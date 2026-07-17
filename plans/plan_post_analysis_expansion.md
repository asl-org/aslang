# Post-analysis expansion

Position in the pipeline:

```
Parser → Resolver → Analyzer → Post-analysis expander → DAG IR (Steps 1-20)
```

The expander is a **mechanical tree-to-tree rewrite** that runs after
the analyzer. Its job is to lower every declarative construct in the
source language (literals, structs, unions, enums, initializers,
getters, setters, `match`, `try`, `for`) into a uniform IR whose only
computation node is the function call. Everything downstream (the DAG
IR pipeline in `plans/plan_dag_ir.md`) then reasons about exactly one
shape.

The expander is intentionally small because the analyzer has already
done the heavy lifting.

---

## Contract

- **Input**: an AST that the analyzer has already validated —
  syntactically clean, fully name-resolved, fully typed, generics
  monomorphized, `match` exhaustiveness proven, `try`-position
  constraints satisfied, tag-flow narrowing complete.
- **Output**: a lowered AST containing only function calls,
  literals, and control flow. Every declarative construct in the
  input has been rewritten into a call to either an `@extern` or
  a `@generated` function.
- **Guarantees**: preserves the source location of every syntactic
  form it rewrites (see § Source location preservation).
- **Non-goals**: does not type-check. Does not validate. Does not
  resolve names. Does not diagnose user errors. Every failure is
  an expander bug, not a user error.

Because the input is known-valid, the expander has no error paths,
no fallback logic, no "what if this type is generic" branches, and
no runtime guards to synthesize. Access to a variant field on the
wrong tag can't reach the expander; the analyzer rejected it.

---

## `@extern` vs `@generated`

Two annotation categories with distinct semantics:

- **`@extern`** — body is **opaque** to the compiler. Defined
  outside ASL (in `base.aslb`, the C runtime, or hardware). Used
  for universal primitives that don't depend on user-defined layout
  (`u8_init`, `u32_add`, `syscall_write`, `Point_byte_size` for
  layout-independent size queries).
  - May be marked `@effect` if the operation touches the world.
  - Not inlinable by Step 10 (the compiler doesn't have the body).
  - Signature-only in the IR.

- **`@generated`** — body is **known** to the compiler.
  Synthesized by the expander from the analyzer's field table
  (struct field order + widths, union variant table, enum tag
  table). Used for layout-dependent operations (`x(p: Point)`,
  `Ok_value(r: Result[T])`, `__asl_branch_id(r)`).
  - Always pure. Never `@effect`.
  - Always inlinable by Step 10 (the compiler has the body).
  - Body is emitted as DAG IR nodes directly (see § Body
    representation).

The distinct annotations let Step 10 (whole-program inlining)
inline `@generated` calls unconditionally without re-checking
inlinability. `@extern` calls stay opaque and become the boundaries
Step 20 (pure kernel extraction) cuts on.

---

## Expansion tables

### Literal block

Source:
```
literal: "u8"
```

Expansion:
```
@extern("u8_init")
public func init(value: u8): u8

@extern("u8_byte_size")
public func byte_size(): u32
```

All arithmetic / logical / comparison primitives on `u8` are
declared elsewhere (also `@extern`) — the literal block itself only
emits `init` and `byte_size`.

### Struct block

Source:
```
struct Point {
  x: i32
  y: i32
}
```

Expansion:
```
@extern("Point_byte_size")
public func byte_size(): u32

@generated
public func init(x: i32, y: i32): Point

@generated
public func x(__asl_ptr: Point): i32                     # getter
@generated
public func x(__asl_ptr: Point, __asl_x: i32): Point     # setter (returns new)

@generated
public func y(__asl_ptr: Point): i32
@generated
public func y(__asl_ptr: Point, __asl_y: i32): Point

@generated
public func free(__asl_ptr: Point): u32                  # bytes released
```

Getter and setter share the field name; overload discriminated by
arity. Setter returns a new `Point` (pure). Step 5's `vcLinear`
refcount case gives it zero-copy in generated code when the input
has one consumer.

### Union block

Source:
```
union Result[T] {
  Ok(T)
  Err { code: u32, msg: str }
}
```

Expansion:
```
@extern("Result_byte_size")
public func byte_size(): u32

# variant constructors
@generated
public func Ok(__asl_val: T): Result[T]

@generated
public func Err(__asl_code: u32, __asl_msg: str): Result[T]

# compiler-added discriminant reader
@generated
public func __asl_branch_id(__asl_ptr: Result[T]): u32

# per-variant field accessors — prefixed by variant name
@generated
public func Ok_value(__asl_ptr: Result[T]): T
@generated
public func Ok_value(__asl_ptr: Result[T], __asl_val: T): Result[T]

@generated
public func Err_code(__asl_ptr: Result[T]): u32
@generated
public func Err_code(__asl_ptr: Result[T], __asl_val: u32): Result[T]

@generated
public func Err_msg(__asl_ptr: Result[T]): str
@generated
public func Err_msg(__asl_ptr: Result[T], __asl_val: str): Result[T]

@generated
public func free(__asl_ptr: Result[T]): u32
```

Notes:

- The compiler adds one hidden field `__asl_branch_id: u32` to
  every union. Constructors write it; `__asl_branch_id` reads it.
- Per-variant getters and setters use `<Variant>_<field>` naming.
- **Empty variants** (per `project_empty_variants_vs_structs.md`)
  emit only their constructor — no getters, no setters. Example:
  `None(): Option[T]` and nothing else.
- Variant field access is total. The analyzer already proved the
  tag; no runtime tag check inside the generated getter.

### Enum block

An enum is a union whose every variant is empty. Source:

```
enum Color { Red, Green, Blue }
```

Expansion:
```
@extern("Color_byte_size")
public func byte_size(): u32

@generated
public func Red(): Color
@generated
public func Green(): Color
@generated
public func Blue(): Color

@generated
public func __asl_branch_id(__asl_ptr: Color): u32

@generated
public func free(__asl_ptr: Color): u32
```

Same rules as unions with empty-only variants. No per-variant
getters or setters.

---

## Call-site rewrites

The expander also rewrites source expressions into calls to the
generated / extern functions above.

| Source expression                              | Lowered form                                  |
| ---------------------------------------------- | --------------------------------------------- |
| `p.x`                                          | `x(p)`                                        |
| `p.x = 3`                                      | `x(p, 3)` (returns a new `Point`)             |
| `Point { x: 3, y: 4 }`                         | `Point.init(3, 4)`                            |
| `r.Ok_value`                                   | `Ok_value(r)` — analyzer proved `r` is `Ok`   |
| `Result.Ok(42)`                                | `Ok(42)`                                      |
| `match r: Ok(v) -> f(v), Err(c, m) -> g(c, m)` | `__asl_branch_id(r)` dispatch — see below     |
| `try foo()` (expression)                       | tag check + early return + `Ok_value` unwrap  |
| `for x in xs: body(x)`                         | tail-recursive helper (per Step 8 spec)       |

### `match` lowering

```
match r:
  Ok(v)      -> f(v)
  Err(c, m)  -> g(c, m)
```

lowers to:

```
let __asl_tag = __asl_branch_id(r)
if __asl_tag == 0:            # Ok = 0 by declaration order
  let v = Ok_value(r)
  f(v)
elif __asl_tag == 1:          # Err = 1
  let c = Err_code(r)
  let m = Err_msg(r)
  g(c, m)
```

Tag values are assigned by declaration order in the union block.
Exhaustiveness is guaranteed by the analyzer; no `else` arm needed.

### `try` lowering

```
let x = try foo()
# continuation using x
```

lowers to:

```
let __asl_tmp = foo()
if __asl_branch_id(__asl_tmp) == 1:  # Err
  return __asl_tmp                    # propagate up
let x = Ok_value(__asl_tmp)
# continuation using x
```

The analyzer has already validated the `try`-position constraint
(PC-3 in `plans/plan_try_operator.md`): the enclosing function
returns `Result[U]` for some `U`, so the early `return __asl_tmp`
type-checks. Expander just emits it.

### ANF flattening

Compound expressions like `foo(bar(baz()))` were preserved through
the analyzer for clean error messages. The expander flattens them
into single-assignment temps at this stage:

```
foo(bar(baz()))
```

becomes:

```
let __asl_arg_1 = baz()
let __asl_arg_2 = bar(__asl_arg_1)
let __asl_result = foo(__asl_arg_2)
```

`__asl_arg_N` naming matches the temporary convention already used
elsewhere in the compiler.

---

## Source location preservation

Every node the expander synthesizes carries the source span of the
syntactic form it came from:

- `x(p)` carries the span of `p.x` in source.
- `x(p, 3)` carries the span of `p.x = 3`.
- `__asl_tag` carries the span of the `match` keyword.
- `__asl_arg_1` carries the span of the sub-expression it uplifted
  (`baz()` in the ANF example).
- Generated function *declarations* carry the span of the block
  they were synthesized from (the whole `struct Point` block for
  `Point`'s getters/setters).

Errors surfacing after expansion (in Step 10 inlining, Step 12
parallelism warnings, Step 13 WCET violations, Step 17 codegen
diagnostics) still point at the user's source, never at synthesized
temps or generated declarations.

---

## Body representation

Generated function bodies are emitted as **DAG IR nodes directly**,
skipping the parser and analyzer. Rationale:

- Bodies are structurally trivial: one memory load (getter), one
  memory store returning the new value (setter), one tag compare
  (`__asl_branch_id`), one struct-populate sequence (constructor).
- Types are already known — round-tripping through the analyzer
  would recompute what the expander already has.
- Skipping the round-trip keeps the pipeline linear and avoids
  bootstrapping questions (the expander itself runs post-analysis).

Alternative rejected: emitting bodies as ASL source that re-enters
the parser. Homogeneous but wasteful — no user-facing benefit and
adds a re-entrant loop to a pipeline that's otherwise a straight
line.

---

## Interaction with Step 10 (whole-program inlining)

- **`@generated` calls** are always inlined by Step 10 —
  unconditionally, with no cost heuristic. After Step 10, no
  `@generated` calls remain in the DAG.
- **`@extern` calls** stay opaque. Their signatures plus `@effect`
  annotations feed:
  - Step 10's effect propagation (pure vs effect classification of
    every user function transitively).
  - Step 20's boundary detection (effect externs are the cut points
    for pure kernel extraction).

Consequence: the "everything is a function call" IR is a *shape*
guarantee at the input to Step 10; by the time we reach Step 20,
the only calls left are the effect boundaries. Kernel bodies are
inline DAG nodes with zero function-call overhead.

---

## What the expander does NOT do

Because the input is validated by the analyzer:

- No type checking.
- No name resolution (resolver did it).
- No generic monomorphization (analyzer did it).
- No tag validation for variant field access (analyzer proved it).
- No exhaustiveness check for `match` (analyzer proved it).
- No `try`-position constraint check (analyzer proved it).
- No error diagnostics for user code — the expander cannot produce
  a user-facing error. Every failure is a compiler bug.

This is what keeps the expander small. The rewrites in this
document plus the two-column source-to-lowered table above are
essentially the whole spec.

---

## Sequencing

1. Ship the resolver rewrite in progress (see
   `project_resolver_state` — snapshot 2026-04-30).
2. Ship the analyzer's remaining shape / typing work (post-milestone
   from the current commit `acc8997`).
3. Land the post-analysis expander as its own peer layer under the
   analyzer — `src/analyzer/expander/`. Rewrite tables from § Call-
   site rewrites first, `@generated` synthesis (§ Expansion tables)
   second.
4. Wire the expander's output into Step 1 (build DAG) from
   `plans/plan_dag_ir.md`.
5. Reframe Task 21 (`try`) to add `ekTry` as a first-class AST
   variant that the resolver and analyzer both understand; the
   desugar-to-tag-dispatch happens in the expander per this
   document's § Call-site rewrites.
6. Retire the old parser-time expander (`parser/body.nim`'s
   `expand*` procs) — its work is now covered by the post-analysis
   expander plus the DAG builder's natural ANF form.

---

## Cross-references

- `plans/plan_dag_ir.md` — consumer of this expander's output; Step
  10 relies on the `@generated` inlinability guarantee and Step 20
  relies on the `@effect` extern boundary invariant.
- `plans/plan_try_operator.md` — reframed: `try` is a language
  feature (AST variant), not a macro. The lowering in § Call-site
  rewrites replaces the macro rewrite the original plan described.
- `plans/plan_deferred_typing.md` — its Q9 discussion of `try`
  should be revisited under the language-feature framing.
- `project_empty_variants_vs_structs` — the "empty variants get
  only a constructor" rule follows from this memory.
