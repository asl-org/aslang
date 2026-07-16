# Plan — Per-function DAG IR (reference-counted, escape-aware)

**Status**: exploratory. Successor to the current AnalyzedAST. Landing
gated on Tasks 20 (extract macro layer) and 21 (try operator) —
neither strictly required, but sequencing them first keeps the parser
and expander stable while the DAG lowering is prototyped.

## Goal

Post-analyzer, lower each function body into a per-function graph
(DAG) where nodes are computations and edges are data-flow
dependencies. From that graph, statically derive:

1. **Reference counts** — how many times each value is consumed. Enables
   Perceus-style reuse-in-place optimization for persistent data
   structures (linear values mutate in place; shared values structurally
   share).
2. **Escape sets** — which values survive the function's watermark
   release. Enables bump-allocator-based memory management with
   deterministic release.
3. **Dead-code elimination** — values with no consumers get removed.
4. **Frama-C spec generation** — every function's contract (types,
   purity, memory footprint) can be emitted as ACSL alongside the
   generated C, allowing formal verification of the codegen output.

## Input / Output

**Input**: analyzed function body in ANF form. A sequence of statements,
each of shape `x = expr`. Each `expr` is exactly one of:

- `literal(value)`
- `call(func, [arg_1, arg_2, ...])` — args are variable names
- `branch(subject, [arm_1, arm_2, ...])` — subject is a variable name,
  each arm is a sub-body (same shape recursively)

**Output**: a per-function graph `G` where each node represents one
binding, edges point from producers to consumers, and each node carries
its refcount, escape flag, and provenance for downstream codegen.

## The algorithm — 6 core steps

### Step 1. Build the graph

Walk statements top to bottom. Keep a variable-to-node map `V`.

For each statement `x = expr`:
1. Create a new node `N` for this expression. Store its kind
   (literal / call / branch) and the associated data (literal value,
   function reference, branch subject).
2. For every variable reference inside `expr`:
   - Look up its producing node: `M = V[y]`.
   - Add an edge `M → N` to the graph.
3. Record `V[x] = N`.

Each edge is directional: **producer → consumer**. So the out-degree
of a node equals how many later expressions use its result.

### Step 2. Identify the return node

The last statement of the function body is the return. Its node is the
return node `R`.

### Step 3. Compute the escape set

Walk backwards from `R`, following edges in reverse (from consumer back
to producer). Every node you touch is in the escape set — its value's
memory must survive the function's watermark release, because `R`
(or something transitively feeding `R`) references it.

### Step 4. Dead-code elimination

Repeat until stable:
- Find any node with `out-degree == 0` that is NOT in the escape set.
- Remove it. This may reduce other nodes' out-degrees.

After this pass, every remaining non-escape node is used by SOMETHING;
every escape-set node is preserved regardless.

### Step 5. Compute reference counts

For each remaining node `N`: `refcount(N) = out-degree(N)`.

Interpretation:
- `refcount == 1`: **linear**. The one consumer can safely reuse `N`'s
  memory in-place (Perceus-style reuse optimization).
- `refcount > 1`: **shared**. Multiple consumers reference this value;
  keep separate allocations or share via structural sharing.
- Node is in escape set: **allocate in caller's frame** regardless of
  refcount.

### Step 6. Codegen in topological order

Sort the graph topologically (producers before consumers). For each
node in order:
- **literal**: emit constant, allocate at bump position (or caller's
  region if in escape set).
- **call**: emit function invocation. If linear, allow in-place update
  on the input. If shared, allocate fresh.
- **branch**: emit conditional dispatch (details below).

At function exit: watermark release. Wipes everything not in the
escape set.

---

## Concrete example

Source (ANF-normalized):

```
func compute(): u32
  a = literal(1)
  b = literal(2)
  c = call(add, [a, b])
  d = call(mul, [c, c])
  d
```

### Step 1 — build graph

```
V:  a → A,  b → B,  c → C,  d → D

G:
      A ────┐
            ├──> C ═══> D
      B ────┘
```

`C` has two edges to `D` because `mul(c, c)` uses `c` twice. Drawn as
`═══>` (double-edge).

### Step 2 — return node

`D` is the last statement's node. `R = D`.

### Step 3 — escape set

Walk back from `D`:
- `D` → escape.
- `D`'s inputs: `C` → escape.
- `C`'s inputs: `A`, `B` → both escape.

Everything is in the escape set. (Not surprising — every value
contributes to the return.)

### Step 4 — DCE

No non-escape nodes. Nothing removed.

### Step 5 — refcounts

- `A`: out-degree 1 → linear.
- `B`: out-degree 1 → linear.
- `C`: out-degree 2 → shared.
- `D`: out-degree 0, but in escape set → allocated in caller's frame.

### Step 6 — codegen

Topological order: A, B, C, D.

- Allocate for `A` at bump position P0. Store literal 1.
- Allocate for `B` at bump position P1. Store literal 2.
- Call `add(A, B)` producing `C`. Since `A` is linear (refcount 1),
  can reuse P0 for `C`'s output. Bump grows to P2.
- Call `mul(C, C)` producing `D`. `D` is in escape set, so allocate in
  caller's frame at position P_caller. `C` is used twice in this call —
  pass its address twice; no need to copy.
- Return `D`'s address in caller's frame.
- Watermark release: bump rolls back to P0. `A`, `B`, `C`'s memory is
  freed. `D` (in caller's frame) survives.

---

## Handling branch nodes

Treat each branch as a **single node in the outer graph**, with a
recursive sub-graph for each arm.

For a branch node `br`:
- **Inputs**: subject variable + any variables from outer scope that
  arms reference (closed-over variables).
- **Arms**: each arm is itself an ANF-normalized body → run the same
  6-step algorithm recursively to build its sub-graph.
- **Output**: whichever value the taken arm produces.

**Key insight for refcounts**: at runtime, exactly ONE arm executes.
So a variable referenced from two arms is still ONE use at the outer
level — the branch node consumes it once, then internally dispatches
to whichever arm needs it.

The sub-graphs each have their own escape sets (the arm's own return
value, which flows out to the branch node's output). Recursively DCE
and refcount them.

---

## Step 7 (extension) — Frama-C spec generation

Once the DAG is built and analyzed, every function has known-at-compile-
time properties that map directly onto ACSL annotations:

- **Argument types** → `@requires` type invariants on parameters.
- **Return type** → `@ensures` postcondition on `\result`.
- **Purity** (no observable side effects) → `@pure` annotation.
- **Memory footprint** — for each node in the escape set: `@assigns`
  clause naming the memory region it writes into (caller's frame vs
  local bump).
- **Bump-allocator invariants** — bump pointer never exceeds capacity;
  watermark stack never underflows. These become module-level `@axiom`s
  and `@invariant`s on the allocator struct.
- **Escape set** → each escaping value's memory region is named in the
  function's `@assigns` clause; non-escaping values are noted as
  belonging to the scratch region that gets wiped on return.
- **Dead-code paths** → not emitted at all (already eliminated in
  step 4), so no ACSL noise from them.

The spec-generation step runs AFTER the DAG has been analyzed but
BEFORE C codegen — the DAG's structure directly informs the ACSL
attributes emitted alongside the C. Both outputs (C code + ACSL specs)
travel together as one artifact per function.

**Codegen produces**:
```c
/*@ requires \valid(a) && \valid(b);
    ensures \result == a + b;
    assigns \nothing;
    pure;
*/
uint32_t compute_add(uint32_t a, uint32_t b) {
    return a + b;
}
```

Frama-C's proof kernel can then verify the ACSL matches the C. Two
value adds:

1. **Formal verification** — Frama-C proves the generated C respects
   its declared contract. Catches codegen bugs.
2. **Documentation** — the ACSL doubles as machine-checked
   documentation of what each function guarantees.

The user writes no ACSL. The compiler generates it from information the
DAG already has.

---

## What's deferred (not in step 1-6)

- **Node origin** (`user` vs `uplifted` vs `expanded` vs `injected`).
  Add later for warning-quality attribution.
- **Purity discrimination** on function calls. Currently treated
  uniformly; extern functions may need `@pure` decorator to
  participate in DCE. See Step 7 — Frama-C spec generation naturally
  wants this too.
- **Warning collection** — when DCE removes a user-written node, emit
  a warning through a collector that reports at end-of-pass.
- **Cross-function optimization** — inlining, whole-program CSE. Per-
  function scope for now; whole-program passes are a later phase.
- **Cyclic-DAG handling** — recursion within a function body doesn't
  produce cycles in the value graph (each invocation is a fresh
  set of nodes). Recursive function calls are opaque edges pointing
  at the function's declaration, not into its body. So DAG stays
  acyclic per invocation.

---

## Open questions

### Q1 — Node representation shape

**Evolve the analyzed AST** — annotate each analyzed statement with a
refcount and escape flag. Cheap to build, preserves source-level shapes
for error messages.

**Fresh IR** — dedicated data structures for graph nodes + edges.
Cleaner analysis, no AST quirks to work around. Better foundation for
future optimizations (CSE, constant folding, code motion).

Recommended: **fresh IR** with mandatory `loc` on every node and a
translation layer to source for diagnostics. Location threading is
the extra cost; better isolation of the IR from AST evolution is the
benefit.

### Q2 — When is the DAG lowering pass wired in?

Between analyzer and (future) codegen. Doesn't touch parser / resolver
/ analyzer / expander. Standalone pass that consumes analyzed AST and
produces DAG per function.

### Q3 — Where does the DAG lowering pass live?

New peer of `resolver` / `expander` under `analyzer`:

```
src/analyzer/
  resolver.nim
  resolver/
  ir.nim               (NEW barrel)
  ir/
    graph.nim          (Node, Edge, FunctionGraph types)
    build.nim          (analyzed AST → DAG)
    escape.nim         (escape set computation)
    dce.nim            (dead code elimination)
    refcount.nim       (refcount analysis)
```

Room for `codegen/` and `specs/` (Frama-C) as siblings later.

### Q4 — Frama-C spec surface

Which ACSL features to emit initially:

- **Minimal**: `@requires` on args + `@ensures` on result + `@pure` when
  applicable. Covers type-level contracts.
- **Broad**: also `@assigns` clauses, memory-region invariants,
  bump-allocator axioms.

Recommended: **minimal first**, expand as codegen matures. Complex
`@assigns` clauses depend on having a stable ABI for the bump
allocator's memory model.

---

## Sequencing

1. Ship Task 20 (extract macro/expander layer) — clean parser/expander
   separation.
2. Ship Task 21 (try operator) — validates that the expander is
   extensible.
3. Prototype IR lowering as a new phase after analyzer. Just the 6
   core steps.
4. Add refcount analysis + DCE (steps 4-5).
5. Add escape set computation (step 3).
6. Wire codegen (step 6) — bump allocator with reuse-in-place for
   `refcount == 1`.
7. Add Step 7 — Frama-C spec generation alongside codegen.

Steps 3-6 can ship independently, each adding capability without
breaking the prior stage. Frama-C spec generation slots in whenever
codegen is stable enough to attach contracts to.
