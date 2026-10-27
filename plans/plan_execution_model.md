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
- **Persistence is realized without cross-version sharing** — chosen over
  reference counting. An update walks the path to the changed position and then:
  - if the value's **last use** is this update (uniquely owned) → **mutate in
    place** (no copy);
  - if a **version is retained** (still live afterward) → **full deep copy**,
    producing two independent trees (classic path-copying's shared-subtree trick
    is deliberately NOT used — see why below).
  This is essentially **Rust ownership minus `Rc`**: own → mutate-in-place-or-
  clone → recursive drop. Tracing GC is rejected (nondeterministic pauses sink
  WCET). The only cost paid is a bounded deep copy **on actual retention**; the
  common actor-loop state threading is all in place.
- **Why no sharing:** structural sharing is exactly what makes freeing hard — a
  dying version can't recurse-and-free, because subtrees may belong to another
  live version (needs per-node refcount + cascade). With no sharing, each version
  owns its whole tree, so **freeing is a plain bounded recursive drop, no refcount,
  no sharing check.** The price is the deep copy on retain (bounded by capacity).
- **Uniqueness = last-use, computed by exact backward liveness** over each
  instance's value graph + CFG — **exact because there is no aliasing** (a value's
  uses are exactly its graph consumers). Compositional via a **move convention at
  call boundaries** (passing a collection moves it; the callee owns it). Where
  control flow leaves last-use unprovable → **copy** (sound, static, no refcount).
- **Element lifetimes are the same ownership tree one level down.** `Array[T]`
  owns its `T`s like `Vec<T>`:
  - `set(arr, i, x)` → displaced old element **dropped** (recursively if
    aggregate); `x` **moved in** (or copied if still live elsewhere).
  - `get(arr, i)` → **borrow** for a transient read (no copy); **move** out if the
    array is dead afterward, else **copy** out, when the element escapes.
  - freeing the array → generated **recursive drop** of all owned elements
    (trivial — nothing shared). Cost note: aggregate elements make copy-on-retain
    a *deep* recursive copy, bounded by the product of capacities.
- **Codegen seam for a future refcount backend (CPU-target optimization).** Keep
  copy-vs-refcount out of the IR and the lifetime analysis. The lifetime pass
  emits **abstract ownership directives** — `dup(v)` (retain / survive a
  consume), `drop(v)` (end of life), and a per-mutation `unique?` flag — never
  concrete "copy"/"free". Codegen *realizes* them per target:
  - **deep-copy (now; hardware):** `dup`=recursive copy, `drop`=recursive free,
    mutate = static in-place/copy per `unique?`; no header, no runtime checks.
  - **refcount (later; CPU):** `dup`=`incref`, `drop`=`decref` (+cascade free at
    0), mutate = runtime `rc==1 ? in-place : copy`, plus a count **header** on
    heap aggregates (non-atomic/`Rc` by default — actors share only by moves, so
    atomic/`Arc` is needed only for genuinely cross-actor-shared values).
    Optional: cell-reuse / FBIP fusion for allocation-free updates. The win is
    recovering in-place reuse that the static deep-copy strategy conservatively
    copied, at the cost of one runtime branch.
  **Adding refcount is codegen-local:** a layout header + `incref`/`decref` + the
  three realizations + the per-mutation runtime check. The IR, monomorphizer,
  type layouts, and the `dup`/`drop` *placement* do NOT change. The one thing to
  get right up front is that the lifetime pass emits `dup`/`drop`/`unique?`
  abstractly, routed through a small "memory strategy" seam in codegen.
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

## Loops → steppers (SCC reification)

Loops (= recursion = cycles in the call graph) are the one complexity
concentrator; the plan is to **reify each loop as a cohesive, bounded unit** so
every downstream layer treats loops as composable boxes instead of re-solving
them. This does NOT remove loops at runtime — it turns them into named,
independently-analyzable units (predictable for mission-critical use); on CPU a
stepper lowers back to a `while`, on hardware it becomes a process.

- **A loop is an SCC of the call graph.** Reify each SCC into a **stepper** with
  an init / `step` / terminate shape (an actor/agent). Process in **reverse-
  topological order over the condensation** (a DAG, *not* a strict nesting
  chain — an inner loop may be shared by several outer loops; an outer may drive
  several inner ones). Once an SCC's inner loops are reified into opaque bounded
  calls, its body is straight-line-with-stepper-calls → reify it → repeat up to
  `start`. End state: a **tree of steppers**.
- **A stepper's state** = the loop-carried values; its **context** = the
  loop-invariant captures. An SCC with multiple mutually-recursive functions
  reifies into a **union-state FSM** (state encodes *which function of the cycle*
  is active); a single self-recursive function is the one-state special case.
- **`step(state) → Continue{state'} | Done{result}`** — an internal loop is
  *self-driven* (no external event; external events belong only to the top-level
  actor). The `Continue | Done` union IS the terminate mechanism.
- **CRITICAL — non-tail recursion needs an explicit stack.** A tail-recursive SCC
  reifies into a clean loop stepper. A loop that does work *after* the recursive
  call returns (`sum(t)=t.val+sum(l)+sum(r)`) has an implicit call stack; to
  flatten it into a flat `step` you must **defunctionalize the continuation into
  an explicit stack held in the stepper's state**. That explicit stack's depth =
  the recursion-depth bound (already required bounded for WCMC), so it fits — but
  it is the one reification that is not a trivial while-loop, and maintaining
  that stepper-owned stack correctly is the hard, essential part.
- **Bounds compose bottom-up, demanded at reification.** You cannot reify a loop
  into a *bounded* stepper without a bound, so that's exactly where the bound is
  inferred (ranking function vs the iterated collection's capacity) or required
  (warn by default, error under WCET/WCMC). Then WCET(outer) = bound × (per-step
  cost incl. the already-bounded inner stepper call), composed up the tree; WCMC
  = the sum down the *active stepper stack* (each stepper's state + its explicit
  continuation stack), bounded because depths and capacities are bounded and
  each stepper reuses its state in place. This is the OOM/crash elimination, and
  it falls out of the reification order rather than being a separate pass.

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
