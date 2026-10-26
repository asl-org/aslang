# Monomorphizer + downstream IR — design & decisions

Status: in progress on `main`, built incrementally (one small, compiling bite at
a time) in `src/monomorphize.nim`, wired into `compile` so `./asl build` walks
it and stops at the first `todo` arm. This doc persists the design reasoning so
we don't lose it when we revisit the earlier layers.

## North star

- Pipeline today: parse → resolve → defanalyze → analyze → **monomorphize** →
  (future) lifetime → codegen. Target now = **C on CPUs**; later = LLVM and
  **hardware (HDL)**.
- **Self-hosting is the long-term goal**: once ASL can express real programs,
  rewrite the compiler in ASL itself. Everything below should stay simple and
  consistent enough that that rewrite is realistic.
- The compiler's value proposition is **static worst-case guarantees**:
  worst-case execution time (WCET) and worst-case memory consumption (WCMC),
  via `bound` annotations (one annotation declares *both* space and time, so the
  two bounds stay parametrized over the same inputs and never drift).

## The two id spaces (the core distinction)

- `FunctionId` — names one fully-typed **function copy** (one monomorphized
  instance). Program-global, minted by the `Monomorphizer`. A generic function
  used at several concrete types becomes several copies, each its own id.
- `ValueId` — names one **value inside a single copy's body**. Local to that
  copy, minted by its `FunctionScope`, numbered from 0.
- They are `distinct int` so the compiler forbids crossing them. At a call node
  both appear: `callee: FunctionId`, `args: seq[ValueId]`, result `ValueId`.
- A value is a particular *invocation*, not a function — one function, N calls,
  N values — which is why `FunctionId` can't double as `ValueId`. And a call is
  an opaque node that *names* a `FunctionId` without unfolding it; that opacity
  is exactly what keeps each body finite under recursion.

## Approach 1, and why approach 2 is impossible

- **Approach 1 (chosen):** build each instance once, keyed by `FunctionRef =
  (module, function, concrete impls)` — call-site-*independent*. Params become
  their own values (slots); the caller wires actual argument values at the call
  node. One copy, reused across all callers.
- **Approach 2 (rejected):** put the call-site arg values into the key / inline
  per call. It **cannot represent recursion** — a recursive call's key never
  repeats, so the memo knot never closes and it unrolls forever; it also
  explodes code size. "**A loop is a key that repeats**": approach 1's key
  repeats on a recursive call, so `visiting` closes the cycle and the call graph
  is finite — which is also the cycle the eventual loop/agent extraction finds.

## Memoization / recursion knot

`Monomorphizer` holds `visiting` + `visited: Table[FunctionRef, FunctionId]` and
the id counter. First encounter of a user function: mint the id, put it in
`visiting`, build the body, move to `visited`. Re-entering a `FunctionRef` still
in `visiting` is a recursive call — return its in-progress id so the cycle
closes. `TODO(occurs-check)`: polymorphic recursion whose type args grow
(T → List[T] → …) mints a fresh key each level and `visiting` grows without
bound; guard that.

Callee key must be **concretized through the enclosing instance's impls**
(`fncall.impls.calleeImpls(impls)`) — otherwise a call made inside a generic
instance keys on a type parameter still in scope. Same for a try's result type
(`fncall.returns.concrete(impls)`).

## The IR node model

A `FunctionScope` is the work area for one copy: a value counter, an `argMap`
(variable name → the value it currently stands for), and `nodes: seq[Node]` (the
body collected as it is walked).

- `Node { id: ValueId, kind, payload }`, kinds so far:
  - `nkCall` → `FunctionCallNode { callee, args }`
  - `nkMatch` → `MatchNode { subject, branches: seq[BranchNode] }`, where
    `BranchNode { pattern, resultId }`. The match node's own id is the merged
    result (a phi over the branches).
  - `nkTry` → `TryNode { call, returns }` — a call plus the finalized unwrapped
    Ok type; on Err it returns from the enclosing function.
- A **variable** is not a node — it resolves through `argMap` to an existing
  `ValueId`.
- Every recursive step is named `monomorphize` (overloaded) — no oddly-named
  helpers; that naming consistency is a deliberate rule.

Planned: once **params become `nkParam` nodes**, every value is a node stored at
its own index, so `ValueId == index into nodes`, the `counter` is replaced by
`nodes.len`, and `nodes[id]` is an O(1) "what produced this value" — which is
what CSE / lifetime / forwarding want.

## `try` — interim vs eventual

- **Interim (now, C target):** `nkTry`. C has `return`, which *is* the
  short-circuit-from-any-depth that `try` needs, so codegen emits
  `Status r = f(args); if (is_err(r)) return rebuild(r.err); v = ok_value(r);`.
  Lossless and needs no restructuring.
- **Eventual (consistent form):** expand `try` into a `match` in the macro layer.
  The blocker was that an error inside desugared code points at code the
  developer never wrote. **Solution:** tag the generated `match` with a
  `generated` kind; any error originating in a generated block is **remapped**
  to developer-facing terms at the error boundary (provenance tag + remap, like
  macro source-maps). This is the unblock for doing the expansion in the
  expansion layer.
- **Hardware form:** no `return`, so the pure-SSA shape is needed — `try` becomes
  a branch whose Err arm *diverges* via an explicit return node, continuation
  stays put (Rust's `?` desugaring). The pain of "move the continuation into the
  Ok arm" only exists in a no-`return` expression model; give the IR an explicit
  return/divergence node and it disappears.

## Value model (versioning), CSE, lifetime

- Every value carries a version id. Structs path-copy on update (new ids along
  the path, shared off-path); unions are construct-only. **Array and Map are the
  only linear types** — persistent, but linearity means a unique reference's old
  version is dead at update, so the backend can reuse storage in place.
- **The IR is always persistent.** In-place is an **as-if optimization chosen
  after lifetime analysis**, observationally invisible — so copy-everywhere C is
  correct from day one and any WCMC computed on the persistent IR stays a sound
  upper bound; in-place only tightens it.
- **Content-addressed ids = free CSE**: give immutable values (literals, structs,
  unions, pure calls) ids derived from their content, so equal computations are
  the same node automatically. Linear Array/Map stay version-counted (identity,
  not content). Introduce content-addressing as its **own pass after the
  monomorphizer** (keep the builder minting fresh ids; it preserves provenance),
  and re-run it after any inlining for cross-boundary CSE.
- Cross-function CSE is inlining-gated and trades against boundary preservation;
  on hardware, recompute is often cheaper than a shared long wire, so it's a
  per-region knob, not a mandate. Field-expanding struct parameters eliminates
  flat non-recursive structs entirely; recursive/union/array-bearing/escaping
  structs stay boxed.

## Loops as agents (later)

After monomorphization the **SCCs of the concrete call graph are the loops =
agents**; the condensation is the process network, cross-SCC edges are channels.
Sync agents only for now (async deferred). The share-vs-replicate choice (one
shared actor + mailbox vs. replicated point-to-point) is the area/throughput
*and* determinism knob. Lineage to study: Lustre/SCADE, SDF (static dataflow),
KPN/CSP, sized/indexed types.

## Downstream IR shape

Make the monomorphized IR **SSA/CFG** (block arguments or phi). SSA is the
"purely functional" form *with* explicit control flow, and is the common
ancestor of C (result var + single return), LLVM (phi directly), and hardware
(phi → mux). WCET = critical path through a copy's node DAG × a loop bound;
WCMC = peak live set + bounded channel buffers — both standard on SSA/CFG.
Undecidable in general, so the language must *restrict* so bounds exist (checked
`bound` annotations / structural recursion / capacity-typed structures) — a
front-end commitment, not a backend afterthought.

## Bites done / remaining

Done: FunctionId/ValueId split; FunctionRef memo + recursion knot; callee-impls
concretization; FunctionScope; nkCall record+return; values flow
(statement→ValueId, variable binds); nkMatch record; nkTry record.

Remaining (next): `initializer` (literals, struct/union construction);
`aekVariable` (argMap lookup); struct getter; the generic-target call path;
payload bindings (`nkPayload`) + per-branch region tracking; capture the
function's own result; params → `nkParam` (then `counter` → `nodes.len`);
`typ` on all nodes; then content-addressing, lifetime, codegen.

> **Refactor note:** once the monomorphizer reaches a working state we intend to
> refactor it and revisit the earlier layers for consistency. Keep changes
> reversible and the bites small until then.
