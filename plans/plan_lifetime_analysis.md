# Plan — Lifetime / Ownership Analysis (persistent, clone-and-free)

**Status**: design. A skeleton has landed (`src/lifetime.nim`,
`analyzeLifetime`), kept OFF the CLI compile path until it handles every
construct. This document is the codebase-grounded refinement of
`plans/plan_dag_ir.md` — same destination (a per-function graph with
Perceus-style reuse), but reasoned against the *actual* `Analyzed*`
output and with the ownership model made precise. Where the two
disagree, this doc wins.

## Goal

ASL values are **persistent / immutable**: every "mutation" produces a
new version that structurally shares memory with the old one. On a
bump-allocated, GC-free runtime (`examples/allocator.c`), the compiler
must decide, per function reachable from `start`:

1. **Where each value dies** — so its memory can be reclaimed (pop the
   bump watermark at scope exit for everything that does not escape).
2. **Whether a value's memory can be reused or must be copied** when it
   is reshaped — so we insert the minimum number of clones.

That's the whole job: **auto-insert clones and frees** so a
persistent-data program runs with deterministic, statically-known
memory and no garbage collector.

## The core insight — "consumed" is NOT a property of the function

In an immutable world *nothing is destroyed by a call* — the old value
stays valid. So reusing a value's memory is legal at a point **exactly
when two facts hold about the value there**:

- **(A) it is the last use** — never read again, does not escape, and
- **(B) it is the unique owner of its memory** — no other live name or
  aggregate shares that memory.

"Consumed" just *means* "the point where a uniquely-owned value dies."
This is Perceus / functional-but-in-place (FBIP), done **statically**.

Two consequences that shape everything below:

- **Storing never copies.** `Box { content: s }` just points the box at
  `s`'s memory — sharing is free. The copy never happens at the *store*;
  it happens later, and only when someone reshapes a value that turns
  out to be still-live or shared.
- **The copy decision is a use-site property, not a function property.**
  The callee only contributes "does my result retain this argument?";
  whether that costs a clone depends on the caller's own liveness +
  aliasing.

## Why the shallow approaches fail

**Type reachability** ("return type can contain the arg type →
consumed") is unsound and imprecise:

- Two functions with identical signatures can behave oppositely.
  `f(a: Array[T]): Array[T]` might return a fresh array (retains
  nothing) or return `a` itself (retains everything). Types can't tell
  them apart.
- It ignores aliasing entirely — and aliasing is what makes last-use
  reuse *unsafe*.

**Per-function annotations** (`@consumes` / `@produces`) push the
soundness of the whole memory model onto humans annotating correctly.
Fragile, and unnecessary for user code.

## The three analyses feeding one decision

1. **Liveness (last use).** From the dataflow graph: for each value,
   where is it read for the last time / does it escape? Exact,
   mechanical.
2. **Uniqueness / aliasing.** Is this value the only owner of its
   memory, or has it been shared (bound to a second live name, or stored
   into a still-live aggregate)? This is the piece the type/annotation
   approaches miss.
3. **Ownership summaries** — per function, per parameter, one of:
   - **borrow** — the result shares nothing with the parameter
     (`Array.count(a): u32`). Free `a` independently right after.
   - **alias-out** — a piece of the parameter escapes into the result
     (`Array.get(a, i): T` returns an element living inside `a`). The
     result's lifetime pins `a`.
   - **absorb** — the result is a new version of the parameter, sharing
     its backbone (`Array.assoc(a, i, x): Array[T]`). `a` is retained.
   - **may-absorb** — arms disagree (see the branch example); the caller
     stays safe by treating it as absorbed.

   Summaries are **inferred from bodies, bottom-up over the call graph**,
   memoized per function, fixpointed across recursion (SCCs). The base
   cases are the persistent-structure **primitives (externs)**, whose
   summaries are known *by construction* because the compiler owns that
   runtime.

**The decision at each use site** combines the value's (A) last-use and
(B) uniqueness with the callee's summary for that slot:

| callee summary | value state at this use | action |
|---|---|---|
| borrow | any | no copy; free the value later if dead |
| alias-out | any | keep the value alive as long as the result |
| absorb | last use **and** unique | **reuse in place** (zero copy) |
| absorb | still live **or** shared | **clone** the edited path, keep original |

## The graph model

Lower each function body to a **per-function value graph**:

- **Node = value, not name.** A name is used exactly once, during
  lowering, to look up "which node currently produces the value this
  name refers to," then discarded. This erases every "variable
  shenanigan": rebinding, shadowing, alias-by-name.
- **Edges `consumer → producer`.** Under this direction, "how many
  things consume a value" = its **in-degree** — the load-bearing count
  for uniqueness.
- **Each node tagged `param` or `local`.** A param node is owned by the
  caller (never freed here); a local node is bump-allocated in this
  frame (freed at scope exit unless it escapes). This tag *is* the
  free/escape decision.

Every analysis becomes a structural query:

| fact | query |
|---|---|
| last use | latest consumer in topological order |
| uniqueness | consumer count (in-degree); a branch counts as one |
| escape | reverse-reachable from the return node |
| alias lifetime | follow the alias edge back to its source |

### The graph is a DAG by construction — you do not "ignore loops"

With node-per-value, later statements depend only on earlier ones —
nothing points backward. Loops appear only from:

- **A name-keyed graph (mistake).** `x = Array.new(); x = Array.assoc(x, 0, 5)`
  makes `x → x` if you keep one node per *name*. Node-per-value emits
  `node2 = assoc(node1)`; no loop, and `node1` still holds its real
  consumers. If you see intra-function loops, you're still keyed by
  name.
- **Recursion (real).** A self/mutual call is an **opaque leaf node** —
  you do not expand it into the callee's body, so no back-edge is drawn.
  The toposort runs on the acyclic remainder as-is. "Modified toposort
  that ignores loops" is really "recursive calls are opaque leaves."

Two things bend the toposort but are **not** loops:

- **Branches.** A value used in two match arms is one *dynamic* use
  (one arm runs). Model the branch as **one node** with arms as
  sub-DAGs, so uniqueness counts it once. Handle it in the node model,
  not the sort.
- **Effects.** `println("A"); …; println("B")` must keep order. Effect
  edges preserve program order for effectful nodes; pure nodes between
  them stay freely orderable.

## The IR realm — dissolve files, think in ids

After analysis we cross from the *frontend realm* (files, scopes,
`Identifier`s, `Location`s — all in service of developer diagnostics)
into the *IR realm*, where those are fog. The IR cares about a flat
universe of integer-id'd entities; names survive only as plain
**strings**, kept for one purpose — emitting readable C at the end.

Why ids: dense `seq[T]`-indexed-by-id storage instead of identity-hashed
tables (O(1), cache-friendly, deterministic iteration, and no more
`hash` / `==`-by-location machinery). The analyzer already started this
— `AnalyzedApp.moduleIndex` / `findModule` dissolved the file barrier
for modules, and `Source = skInput(position) | skLocal(statement)`
already int-indexes producers. This generalizes both.

### Entities

    Program     = { types: seq[LocalTypeIR] }          # index = TypeId
    LocalTypeIR = { id: TypeId, name: string,
                    data: <struct | union | literal | …>,
                    funcs: seq[FuncId] }
    FunctionIR  = { id: FuncId, name: string, owner: TypeId,
                    args: seq[Arg], body: seq[AnfStmt], loc: string }
    Arg         = { name: string, ty: TypeRef }
    TypeRef     = { def: TypeId, impls: seq[TypeRef] }  # an instantiation

Three rules baked in:

- **Definition-id vs. value-type.** The id space is for *definitions*
  (`Array`, `Status`, `u32`). A *value's type* is an *instantiation* —
  a `TypeRef` = def-id + impl `TypeRef`s (`Array[u32]`). Ownership
  summaries are per-definition; sizing / layout needs the
  instantiation.
- **FuncIds are globally unique; `owner: TypeId` expresses "within."**
  One flat function table — "within a type" is a field, not a nested id
  space. Overloads are distinct FuncIds sharing a string `name`, so the
  name is NOT a unique C symbol; codegen mangles the C symbol from the
  id / args.
- **Names are strings, but keep a `loc` string** per function / binding
  for IR-level diagnostics ("value at X may leak"), separate from the
  readability name.

### Value ids unify `Source`

Every value gets a value-id too — params and bindings alike. A variable
resolves to its producer's value-id; graph edges are `value-id →
value-id`. `Source`'s `skInput` / `skLocal` collapse into one id space.

### The interning pass (lowering entry)

One walk, demand-driven from `start`, that assigns ids and translates
every analyzed reference into an id. Lazy: only entities reachable from
`start` get an id — dead code is never lowered and the id space stays
tight.

    intern(app):
      program  = empty
      typeIds  : Table[AnalyzedDefModule, TypeId]     # analyzed identity → id
      funcIds  : Table[AnalyzedFunctionDef, FuncId]
      worklist = [ app.entry.function ]               # start

      while worklist not empty:
        fn = worklist.pop()
        if fn.funcDef in funcIds: continue
        fid = freshFuncId(); funcIds[fn.funcDef] = fid
        tid = internType(fn.owner-module)             # assigns/returns a TypeId
        args = [ Arg(a.name.string, internTypeRef(a.argType)) for a in fn.args ]
        body = expandToAnf(fn, typeIds, funcIds, worklist)  # ANF overlay, emits ids;
                                                            # pushes each callee onto worklist
        program.funcs[fid] = FunctionIR(fid, fn.name.string, tid, args, body, fn.loc.string)

      internType(module):
        if module in typeIds: return typeIds[module]
        tid = freshTypeId(); typeIds[module] = tid
        program.types[tid] = LocalTypeIR(tid, module.name.string,
                                         internData(module.data), funcs = [])
        return tid                                    # funcs filled as they intern

`internTypeRef(argType)` walks an `AnalyzedArgumentType`: module arm →
`TypeRef(internType(module), impls.map(internTypeRef))`; generic arm →
resolved through the call's impl map, or left as a generic slot. The two
id maps are the entire bridge from analyzed identity to the IR — after
interning, nothing downstream touches an `Identifier` or a file.

## Per-construct lowering rules

The lowering walk reads each statement, resolves names via an
`env: name → node`, emits nodes + edges, and throws the env away at the
end. The five expression kinds + setter:

- **variable (`aekVariable`)** — resolve in env to a param/local node.
  An alias (`b = a`) creates **no** node; both names map to the one
  node (so its in-degree counts every real consumer — the aliasing
  trap solves itself).
- **function call (`aekFunctionCall`)** — a call node; edges to each
  argument's producer. Each arg edge is labeled with the callee's
  summary for that slot (`borrow` / `alias-out` / `absorb`).
- **initializer (`aekInitializer`)** — a construct node that **retains
  (absorbs)** each stored field value. Storing is free (a shared
  pointer); the copy, if any, is decided later by the field value's own
  last-use/uniqueness.
- **getter (`aekGetter`)** — reads the receiver, but the result
  **aliases a piece** of it for aggregate fields (the receiver must
  outlive the result). Only scalar fields are copy-out reads. Same
  danger class as match destructuring.
- **setter (`askSetter`)** — `s.f = x` produces a new `s'`. It
  **absorbs the receiver `s`** (shares its other fields) **and stores
  `x`** — two consumed inputs — then **repoints the name `s` to the new
  node**. This rebind is exactly what the AST does not express; the
  graph builder does it regardless.
- **match (`aekMatchExpr`)** — see below.

The clean "the variable is consumed" statements hold only when operands
are **bare variables**. The analyzed body is a nested tree, so Step 0's
post-analysis expander lifts nested operands into synthetic value-id
bindings first (`Box { content: Array.count(s) }` becomes `t =
Array.count(s); Box { content: t }`) — after which every operand is a
value-id and lowering is uniform.

## Match as an independent sub-function

Treat a match like a call node with closed-over inputs:

- **One node in the outer graph.** Its inputs are the subject plus every
  outer-scope variable the arms read; each such input is consumed
  **once** at the outer level — which *is* the "only one arm runs"
  semantics, for free.
- **Each arm is its own sub-graph** (its own env), so arm-local names
  stay contained and the same machinery recurses with no special cases.

Memory follows the **C-union** model, with the "max" principle applied
to three things:

- **Max bytes** — arm *internals* (temporaries) overlap in one region
  sized to the largest arm; popped at branch exit. (The *result* is a
  single uniform type — the analyzer already enforces uniform arm return
  type — so the result is one size, not a max.)
- **Max lifetime** — the branch has one output lifetime; all arms feed
  the same downstream consumer.
- **Max consumption** — a closed-over input's summary is the **join over
  arms** (most-consuming wins):

  ```
  match flag:
    case 0: Array.assoc(a, 0, 5)   # arm 0 ABSORBS a
    case _: Array.count(a)         # arm 1 only READS a
  ```
  The branch summary for `a` is "may-absorb," so the caller clones
  before the match if `a` is needed after — even though the read arm
  wouldn't have required it (the path isn't known statically).

**Alias-out caveat.** An arm whose result aliases a piece of the subject
(`case Ok { value: v }: v`) pulls the subject *out* of the poppable
arm-scratch and into the branch's output lifetime. Escape analysis
(following alias edges to the subject) sorts each value into
"poppable scratch" vs "survives with the result." The union-of-max-bytes
applies only to internals that don't escape.

A branch node is **effectful if any arm is** — it then sits as an
ordering barrier at its program position.

## The two coupled layers

Consumption-the-summary is a *function* property; copy-or-move is a
*use-site* property. They cannot collapse into one pass:

1. **Forward, demand-driven from `start`.** Discover the reachable call
   graph; build each function's per-param ownership summary. Memoized,
   fixpointed over recursion (SCCs), externs as base cases.
2. **Backward, within each function.** Last-use + uniqueness + escape on
   the value graph.

The link: summaries from layer 1 **label the argument edges** of layer
2's graph; the degree/reachability queries then make the actual
clone/move/free calls. Summaries flow down; liveness flows back; the
edge label is where they meet.

## The pipeline

- **Step 0 — intern (demand-driven from `start`).** One walk that
  assigns `TypeId` / `FuncId`, dissolves the file barrier, and
  translates every analyzed reference into an id (see The IR realm).
  Lazy — only entities reachable from `start` are lowered. Output: the
  id'd IR `Program`, its function bodies still to be expanded.
- **Step 1 — ANF-expand + lower each body to its value graph.** The
  post-analysis expander lifts nested operands into synthetic value-id
  bindings (every operand becomes a value-id/name), then the forward
  walk builds the graph — nodes are value-ids, edges `consumer →
  producer`, per the lowering rules above. The expander references
  analyzed nodes read-only; the hardened analyzer stays frozen.
- **Step 2 — ownership summaries (layer 1),** fixpointed over the call
  graph; externs known by construction.
- **Step 3 — backward graph queries (layer 2):** escape (reverse-reach
  from return, following alias edges), uniqueness (in-degree, branch as
  one), last-use (latest consumer in topo order, effect-ordered).
- **Step 4 — emit decisions.** At each consume site combine
  summary + last-use + uniqueness → reuse-in-place / clone / borrow /
  keep-alive. Insert frees: at each scope/branch exit, pop the bump
  watermark for every *local* node not in the escape set; match
  internals share a max-sized union region.
- **Step 5 — output for codegen.** A graph with per-node placement
  (caller-frame vs local-bump), per-consume copy/move flags, and
  per-scope watermark points — the input to C codegen + the allocator.

## Build order (incremental, correctness-first)

Start sound and dumb, then sharpen. Every step is shippable —
over-copying and late-freeing are always *correct*; later steps only
remove copies and free earlier.

1. **Lowering only** — build the value graph for straight-line
   functions; snapshot-test the shape. No decisions.
2. **Escape + naive free** — reverse-reach from return; free all locals
   at *function* exit (one watermark). Always correct.
3. **Uniqueness + last-use** — the reuse-in-place / clone decision for
   straight-line code.
4. **Match** — branch nodes, arm sub-graphs, union scratch, nested
   watermarks.
5. **Interprocedural summaries** — the call-graph fixpoint; replace the
   conservative "assume absorb" default with inferred
   borrow/alias-out/absorb.
6. **Recursion** — opaque nodes + SCC summaries. (The skeleton has **no**
   memoization/cycle guard yet — it will infinite-loop on recursive
   functions once the real arms land, so this step gates them.)

## Memory model

`examples/allocator.c`: a bump allocator with `stack_alloc` (advance the
cursor) and save-watermark / `stack_release` (pop the cursor back).
Lifetime analysis drives it — escape decides caller-frame vs local-bump
placement; each scope (function body, each match arm) saves a watermark
on entry and pops it on exit, freeing everything local that did not
escape. Match arms are the nested watermarks (Frame 1 / Frame 2 in the
prototype).

## What the pass consumes (grounded in the real `Analyzed*` types)

- Body: `AnalyzedApp → files → AnalyzedFile → modules → AnalyzedModule →
  functions → AnalyzedFunction(afkUser).user.statements:
  seq[AnalyzedStatement]`.
- **3 statement kinds**: `askAssignment` (the ONLY binding-introducing
  form — `statement.arg` is `some` only here), `askSetter` (`x.f =
  expr`, introduces no binding), `askExpr` (bare expression).
- **5 expression kinds**: `aekVariable`, `aekGetter`, `aekFunctionCall`
  (positional args + inferred `AnalyzedImplMap` + materialized
  `returns`), `aekInitializer` (struct/union/literal, keyword args),
  `aekMatchExpr` (subject + case arms, each its own nested statement
  scope + pattern bindings).
- **Every expression self-types** via `argType*` → a concrete
  `AnalyzedArgumentType`, generic instantiation intrinsic on `.impls`.
  The pass never re-resolves a type.
- The analyzer scope is name-keyed (`AnalyzedFunctionContext =
  Table[Identifier, AnalyzedBinding]`), value-copied per arm,
  **reassignment overwrites** — no SSA, no ownership fields. The value
  graph supplies the identity the name model lacks.

Do **not** extend the string-typed, `concept`-based prototypes in
`plans/phase_0*.nim` / `dag_ir_core.nim`. Their escape/refcount/DCE
*algorithms* are right, but a real build consumes the `Analyzed*` types
directly (Nim `concept`s are flagged unreliable in this codebase).

## The current skeleton (`src/lifetime.nim`)

Already landed, off the CLI path:

- `Source = skInput(position) | skLocal(statement)` — the param-vs-local
  resolution of a variable.
- `analyzeLifetime` overloads walk `app → start → statements →
  expression → fncall → callee`, seeding scope from the function's args.
- Cross-barrier plumbing: `AnalyzedApp.findModule`,
  `AnalyzedModule.findFunction`, `AnalyzedFunctionCall.localType`.
- Most arms return `todo:` errors. The top-level app arm currently
  duplicates the `afkUser` function arm — it can delegate once the walk
  is real.

## Open decisions

- **How externs declare their summaries** — inferred from
  compiler-generated persistent-structure code vs. a small annotation
  vocabulary on `base.aslr` primitives.
- **Interprocedural uniqueness** — does a function *assume* it uniquely
  owns a parameter? The genuinely hard corner. Defer: assume params may
  be shared → clone conservatively, optimize later.
- **How much the IR copies vs. references** — the id'd entities carry
  string names + `TypeRef`s, but data-shape (struct fields / union
  variants) and generic-impl detail can either be copied into the IR or
  read back from the analyzed node by identity. Start by referencing;
  copy only what a pass actually needs.

Decided (folded in above): post-analysis expander → thin ANF overlay
(not the parser expander); an int-id IR realm with dissolved files;
globally-unique `FuncId`s with `owner: TypeId`; lazy id assignment
demand-driven from `start`; port the DAG escape/refcount/DCE algorithms
onto the id'd IR rather than extending the string/`concept` prototype.
