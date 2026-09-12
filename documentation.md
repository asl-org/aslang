# ASL — Language Documentation

ASL ("a Software Language") is a statically-typed systems programming
language for mission-critical software. The language is under active
development; this document tracks the syntax that currently parses,
resolves, and analyzes cleanly through the compiler. Anything not
written here is either not yet supported or in flux.

For compiler internals (pipeline phases, AST shapes, design patterns),
see `overview.md`. For the domain vocabulary that parser/resolver/analyzer
types trace back to, see `grammar.md`. For active issues and design
lessons, see `bugs.md` and `lessons.md`.

---

## Source files

ASL distinguishes two file kinds by extension. The compiler enforces
each kind's invariants at parse time.

| Extension | Purpose | May `import` | May host `@extern` | Auto-injected `@std` |
|-----------|---------|--------------|--------------------|----------------------|
| `.asl`    | User source code | yes | yes | yes |
| `.aslr`   | Runtime interface — the boundary between ASL and the host runtime (C, etc.) | no | yes | no |

`examples/base.aslr` is the standard library: every primitive type and
host-provided function is declared there with an `@extern("c_symbol")`
decorator. Application code lives in `.asl` files, which may also declare
their own `@extern` functions when they need to bind a runtime symbol
directly.

Every `.asl` file gets `import "@std"` injected at parse time, so
standard-library types (`u8`..`u64`, `i8`..`i64`, `f32`/`f64`, `String`,
`Status`, `Array`, `Bitset`, `Error`, etc.) are in scope without a
written import line.

---

## Lexical conventions

- **Indentation-based.** Block structure follows indentation (default 2
  spaces; configurable via `--indent-width=N` to 2 or 4). Each nesting
  level must be indented by exactly `indent-width` additional spaces —
  a line indented by anything other than an exact multiple is a parse
  error. There are no braces around blocks and no semicolons between
  statements.
- **Newlines end statements.** A statement runs from the start of a line
  to the next newline; there is no line continuation.
- **Comments.** `#` introduces a line comment; the rest of the line is
  ignored. There is no block-comment syntax.
- **Identifiers.** Head: ASCII letter or `_`. Tail: ASCII letter, digit,
  or `_`. Hyphens are not allowed. Maximum length is 256 characters.
  The `__asl` prefix is reserved for compiler-generated identifiers
  and rejected in user code.
- **String literals.** Double-quoted. Exactly four escape sequences
  are recognized: `\\`, `\"`, `\n`, `\t` — nothing else (no `\r`,
  no `\xNN`, no `\uXXXX`). Consequence: a string literal cannot
  contain a carriage return, so CRLF (`\r\n`) line endings cannot be
  written in source. Text destined for CRLF-expecting consumers must
  get its `\r` bytes from the runtime (e.g. a stdlib helper), not
  from a literal. This is a deliberate design decision, not a gap.
- **Number literals.** Decimal integers (`42`, `-1`), decimal floats
  (`3.14`, `1.5e3`, `-0.5`; exponent marker `e` or `E`). Float
  positions additionally accept the special IEEE-754 forms `nan`,
  `inf`, `+inf`, `-inf` (`nan` cannot be sign-prefixed).
- **Unicode safety.** The tokenizer rejects bidirectional control
  codepoints, zero-width characters, and invisible Unicode (Trojan
  Source defense).

---

## Imports

Three forms, all written at the top of an `.asl` file before any module
or generic declaration. `.aslr` files cannot contain imports.

### Explicit

```asl
import { Foo, Bar } from "./util.asl"
import { Solver as Solution1 } from "./problem001.asl"
import { Foo, Bar as B, Baz } from "./lib.asl"
```

Names listed in braces are brought into scope. `as Alias` rebinds a
name locally.

### Shorthand

```asl
import "./util.asl"
```

Every `public` type from the target file is brought in under its
original name. No braces, no alias list. Useful when you want to use
many names from a single dependency.

### Vendor

```asl
import "@std"
import "@runtime"
```

`@<name>` references a vendor registered via the CLI's `--vendor` flag
(see [CLI](#cli)). The compiler resolves `@<name>` against the vendor
table and treats the entry exactly like a shorthand import of the
mapped file. `@std` is auto-injected in every `.asl` file, so writing
it explicitly is redundant.

### Path rules

Relative paths must stay under the importing file's directory subtree
— `../` and sneaky escapes (`./sub/../../escape`) are rejected. Self-
import (importing the file you are in) is rejected. Importing the same
file twice with different aliases is allowed and produces independent
binding sets.

The `.asl` (and `.aslr`) suffix is **optional** on relative import
paths. If the source ends in `.asl` or `.aslr`, the resolved path is
used as-is. Otherwise the compiler tries the resolved path as
written, then falls back to `<source>.asl`, and finally to
`<source>.aslr`. `.asl` is tried first because user code almost
always imports other user code; the `.aslr` case is a belt-and-braces
last attempt (runtime-interface imports normally flow through
`@<vendor>` paths). Only if none of the candidates exists is an error
raised.

```asl
import { Helper } from "./helper"       # resolves to ./helper.asl
import { Helper } from "./helper.asl"   # same file
import "./util"                         # shorthand form, same fallback
import "./rt"                           # resolves to ./rt.aslr if
                                        # ./rt.asl doesn't exist
```

Because the bare and suffixed forms resolve to the same absolute
path, the loader deduplicates them — writing `./helper` and
`./helper.asl` in the same file imports the file once.

---

## Top-level declarations

Two kinds of declaration may appear at the top level of a file:
**modules** and **generics**. A file must contain at least one of them.

### Modules

A module is the primary unit of organization. It optionally carries a
single data block (struct, union, or literal) and any number of
functions.

```asl
module Pair:
  struct:
    a: u8
    b: u8

  func first(p: Pair): u8
    p.a

  func setA(p: Pair, v: u8): Pair
    p.a = v
    p
```

`public module` exports the module so other files can import it.
Without `public`, the module is file-local.

### Generics

A generic is an interface: a named list of function signatures that any
implementing type must provide. There are no bodies inside a generic
block.

```asl
generic Eq:
  func eq(a: Eq, b: Eq): u8
  func hash(a: Eq): u64

public generic Any:
  func byte_size(): u64
```

A generic name inside its own block self-references — `Eq` in `eq(a:
Eq, b: Eq)` means "whatever type implements me." The **generic
signature rule** restricts every argument/return type root inside a
generic to either the generic itself or a module — other generics are
not accepted.

---

## Data blocks

A module's data block is one of three shapes. The shape determines
what values of the module's type look like.

### `struct` — product type

```asl
module User:
  struct:
    name: String
    age: u32
```

### `union` — sum type with named variants

```asl
module Plan:
  union:
    Free { usage: u32 }
    Pro { users: u32, credits: u32 }
```

Each variant carries its own named fields. Variants may be empty
(`Done {}`).

### `literal` — opaque primitive (only in `.aslr` files)

```asl
public module u8:
  literal: "u8"
```

`literal` declares a primitive type backed by a host-runtime
representation tagged by the quoted name. Values of a literal type are
constructed via literal-initializer syntax (`u8 42`). Only `.aslr`
files may use this shape — application code reuses the primitives the
runtime exposes.

A module may have **at most one** data block. A module with no data
block is a namespace for functions (like `System` in `base.aslr`) —
its functions are callable, but the module itself is not a value:
it cannot be used as an argument type, return type, or field type.

---

## Functions

A function has a parameter list and a return type. User functions
carry a body of one or more indented statements; extern functions are
bodyless.

### User functions

```asl
module M:
  func go(x: u8): u8
    x

  func add(a: u8, b: u8): u8
    sum = u8.add(a, b)
    sum
```

The body's **trailing expression is the return value** — there is no
`return` keyword. Earlier statements bind locals or perform side
effects.

### Public functions

Function overloads are distinguished by their input signature —
the function name plus its argument types. Two functions in the
same module (or funcDefs in the same generic) may not share an
input signature, and the return type does not distinguish them:
call sites could never disambiguate by arguments alone. The
resolver rejects violations with a `duplicate function` error
pointing at both declarations.

`public func` exports the function across module/file boundaries.
Without `public`, the function is module-internal: it is only
callable from inside its own module, and it only counts toward
satisfying a generic constraint there. Writing `Pair[u8]` outside
module `u8` requires every function the constraint demands to be
`public` on `u8` — a private implementation satisfies the
constraint only within `u8` itself. Generic blocks are not modules:
from inside a generic, every module's public functions (and only
those) are visible.

### Extern functions

```asl
public module u8:
  literal: "u8"

  @extern("u8_add_u8")
  public func add(a: u8, b: u8): Status[u8]
```

The `@extern("c_symbol")` decorator names the runtime symbol that
implements the function. The body is replaced by the host
implementation. Extern functions may appear in both `.aslr` and `.asl`
files — `.aslr` is where the standard library declares them, but an
`.asl` file may bind its own runtime symbols too.

### Overloading

Two functions with the same name in the same module are allowed if
their argument lists differ (in count or in type):

```asl
module Foo:
  func bar(a: i64): i64
    a

  func bar(a: String): String
    a
```

Overload resolution happens at the analyzer phase — each call site
unifies against every candidate, and the unique survivor wins.

### Zero-argument functions

```asl
module Foo:
  func start(): u8
    u8 0
```

The empty argument list `()` is accepted.

### Decorators

`@<name>(...)` lines attach metadata to the following function. Today
only `@extern("symbol")` is consumed by the compiler; other decorators
parse but are not yet wired.

---

## Generic modules — struct header

A module can be made generic over one or more types by naming them in a
parenthesised clause on the `struct` keyword itself:

```asl
public module Array:
  struct(Any):
    size: u32

  @extern("array_get")
  public func get(arr: Array[Any], index: u32): Status[Any]

  @extern("array_set")
  public func set(arr: Array[Any], index: u32, item: Any): Status[Array[Any]]
```

`struct(Any):` says: "to use this module you must supply something
that implements `Any`." Use sites then parameterize:

```asl
arr = Array[u32] { size: 100 }
```

A struct's generic parameters can be declared in one of two mutually
exclusive ways:

- **Explicit header** (`struct(Any):`) — used for phantom-type
  parameters that no field mentions, as with `Array` above. Required
  for public APIs whose generics don't surface in field types.
- **Inferred from fields** (`struct: item: T`) — a plain `struct:`
  header with fields typed by a generic name; the generic parameters
  are collected in first-seen order across the fields.

The two modes compose: a struct's generic parameter set is the union of
its explicit `struct(A):` header generics and every generic collected
from its field types — recursing into nested argtypes, so a field typed
`Box[K]` contributes `K`. Header slots come first in the order.

Within the explicit header, every named generic must be distinct —
`struct(K, K):` is rejected with "duplicate generic encountered".

Unions do NOT have an equivalent explicit-header form. A union's
generic parameters are always inferred from its variant field types,
in first-seen order across variants (repeated names keep their
original slot; new names take the next).

### Constraint satisfaction

Writing `Container[T]` obligates `T` to satisfy the slot's generic.
Satisfaction is checked in two stages, both before any function body
is analyzed:

- **At resolve time**: `T` must provide a function for every funcDef
  the generic declares, matched by name and argument count, and
  visible from the file where `Container[T]` is written (a private
  function satisfies a constraint only inside its own module).
- **At definition-analysis time**: the full signatures must match.
  The generic's funcDefs are read with the generic's self-references
  standing for `T`'s own declared shape, and `T` must declare exactly
  those input types AND the exact return type. A `T` whose `compare`
  returns the wrong type is rejected at the `Container[T]`
  declaration even if `compare` is never called.

The constraint generic itself does not need to be in scope at the
use site. Require slots derive in the file that DEFINES the module,
so `import { Container } from "./lib.asl"` suffices even though
Container's slots name `Comparable` — the imported binding carries
its contract.

Satisfaction is a property of the type itself, independent of what
the slots happen to be bound to at any particular site.

### Public modules require public generics

A `public module`'s type parameters are part of its public
interface. If a require slot names a non-public generic — whether
via an explicit `struct(G):` header or inferred from a field typed
`G` — the module's contract references a type its importers can
never see or name: signatures and constraint errors would point at
an invisible type. The resolver rejects this at the defining module:
"public module `M` requires non-public generic `G` — a generic named
in a public module's type parameters must be public". Private
modules may use private generics freely.

---

## Types

### Built-in primitives (declared in `base.aslr`)

- **Unsigned integers:** `u8`, `u16`, `u32`, `u64`
- **Signed integers:** `i8`, `i16`, `i32`, `i64`
- **Floats:** `f32`, `f64`
- **String:** `String`

Each primitive module exposes the usual operations as extern
functions: `add`, `subtract`, `multiply`, `quotient`, `remainder`,
`compare`, bitwise (`and`, `or`, `xor`, `shr`, `shl`, `not`),
`byte_size`, and various `from` conversions.

### Result type — `Status[T]`

Every fallible operation returns `Status[T]` instead of throwing.
`Status` is a union with two variants:

```asl
public module Status:
  union:
    Ok { value: Any }
    Err { error: Error }
```

`Error` carries `{ code: i32, message: String }`. Use `match` on a
`Status` to handle both arms.

### Containers (declared in `base.aslr`)

- **`Array[T]`** — fixed-size array of `T`; field `size: u32`; functions
  `get`, `set`, `byte_size`.
- **`Bitset`** — bit-packed set built on `Array[u32]`; functions
  `init(size)`, `get(index)`, `set(index)`.

### Type-parameter syntax

Type parameters are passed in square brackets:

```asl
Status[u8]
Array[u32]
Map[String, Array[u64]]
Status[Bitset]
```

Nesting is unbounded.

---

## Expressions

### Literal initializers

A primitive value is written as `TypeName literal`:

```asl
u8 0
i64 -1
f64 3.14
f64 1.5e3
f64 -0.5
String.from(42)
```

The type prefix is mandatory — there are no untyped integer literals.

### Local bindings (assignment)

```asl
sum = u8.add(a, b)
arr = Array[u32] { size: 100 }
```

No `let` keyword. The right-hand side is any expression; the
identifier on the left is bound for the rest of the current scope.
There is no shadowing within a single scope.

### Discard binding

```asl
_ = Bitset.set(bitset, num)
```

`_ = expr` evaluates and throws away the result. Use when you want
the side effect (or to assert the call type-checks) without naming a
local.

### Struct initializer

```asl
User { name: n, age: a }
```

Curly braces with `field: value` pairs. Field names must match the
struct exactly. Type parameters (when the struct is generic) are
attached to the type name: `Pair[u8, u8] { a: u8 0, b: u8 1 }`.

### Union initializer

```asl
Status.Ok { value: u8 0 }
Status[u32].Err { error: err1 }
Plan.Free { usage: u32 100 }
```

Type parameters may be attached to the receiver (`Module[T1, T2].Variant
{ … }`) or omitted (`Module.Variant { … }`); at the AST level both write
into the same `UnionRef` shape carrying an `impls` seq (empty for the
bare form, populated for the bracketed form). When impls are omitted the
compiler infers them from the kwarg values, leaving any generic the
variant's fields don't touch at its declared position (leave-as-is).
Explicit impls are needed when the variant alone cannot determine all
type parameters — e.g. `Status[Bitset].Err { error: e }`, where `Err`
only constrains `Error`, not `Bitset`.

### Module-method calls

```asl
u32.add(a, b)
Array.get(arr, i)
Bitset.set(bitset, num)
Solver.start()
System.println("hello")
```

`Module.func(args)` looks up `func` in `Module` (local or imported)
and calls it. There is no implicit `self`. Method calls and free-
function calls share the same syntax.

### Field access

```asl
p.a
bitset.bits
user.name
```

`obj.field` reads a struct field. Only valid when the receiver's type
is a struct module and the field name exists in its data block.

### Field mutation

```asl
p.a = v
bitset.bits = updated_bits
```

`obj.field = expr` writes a struct field. This is a `Setter` statement
(distinct from an `Assignment`, which binds a new local). The analyzer
enforces that the RHS type equals the field's declared type and
rejects mismatches.

---

## Match expressions

`match` is the core branching construct. It takes a subject and one or
more `case <pattern>:` arms; each arm has its own indented body. The
arm's trailing expression is its value, and the entire `match` is an
expression.

```asl
match x:
  case 0:
    u8 1
  case 1:
    u8 2
  case other:
    u8 0
```

A `match` can be used as a statement (its value discarded), or
assigned:

```asl
y = match x:
  case 0:
    String.from("zero")
  case n:
    String.from(n)
```

All arms must produce the same type — the case-arm uniformity check
enforces this.

### Patterns

- **Integer literal** — `case 0`, `case 1`, `case -1` (signed literals
  supported).
- **Wildcard** — `case _` matches anything and discards.
- **Variable binding** — `case other` binds the subject to `other` for
  the arm body.
- **Variant pattern** — `case Variant { field: name, … }` matches a
  variant and destructures its fields. `case Ok { value: v }` matches
  `Status.Ok` and binds the payload to `v`. `case _` works inside a
  variant context too.

```asl
match status:
  case Ok { value: v }:
    use(v)
  case Err { error: e }:
    String.concat("error: ", e.message)
```

### Idiomatic error propagation

`Status` + `match` replaces try/catch. The explicit shape is a tower of
nested `match … case Ok { value: v } / case Err { error: e }` arms:

```asl
func div_ceil(a: u32, b: u32): u32!
  match u32.add(a, b):
    case Ok { value: val1 }:
      match u32.subtract(val1, 1):
        case Ok { value: val2 }:
          u32!.Ok { value: u32.quotient(val2, b) }
        case Err { error: err2 }:
          u32!.Err { error: err2 }
    case Err { error: err1 }:
      u32!.Err { error: err1 }
```

When an arm only unwraps the `Ok` value and re-wraps the `Err`
unchanged, the `try` operator says the same thing in one line: `try f(...)`
evaluates to the unwrapped `Ok` value and short-circuits the enclosing
function with the `Err` otherwise. The tower above collapses to:

```asl
func div_ceil(a: u32, b: u32): u32!
  val1 = try u32.add(a, b)
  val2 = try u32.subtract(val1, 1)
  u32!.Ok { value: u32.quotient(val2, b) }
```

`try` only applies to a call whose return type is a `Status[Value, Error]`,
and it requires the enclosing function to return a `Status` whose error
type matches the callee's `Error` — the propagated `Err` must be well-typed
at the return site. Keep the explicit `match` when an arm does more than
propagate: recovers in the `Err` case, inspects a non-`Status` subject, or
transforms the error.

---

## Visibility

`public` is the only visibility keyword. It applies to:

- **Modules** — `public module M:` exports the module from its file.
- **Generics** — `public generic G:` exports the generic.
- **Functions** — `public func f(...): T` makes the function callable
  across module boundaries. Functions without `public` are only
  callable from inside their defining module.

Modules and generics declared without `public` are file-local and
cannot be imported. Functions in a `generic` block are always callable
(no explicit `public` needed — the generic itself is the boundary).

---

## CLI

```
asl build <filename.asl> [options]

Options:
  --debug               Emit source location comments in generated C
  --dump-tokens         Dump token stream to stdout after tokenization
  --indent-width=<N>    Spaces per indentation level (2 or 4; default 2)
  --vendor=<name>:<path>  Register a vendor (repeatable).
                          Vendor paths are referenced from source as
                          `import "@<name>"`. Default:
                          `std:examples/base.aslr` when --vendor does
                          not include a `std` entry.
  [-o|--output]=<file>  Output binary path (default: input filename
                        without extension)
  [-h|--help]           Show this help message
```

### `--vendor` rules

- The flag is repeatable.
- `<name>` must be a valid ASL identifier (head: letter or `_`; tail:
  letters, digits, `_`).
- `<path>` must point at a readable file (typically `.aslr`).
- Each `<name>` must appear at most once. Duplicate names are rejected
  with both paths in the error.
- `std` is added automatically pointing at `examples/base.aslr` if the
  user does not register their own `std` vendor.

---

## What ASL does not have (yet)

These features are intentionally listed so readers know not to expect
them. Some are planned; others are explicitly out of scope for the
current design.

- **Exceptions / throw / catch.** All fallibility flows through
  `Status[Value, Error]`. The `try` operator (see *Idiomatic error
  propagation*) is Status-based Ok-unwrapping propagation, not
  exception unwinding — there is no `throw`/`catch`.
- **`return` keyword.** A function's trailing expression is its return
  value.
- **Closures / first-class functions.** Functions are not values.
- **Traits / interfaces beyond generics.** The `generic` block plus
  the `struct(...)` header (or field-inferred generics) is the entire
  polymorphism mechanism.
- **Inheritance / subtyping.** No `extends`, no implicit conversions
  between primitives. `u32.from(x: u8)` makes the widening explicit.
- **Mutable globals.** Modules are pure type/function namespaces; no
  module-level mutable state.
- **Operator syntax.** No `+`, `-`, `*`, `/`, `==`. Use the module-method
  forms (`u32.add(a, b)`, `u32.compare(a, b)`).
- **Block-comment syntax.** Line comments only.
- **Generic functions (parametric polymorphism on a function alone).**
  Generics live at the module level — a generic function exists by
  being a function on a module whose `struct(A):` header (or inferred
  field generics) declares a type parameter.
- **Pipe / chain operators.** Nest calls explicitly or bind
  intermediate values.

---

## Worked example

A complete file that exercises modules, struct + union data blocks,
match expressions with variant destructuring, function calls, and
local bindings:

```asl
# Data blocks — one file with two modules, one backed by a struct
# data block and the other by a union data block.
module User:
  struct:
    name: String
    age: u32

  func new(n: String, a: u32): User
    User { name: n, age: a }

module Plan:
  union:
    Free { usage: u32 }
    Pro { users: u32, credits: u32 }

  func describe(plan: Plan): String
    free = Plan.Free { usage: u32 100 }
    match plan:
      case Free { usage: usage }:
        String.from(usage)
      case Pro { credits: credits, users: users }:
        String.concat(String.from(credits), String.from(users))
```

For more, see `examples/` — every fixture has a leading comment
describing what feature it exercises.

---

## Changelog

This section records language changes as they land, newest first.

- **2026-07 (docs sync)** — Documentation aligned with the DDD refactor
  vocabulary locked in `grammar.md`. Parser/resolver/analyzer types now
  use `StructDef` / `UnionDef` / `LiteralDef` (was `Struct` / `Union` /
  `Literal`), `Setter` is a Statement variant (was an Expression), and
  `StructRef` / `UnionRef` carry a single `impls` seq at every layer
  (was two arms — default vs impl). No surface-syntax changes; the
  edits are internal-vocabulary alignment.

- **2026-07 (later)** — Optional `.asl` / `.aslr` suffix on relative
  imports. Import sources like `import { Helper } from "./helper"`
  (no extension) now resolve. `toAbsPath` in
  `src/analyzer/resolver/parser.nim` treats the extension as optional: if the
  source ends in `.asl` or `.aslr`, use as-is; otherwise try the
  resolved path first, then fall back to `<source>.asl`, then
  `<source>.aslr`. `.asl` is preferred because user code almost
  always imports other user code; `.aslr` is a last-chance attempt.
  Only if none of the candidates exists is an error raised. Both
  `./helper` and `./helper.asl` in the same file resolve to the same
  absolute path so the BFS loader deduplicates them.

- **2026-07** — Float-literal exactness is a warning, not an error.
  The `isExactlyRepresentable` rational-form check (introduced in
  the previous entry) is now consulted from `analyzeFloatLiteral`
  after a successful parse. If the source literal cannot be
  represented exactly in the target float kind, the compiler
  accepts the closest approximation *and* writes a `[WARN]` line
  to stderr identifying the literal and its source location:

  ```
  [WARN] path/to/file.asl:3:9 literal `1.62` cannot be exactly
        representable in 64-bit float; using closest approximation
  ```

  Lossy literals like `f64 1.62`, `f64 0.1`, `f32 0.05` compile
  successfully; users are informed at the literal site so they can
  choose to rewrite as a runtime quotient of exact-integer literals
  (`f64.quotient(f64 162.0, f64 100.0)`) if the imprecision
  matters. The previous "TEMP" markers around the exactness call
  sites in `parseFloat[T]` are removed; the check now lives at the
  analyzer's literal-body boundary.

- **2026-06 (late)** — Float-literal analyzer + stdlib numeric build-out.
  The analyzer now validates `f32` / `f64` literal initializers
  (`f64 0.5`, `f32 1.5e3`): syntactic floats parse via the new
  `parseFloat[T: SomeFloat]` helper in `analyzer/patterns.nim`,
  which range-checks against the target kind, rejects `±Inf` / `NaN`
  (TODO marker covers the future special-value forms), and for
  `f32` adds a round-trip narrowing test so values that fit in
  `f64` but not `f32` are caught at the literal site. An exact-
  representability check (`isExactlyRepresentable(text, mantissaBits)`)
  is implemented for both kinds but currently **disabled** behind a
  TEMP comment so day-to-day numeric code (`f64 1.62`, `f64 0.05`)
  doesn't yet need to be spelled as runtime quotients. Re-enabling
  it is a one-line uncomment in `patterns.nim`.

  `base.aslr` gains a wider numeric surface:

  - **Integer–float casts:** `u32.from(f32)`, `u32.from(f64)`,
    `u32.from(i64)` (all `Status[u32]`), `u64.from(f64): Status[u64]`,
    `i64.from(u32): i64`, `f32.from(u32)`, `f64.from(u32)`,
    `f64.from(u64)`.
  - **`i64` utilities:** `abs` (extern), `clamp(x, lo, hi)`,
    `softmax(x)` (max with zero), `negate(x): Status[i64]`.
  - **`f64` utilities:** `clamp(x, lo, hi)`, `softmax(x)`,
    `negate(x): Status[f64]`.
  - **`f32` / `f64` numeric operations:** `compare(a, b): i8`,
    `abs(a)` — closing the parity gap with the integer modules.
  - **`String.from(...)` for every numeric kind:** `u8`, `u16`,
    `u32` (already present), `u64`, `i8`, `i16`, `i32`, `i64`,
    `f32`, `f64` — so `String.concat` chains can render any numeric
    type for `System.println`.

- **2026-06** — Vendor mechanism + `.asl` / `.aslr` file split.
  `--vendor="<name>:<path>"` CLI flag (repeatable, dedup-checked).
  `import "@<name>"` syntax. `.asl` and `.aslr` extensions carry
  different invariants (imports allowed only in `.asl`; externs only
  in `.aslr`). `@std` is auto-injected in every `.asl` file.
