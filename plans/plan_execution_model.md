# ASLang execution model + bounded-compilation design

Captures the design reasoning behind the programming model, the memory model,
and how worst-case guarantees (WCET/WCMC) are achieved. This is the conceptual
spine the compiler serves; read it alongside `plan_monomorphizer.md`.

## Programming model: everything is an actor

An actor is an event loop: **initialize → handle events → terminate.**

```
module Actor:
  struct:            # (or union — see FSM note) the actor's own state
    ...state fields
    context          # the concrete context it was initialized in (may be generic)

  func init(...args, context): Actor
  func handle(state: Actor, event: ActorEvent): ActorResponse   # ActorResponse { state: Actor, result }
```

- `handle` is a pure transition `(state, event) → (state, result)`; an actor's life
  is a **fold over its event stream**. Trivially analyzable: WCET(actor) =
  per-`handle` bound × event-count bound; WCMC = the state's footprint.
- Multiple events → `event` is a **union**; one event → a struct.
- A **union state is an explicit finite state machine** (each variant a state,
  `handle` dispatching on (state-variant, event)) — ideal for verification.
- The **event loop is the runtime agent** = the SCC/loop the monomorphized call
  graph exposes. Compile-time "generic = abstract actor" and runtime
  "loop = agent" are the *same* abstraction at two scales.

## Generics = abstract actors over their own state

A generic is an abstract actor whose state is its own type and that can only
mutate its own state. Therefore:

- **Self-only contracts are definitional, not a restriction to relax.** A
  constraint's functions operate on the self type because the actor mutates only
  its own state; the `context` is a field it owns.
- **Cross-generic contracts are a category error** — one actor's contract naming
  another actor's state. Do NOT add them (decided; see plan_monomorphizer.md).
  What tempts you toward them is one of:
  - the other type is **part of your context** → axis-1, just a (possibly
    generic) type parameter you carry; or
  - genuine interaction with another actor → **communication**, i.e. events on
    the channel/agent layer, never a contract reference.
- Rich/generic **contexts** (multiple abstract params, associated types, nesting)
  are fully supported and are where expressiveness lives (axis 1). The forbidden
  thing is only axis-2 (naming another actor's state).

## Memory model

- **No shared mutable state — it is inexpressible.** Persistence means a
  "mutation" yields a new value, so there is no mutable reference to alias. The
  program state is strictly a **tree of uniquely-owned state** → **no alias
  analysis is ever needed.** Lifetime analysis reduces to the easy local kind:
  liveness / last-use.
- **Path copying** is the persistence strategy for Struct, Array, and Map: an
  update copies the path and **shares the untouched immutable subtrees** between
  versions. Update cost = O(path depth) — bounded iff depth/capacity is bounded.
- **Version retention is expressible** (e.g. a readable undo history), so shared
  immutable nodes can have multiple live referents. Management:
  - **Deterministic reference counting (Perceus/FBIP)** — not tracing GC (GC's
    nondeterministic pauses would sink WCET). RC is **pay-for-what-you-use**:
    in the single-version fast path the count is 1 → **reuse in place**, no copy,
    statically elidable where uniqueness is proven; only genuinely-shared
    (retained) nodes carry real RC. inc/dec are O(1), cascading frees O(depth) —
    bounded, no pauses.
  - Alternative kept in back pocket: **copy-on-retain** (deep-copy on snapshot →
    independent versions → no RC, but O(size) retain). Usually the wrong trade
    vs RC; the fully-static option if RC is ever to be banned.
- **Every Array/List/Map must declare its capacity up front.** So each
  collection's footprint and fan-out are bounded *by construction*, and
  unbounded retention is **unwritable** (a history is a capacity ring). WCMC for
  retention is therefore always defined: peak live versions ≤ the container's
  capacity.

## Recursive types and bounds

- Recursive data types ARE allowed. **Capacity bounds branching, not depth** —
  a `TreeNode { children: List[TreeNode, 4] }` has bounded fan-out but
  data-dependent depth, so total size needs a depth bound too. (The built-in
  Array/Map are internally recursive tries but depth = O(log capacity), so they
  are self-bounding.)
- **Bound policy (graduated strictness):**
  - **Statically-bounded recursion** (recursion that provably shrinks a
    capacity-bounded measure) → **bound inferred** from the Array/List/Map
    capacities. Inference is a **ranking-function check against the capacity**,
    and it is **per-SCC** (mutual recursion → a combined measure for the whole
    SCC = the loop/agent). Bound inference and agent extraction are the same
    call-graph SCC decomposition.
  - **Data-dependent recursion** → a **warning** by default (permissive), which
    **turns into an error under WCET/WCMC** (must infer or annotate a bound).
- **Keep two "bounds" distinct — different phases:**
  - **Occurs-check** (compile-time, monomorphization): recursion whose *types
    grow* (`T → List[T] → …`) blows up the compiler → **always a hard error, in
    every mode.** About the compiler terminating.
  - **Runtime recursion bound** (WCET/WCMC): how many times code *runs* →
    graduated warning/error. A function can pass the occurs-check (finite
    instances, compiles) yet have no runtime bound (data-dependent depth).

## Two tiers: permissive TOOL, bounded ARTIFACT

- **WCET/WCMC mode is viral over the reachable set**: certifying an entry point
  requires its entire transitive closure (libraries included) to be bounded.
  "Bounded" is a property of a reachable subgraph, so code splits into a
  bounded/certified tier and a permissive tier.
- This maps cleanly onto **the tool vs the artifact**: the **self-hosted ASL
  compiler** lives in the **permissive** tier (data-dependent recursion over the
  AST is fine, warnings OK), while the **HFT / defense / hardware programs it
  emits** live in the **bounded** tier (WCET/WCMC enforced). This is what makes
  self-hosting a bounds-focused language consistent — the tool need not be
  bounded, only the artifact.

## How the guarantees compute (downstream)

- Lower each actor/function to SSA/CFG (the purely-functional form that maps to
  C, LLVM, and HDL alike).
- **WCET** = critical path through an SCC's node DAG per firing × the SCC's
  (inferred/annotated) bound.
- **WCMC** = structure footprints (capacity-bounded) + peak simultaneously-live
  persistent versions (capacity-bounded) ; path-copy/RC keep per-update memory
  bounded.
- A `bound` annotation declares **both** space and time together (so the two
  stay parametrized over the same inputs and never drift).
