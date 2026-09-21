# Plan — Monomorphization + value-semantics memory management

**Status**: design. Refines `plans/plan_lifetime_analysis.md` (the value
graph + clone/free) and feeds `plans/plan_dag_ir.md` (kernels, WCET,
SystemVerilog). The headline change since those docs: **fully
monomorphize after analysis**, lower to a concrete C-typed AST, and run
the lifetime/ownership analysis on *that* — no generics survive to
codegen.

## North star: this exists to reach hardware

The end target is C now, and **Verilog/VHDL** down the line. That goal
is what makes monomorphization non-optional rather than a nice-to-have:

- **Hardware is inherently monomorphic.** HDL modules have fixed-width
  ports and fixed structure. There is no runtime type info, no dynamic
  dispatch, no witness tables, no `void*`. A generic `Box[T]` has no
  gates until `T` is concrete. You cannot synthesize what isn't
  specialized.
- **No dynamic allocation / no heap.** Hardware has fixed
  registers/BRAM/wires — everything needs a compile-time-known size and
  lifetime. This is why the whole memory story (bump/region allocation,
  `byte_size` as a compile-time constant, fixed kernel scratch, WCET)
  converges on the hardware target.
- The HDL goal **settles earlier design questions**: static, compile-time
  ownership marking beats runtime reference counting outright (a
  Koka-style `if rc==1` at each op needs refcount registers + data-
  dependent branches — wasted area, non-deterministic timing, fights
  synthesis). There was never a runtime-refcount option here.

Consequences that only the hardware target imposes (design for them now):

- **Everything must be bounded.** Unbounded recursion doesn't synthesize
  (the `@depth`/termination story from plan_dag_ir graduates to
  mandatory), and **persistent Array/Map need a compile-time max
  capacity** to map to fixed BRAM. Design the collection types with a
  capacity bound from the start; it is far easier than bolting it on.
- **Bit-width narrowing is a first-class payoff.** Monomorphization plus
  value-domain analysis (plan_dag_ir Step 7/14) lets a `u32` provably in
  `[0..99]` become a 7-bit signal — area and power on FPGA. You cannot
  narrow a generic; specialization unlocks it.
- **Lifetime analysis IS resource allocation.** On a CPU it decides
  bump-offsets and frees; in hardware it decides register/BRAM
  assignment and reuse. "Clone" = route to a second register/BRAM;
  "in-place mutation" = write back to the same register; "free at scope
  exit" = that storage is available next cycle. The pass isn't analogous
  to hardware allocation — it *is* it.
- **Kernel extraction = the netlist.** The pure-kernel split (effect
  boundaries → I/O ports, pure interior → combinational/pipelined
  module) only works once everything is concrete. Monomorphize →
  concrete kernels → each a synthesizable module.

## The pipeline

    analyze (AnalyzedApp)
      → monomorphize        (specialize generics; concrete C-typed AST)
      → lifetime / ownership (on the concrete AST; in-place vs copy)
      → codegen             (C now; Verilog/VHDL later)

Monomorphization runs **after** analysis (concrete argtypes + the
impl-map's concrete `ResolvedFunctionDef`s are available) and **before**
the value-graph / lifetime pass, which then operates on a fully-concrete
program: no generic arms anywhere, direct calls, known layouts.

The driver already exists: the **demand-driven-from-`start` walk** (the
interner) is the monomorphization worklist. `start(): i32` is fully
concrete, so you propagate concrete types down through call sites,
specializing each generic function per concrete instantiation reached.
The impl-map's concrete defs are how codegen picks the concrete
function for a former constraint call (`Any.byte_size(x)` on a `u8`
becomes a direct `u8.byte_size`).

## Memory model: value semantics, optimized by lifetime

### The reduction

The analyzed body has five expression kinds: function call, initializer,
setter, getter, match. Of these, only **initializer** and **setter**
*retain* a value; getter / match / variable / function-call are reads (a
call is read-only over its args plus whatever its body does,
recursively). So "does this consume?" collapses to two node kinds, and

    setter  =  initializer + one field update  (copy-on-write)

unifies them. Caveat to state explicitly: library *producers*
(`Array.assoc`, `Map.dissoc`, `String.concat`) also retain their inputs,
but those are compiler-owned runtime primitives, not user code — so
consumption lives in init/setter for everything the compiler analyzes,
and the retaining happens inside a fixed, known set of externs.

### Spec vs. implementation

- **Spec: value semantics.** Initializer/setter behave as if they clone;
  nothing is mutated in place; every value is immutable/read-only. This
  is the mental model and the correctness baseline, and it makes
  process/module boundaries trivial (an immutable, self-contained value
  copies/serializes cleanly across an address space or clock domain — no
  shared mutable state).
- **Implementation: lifetime analysis recovers efficiency.** The clone
  is elided when the analysis proves the source is uniquely owned
  (last use, no live aliases) — Perceus / functional-but-in-place, but
  decided **statically** (compile-time marking), not by runtime
  refcount.

### The cost-driven split

- **Structs / unions → plain C aggregates.** Fixed, small, cheap to
  copy — they never need the persistent (structural-sharing / COW)
  machinery. Unique ⇒ mutate in place; shared ⇒ shallow-copy. This is
  the "get rid of persistent data structures" win, *for these types*.
  Consider not even doing in-place for structs: always shallow-copy (the
  copy is trivial for a fixed size, and proving uniqueness buys almost
  nothing there). Reserve the harder ownership analysis for the
  collections, where a copy is O(n).
- **Array / Map → persistent, but transient-marked.** Copy is O(n), so
  keep structural sharing for the shared case and flip individual ops to
  **transient (in-place)** when the receiver is uniquely owned — Clojure
  transients / Roc opportunistic mutation, but *automatic*, driven by
  ownership rather than manual `transient!` / `persistent!`. Codegen
  picks the transient vs. persistent runtime primitive per op. For HDL
  these are **bounded-capacity** (fixed BRAM).

So it is not "get rid of *all* persistent structures" — structs/unions
become mutable C aggregates; only the two collection types stay
persistent, and even those go in-place when the compiler can prove it.

### Boundaries

Share immutably *within* a kernel/process; clone-to-self-contained only
when a value crosses a boundary (process, module, clock domain). The
boundary is the single clone/serialize point (this is where a
serialization format — JSON or a packed binary — comes in), and inside a
kernel you keep structural sharing's cheapness.

## The two gotchas

Both share a shape: the optimization fires only on a positive proof, and
the fallback must be safe and well-defined. For #1 the safe fallback is
*reject the program*; for #2 it is *copy instead of mutate*.

### Gotcha 1 — monomorphization termination (type growth, NOT runtime loops)

Monomorphization terminates iff the set of `(function, concrete-type-
args)` instantiations reachable from `start` is **finite**. It diverges
when a function is instantiated at ever-growing types — a type parameter
reappearing in a structurally deeper position in a recursive call.

**Crucial distinction: this is not the same as runtime termination.** A
program can halt at runtime and still be non-monomorphizable:

```
func poly(x: T, n: u32): u8
  match u32.eq(n, 0):
    case true:  u8 0
    case false:
      boxed = Box[T] { value: x }
      poly(boxed, u32.sub(n, 1))   # type grows to Box[T], but n counts DOWN
```

`poly` terminates at runtime (`n` → 0). Any loop/termination analysis
says "halts." But the monomorphizer follows the **type** (`Box[T]`), not
the runtime value `n`: `poly[u8]` → `poly[Box[u8]]` →
`poly[Box[Box[u8]]]` → … forever. So:

- The check is **type-level** (do the instantiation's type args grow?),
  not a control-flow-loop check.
- It runs **during** monomorphization, on the **instantiation graph** —
  not "after lowering." The specializer would hang before any lowered
  CFG exists to detect a loop in.

**Detection — an occurs-check on the instantiation path.** The name is
borrowed from unification, and the idea is the same: before making a new
specialization, check whether its type *contains* the type of a
same-function ancestor you are already inside. If it does, the type is
snowballing and never stops. Intuition: "am I building a box that
already has one of my ancestors nested inside it?"

Keep a **stack of ancestors** — the chain of `(function, type-args)`
currently being specialized on the path from `start`:

    start
      → poly[u8]              ← ancestor
        → poly[Box[u8]]        ← ancestor
          → poly[Box[Box[u8]]]  ← about to make this

When about to specialize `f` at args `A`, look at the ancestors on the
stack whose function is also `f`, and compare `A` against each such
`f[B]`:

- **`A == B`** (same args) → been here; it's a normal recursive call.
  Reuse the existing specialization (dedup). Fine — a healthy
  self-recursive function; do NOT reject.
- **`A` properly contains `B`** (B nested inside A) → the type grew; the
  chain snowballs forever → reject:

  > `polymorphic recursion at <loc>: poly instantiated at ever-growing
  > types (u8 → Box[u8] → …); cannot monomorphize`

- **neither** → unrelated so far; push `f[A]` and keep walking.

"Properly contains" is a subterm test on the type *tree*. `Box[Box[u8]]`
is `Box(Box(u8))`; to ask whether it contains `Box[u8]`, walk its
sub-trees and test each for structural equality — the child `Box[u8]`
matches → contained. Equality is the argtype `==` / `hash` you already
have, so each check is cheap.

Shape:

    specialize(f, A, stack):
      if (f, A) already done: return              # dedup
      for (g, B) in stack where g == f:
        if A == B:            return              # normal recursion
        if contains(A, B):    error "polymorphic recursion ..."
      push (f, A) onto stack
      for each call (h, C) in f's monomorphized body:
        specialize(h, C, stack)
      pop stack; mark (f, A) done

    contains(A, B) = does any sub-tree of A structurally equal B?

Two cases side by side:

    poly:  start → poly[u8] → poly[Box[u8]]
           check: is u8 inside Box[u8]? YES → REJECT (on the FIRST grow)

    sum:   start → sum[u32] → sum[u32]
           check: u32 == u32? YES → dedup, converged → FINE

So it is *not* "reject cycles in the instantiation graph" — an equal-args
cycle is exactly a healthy recursive function. Reject only strictly-
growing chains: equal = converged, subterm-of-ancestor = shrinking (also
fine), properly-contains-ancestor = diverging (reject).

**Why not just a depth limit (what Rust does).** Rust's type system
accepts polymorphic recursion (it is well-typed); the mono collector
then notices a same-`DefId` re-instantiation with a longer type and
counts it against `recursion_limit` (default 128), erroring only after
that many growing levels ("reached the recursion limit while
instantiating `foo::<Box<Box<...>>>`"). That is a *cap*, not a decision
procedure — imprecise (deep-but-finite code can trip it, hence the
`#![recursion_limit]` escape hatch), but robust (guaranteed to halt on
anything, since full monomorphization termination is undecidable in
general). The occurs-check above is more precise for the common pattern
— it fires on the *first* growing step with a clear diagnostic instead
of grinding out 128 levels — and is affordable here because ASL's
generics are simple (constraint bounds, not higher-kinded). Keep a
**max-instantiation-depth cap as the seatbelt** behind the occurs-check
for exotic growth the subterm test does not model: the occurs-check
gives the precise message, the depth cap guarantees halting.

**Worked example — recursive data types are fine; only type-argument
growth is rejected.** The occurs-check does not fire on a type that
refers to *itself*; it fires only when a type *argument* grows along the
instantiation path. These are different things, and the difference is
exactly the line between "monomorphizable" and "not". Consider the AST a
self-hosting ASL compiler would need:

```
union Expression:
  FunctionCall
  Initializer

struct FunctionCall:
  callee: String
  args:   List[Expression]      # function calls can be passed as args

struct Initializer:
  typeName: String
  fields:   List[Expression]    # field values recurse into Expression
```

Monomorphize from `start` and the set of types reached is:

    Expression, FunctionCall, Initializer, List[Expression], String

Five types — a fixed point. When we expand `List[Expression]` and look at
its element we get `Expression`, which is **already an ancestor on the
stack**. That is the `A == B` arm: dedup, reuse, stop. Nothing grew, the
type set is finite, monomorphization succeeds. Value-level self-reference
(a `FunctionCall` value holding a `List` of `Expression` values) is
*regular* recursion — it closes back onto a type already in the set.

Contrast the two shapes directly:

    Expression:  ... → List[Expression] → Expression   (== ancestor → dedup, FINITE)
    poly:        poly[u8] → poly[Box[u8]] → poly[Box[Box[u8]]] → …  (⊃ ancestor → REJECT, INFINITE)

`Expression` re-encounters the *same* type; `poly` manufactures a
*strictly larger* type-argument every step. Same-type re-encounter = the
dedup arm; larger-type re-encounter = the growth arm. The check
discriminates self-reference from growth — it does not ban self-reference.

**Do real programmers write the `poly` shape?** Yes, but in one narrow
niche: typed-FP **non-regular (nested) datatypes**, where the type
parameter deliberately changes on the recursive step to encode an
invariant in the type. Real examples that ship:

- **Finger trees** (`Data.Sequence`): `Deep (Digit a) (FingerTree (Node
  a)) (Digit a)` — the middle recurses at `Node a`, so element type wraps
  a level deeper each descent. Any traversal is polymorphically recursive.
- **Well-scoped de Bruijn terms**: `Lam (Term (Maybe a))` — the bound-var
  count lives in the type, so scope errors are unrepresentable.
- **Perfect trees / Okasaki bootstrapped structures**: `Node (Tree (a,
  a))`; a fold recurses at `Tree (a, a)`.

The punchline for *this* language: **every one of these is
fundamentally non-monomorphizable, by construction** — they reach
infinitely many distinct types. Haskell runs them only because it does
*not* monomorphize (uniform boxed representation + runtime dictionaries).
Rust rejects them (`recursion_limit`), C++ rejects them (template depth),
for the identical reason our occurs-check would. There is no finite set
of concrete structs — and certainly no bounded hardware layout — for
`FingerTree (Node (Node …))` unrolled forever. So rejecting the `poly`
shape costs us nothing we could otherwise compile: the occurs-check draws
the line at exactly the monomorphizability boundary. In ordinary systems
code targeting hardware the check will essentially never fire; when it
does, it has caught a program that had no monomorphic (or physical)
meaning to begin with.

### Gotcha 2 — transient soundness (mis-proved in-place = silent corruption)

A wrongly-marked transient op mutates a collection another holder still
points at → silent wrong data (and in HDL, a wrong netlist). Example:

```
func oops(): Pair
  a = Array.push(Array.new(), u32 1)   # a = [1]
  b = a                                # b points at the SAME array
  c = Array.push(a, u32 2)             # a and b share storage here
  Pair { first: c, second: b }
```

If the second push is wrongly transient, it writes `2` into the one
array `b` also holds → `b` silently becomes `[1, 2]`. The sound reading:
`a` has two live consumers (`b` and the push) → in-degree 2 → not unique
→ the push must **copy** (persistent). Then `b` stays `[1]`, `c` is
`[1, 2]`.

The good news, mostly-handled by good lowering: if the lowered **value
graph** collapses `b = a` to the *same node* (aliasing = shared in-edges,
not a copy), uniqueness falls out of the structure — in-degree > 1 ⇒
shared ⇒ copy; in-degree 1 and last use ⇒ transient. The `oops` case
self-solves. The graph doesn't remove the analysis, it makes it
mechanical (run in-degree + last-use + escape-reachability over it).

Make it sound by construction:

- **Polarity.** A **must-be-unique** analysis with **copy/persistent as
  the safe fallback**: in-place fires only on proof; "unknown" or
  "probably unique" both fall to copy. A bug then costs performance, not
  correctness.
- **Aliasing sources to refute** before marking transient (most fall out
  of the value graph): in-degree > 1; stored into a still-live
  aggregate; retained by a call (its ownership summary); escapes via
  return; crosses a boundary where a copy exists.
- **Interprocedural retention** is the one thing the local graph can't
  resolve on its own — whether `f(a)` stores/returns `a`. Handled by
  `f`'s ownership summary, or, since whole-program monomorphization makes
  aggressive inlining natural, by inlining `f` (then it's intraprocedural
  and the graph handles it). Fallback when not inlined: assume retained →
  copy.
- **Adversarial.** Because the failure is silent, try to *refute*
  uniqueness for each transient decision; mark transient only if
  refutation fails.

Two safety nets, given "silent":

- **Runtime uniqueness assertions in the sim/debug build.** Carry a cheap
  "shared?" bit (or debug refcount) and assert unique at each in-place
  op; compile it out for release/HDL. Lets you *empirically validate*
  the static analysis across the test corpus on the CPU/sim build —
  exactly where corruption is otherwise unobservable.
- **A formal obligation per transient op.** Emit `@requires unique(coll)`
  (ties into the Frama-C/ACSL layer in plan_dag_ir) and let the prover
  discharge it, turning "did I mis-prove uniqueness?" into a checked
  proof obligation.

## Build order (incremental, correctness-first)

Every step ships correct; later steps only remove copies / enable
in-place.

1. **Monomorphize** with the memo/worklist; reject strictly-growing
   instantiations (subterm occurs-check, depth-cap seatbelt). Output: a
   concrete C-typed AST, zero generics.
2. **Conservative memory**: always shallow-copy structs, always
   persistent for Array/Map. Correct, no ownership analysis yet.
3. **Struct in-place** (optional): mutate unique structs instead of
   copying — or skip, and keep structs always-copy if the analysis
   doesn't pay.
4. **Transient marking** for Array/Map: run the must-be-unique analysis
   on the value graph; flip provably-unique ops to in-place. Add the
   debug uniqueness assertions.
5. **Formal obligations** (`@requires unique`) once the ACSL layer
   exists.

## Open decisions

- **Struct in-place at all?** Always-copy structs is dead simple and
  cheap (fixed size); the uniqueness proof may not be worth it. Decide
  whether structs get the in-place path or stay dumb-copy.
- **Type monomorphization vs. code-only.** Structs/unions are pointer-
  backed (`"pointer"` ctype), so their layout is uniform regardless of
  `T` — you may not need to duplicate the *type*, only the *code* that
  computes sizes/clones/dispatches. Deciding this bounds the code-size
  blowup.
- **Collection capacity model** for HDL — how a bounded Array/Map max
  size is declared and threaded to BRAM sizing.
- **Boundary serialization format** (JSON vs. packed binary) for the
  clone-at-boundary point.
