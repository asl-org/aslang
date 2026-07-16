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
- `refcount > 1`: **shared**. Multiple consumers reference this value.
  See the read-vs-produce distinction in Step 6 for what "shared"
  actually costs.
- Node is in escape set: **allocate in caller's frame** regardless of
  refcount.

### Step 6. Codegen in topological order

Sort the graph topologically (producers before consumers). For each
node in order:
- **literal**: emit constant, allocate at bump position (or caller's
  region if in escape set).
- **call**: emit function invocation. Copy behavior depends on the
  consumer's kind (see below).
- **branch**: emit conditional dispatch (details below).

At function exit: watermark release. Wipes everything not in the
escape set.

**Read consumers vs producer consumers**. `refcount > 1` doesn't
automatically mean "make copies". Under immutability, multiple readers
can share the SAME memory — no allocation needed for the reads. A copy
(or structural-sharing update) is only required when a consumer
PRODUCES a new version of the value from the old one.

Concretely, each consumer of value `V` is classified as one of:

- **Read consumer** — reads `V`'s memory to compute a NEW value of a
  different shape. Examples: `Vector.count(v)`, `Vector.get(v, i)`,
  `Map.contains(m, k)`. Returns a scalar / boolean / smaller structure
  that doesn't share `V`'s allocation. Codegen: pass `V`'s pointer,
  no copy, no allocation for the input.
- **Producer consumer** — reads `V` AND returns a new version of `V`
  (same type, structurally shared with `V`). Examples: `Vector.assoc(v, i, x)`,
  `Map.dissoc(m, k)`. Under structural sharing, most of `V`'s tree
  nodes are reused; only the path from root to the edited slot is
  copied.

The copy decision then follows from three factors:

| refcount | consumer kind | is this consumer the last use of V? | allocation |
|---|---|---|---|
| 1 | producer | yes (only use) | **reuse-in-place** — mutate V's memory to become V' |
| 1 | reader | yes | no allocation for the input |
| >1 | reader | any position | no allocation for the input |
| >1 | producer | last use of V | **reuse-in-place safe** — later consumers already ran |
| >1 | producer | earlier position | **allocate V' fresh** — later consumers still need V's memory |

"Last use of V" is determined by the topological order plus the DAG's
edge list — the consumer whose position in the topological order comes
after every other consumer of `V` is the last use.

This is the Perceus reuse optimization applied per-use, not just per-
value. A value that's read 100 times then updated once at the end can
still reuse the memory — the update is the last use, so the reads have
all completed.

**When is a function a "producer" of an input?** Annotation-driven for
now: `@produces(param_name)` on the function definition. Structural
data-structure functions (`Vector.assoc`, `Map.dissoc`, ...) get the
annotation; scalar-returning functions default to reader. A stricter
alternative — infer from return type matching one of the input types —
is a natural refinement once we have real data-structure APIs to test
against.

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

## Step 7 (extension) — Value domain tracking

For every node, track its possible value domain: numeric range for
integer / float types, boolean truth set for booleans, variant set
for enums / unions. Enables constant folding, bounds check
elimination, overflow detection, and richer Frama-C numeric contracts.

### Sub-steps

1. **Assign initial domains**:
   - Literal node → singleton domain (exactly the literal value).
   - Function parameter → type's full range (`u8 → [0..255]`, `f32 → [-∞, +∞]`).
2. **Walk in topological order**. Producers before consumers, so every
   call node's inputs already have known domains.
3. **For each call node**, look up the function's *range transfer
   function* — a compile-time-known mapping from input domains to
   output domain:
   - `u32.add([a1..a2], [b1..b2])` → `[a1+b1..a2+b2]` (widen on
     overflow).
   - `u32.lt(x, k)` → boolean domain: if `x.max < k` always true; if
     `x.min >= k` always false; else `{true, false}`.
   - `u8.and(x, 1)` → `{0, 1}` regardless of x.
   - User-defined function with no transfer function → widest range
     (type's full domain).
4. **For each branch node**, split the subject's domain per arm:
   - `match x: case 0: A  case _: B` where x's domain is `[0..5]` → arm
     A sees x ∈ `{0}`; arm B sees x ∈ `[1..5]`.
   - Each arm's sub-DAG re-runs step 3 with the constrained subject
     domain.
   - The branch's output domain = union of arms' output domains (over
     reachable arms only).
5. **Store the final domain on each node**. Metadata alongside
   refcount and escape.

### Post-analysis (optional, ships incrementally)

- **Constant folding**: node with singleton domain → replace with a
  literal node. Rerun DCE.
- **Dead branch elimination**: branch arm whose constrained subject-
  domain is empty (`{}`) is unreachable → prune it.
- **Overflow warning**: arithmetic node whose output domain exceeds
  its result type's max → warn `"arithmetic at <loc> may overflow —
  computed range [..., ...] exceeds u32.max"`.
- **Bounds check elimination**: `array.get(arr, i)` where
  `i.max < arr.length.min` → statically safe, skip the runtime bounds
  check.

### Concrete example

```
x = literal(5)                              # domain: {5}
y = literal(3)                              # domain: {3}
z = call(u32.add, [x, y])                   # domain: {8}
w = call(u32.lt, [z, literal(10)])          # domain: {true}
match w:
  case true:
    literal(1)                              # only reachable arm
  case false:
    literal(0)                              # unreachable — pruned
```

Post-analysis: `w` is known `true`. False arm has empty subject domain
(`w ∈ {false} ∩ {true} = ∅`) → dead. The whole match collapses to
`literal(1)`.

### Recursion handling

For self-recursive functions, the return value's domain depends on
itself (fixed-point). Simplest solution: widen to the type's full
range on the recursive call. Fixed-point iteration is a future
optimization.

### If post-pass eliminates nodes

Post-pass constant folding / dead branch elimination changes the
graph shape. Re-run steps 3-5 (escape → DCE → refcount) after
post-analysis, since some nodes' consumers or reachability may have
changed. The passes are idempotent — running them twice on an
unchanged graph produces no changes.

---

## Step 8 (extension) — Tail call optimization

Find self-recursive tail calls (convert to loops), sibling tail calls
(emit as tail jumps), and warn on non-tail recursion so users know
they'll grow the stack.

### Sub-steps

1. **Locate the return node R** (same as core step 2).
2. **Classify R by kind**:
   - Call node, callee = current function → `SELF_TAIL_CALL` →
     convert to loop (step 4).
   - Call node, callee = different function → `SIBLING_TAIL_CALL` →
     mark for tail-jump codegen.
   - Branch node → recurse: check each arm's tail node with steps 1-3.
   - Literal / variable → not a tail call. Nothing to do.
3. **Detect non-tail recursion and attempt auto-conversion**. If the
   DAG contains a call to the current function anywhere OUTSIDE the
   tail position (its result feeds into another node before reaching
   R), try to rewrite the function into an accumulator-passing form
   that IS tail-recursive. Steps:

   a. **Pattern check**: at the return position, find the recursive
      call and its enclosing consumer.
      - Convertible: `op(rec_call, arg)` or `op(arg, rec_call)` where
        `op` is registered as associative (add / mul / concat / min /
        max / bitwise or / bitwise and / ...) and has a known identity
        element (0 for add, 1 for mul, "" for concat, etc.).
      - Also convertible: `match cond: case A: rec_call  case B: base`
        — the recursive call is a whole arm's tail, base case is the
        other arm. Straightforward loop.
      - Not convertible: multiple recursive calls in one branch (tree
        recursion like `fib(n-1) + fib(n-2)`); recursion under a non-
        associative op; recursion whose result is used in a predicate
        (`if rec(x) then A else B`).

   b. **Rewrite for convertible cases**: synthesize a helper function
      with an extra accumulator parameter. The original function
      becomes a thin wrapper calling the helper with the identity as
      the initial accumulator. The helper's recursive call becomes a
      self-tail-call → picks up the `SELF_TAIL_CALL` treatment from
      step 2. Example:

      ```
      # source (non-tail-recursive)
      func sum(list: List[u32]): u32
        match list:
          case empty:
            0
          case cons(x, xs):
            u32.add(x, sum(xs))          # rec call not in tail — result
                                          # feeds u32.add
      ```

      After auto-conversion:

      ```
      func sum(list: List[u32]): u32
        __asl_sum_tail(list, 0)           # thin wrapper, calls helper

      func __asl_sum_tail(list: List[u32], acc: u32): u32
        match list:
          case empty:
            acc
          case cons(x, xs):
            __asl_sum_tail(xs, u32.add(x, acc))  # self-tail-call now
      ```

      The helper's tail node is a self-call → gets loop rewrite via
      step 4. Zero stack growth. Compiler-generated helpers use the
      `__asl_` reserved prefix to avoid user collision.

   c. **Fall back to warning** if the pattern isn't convertible:
      `"recursive call at <loc> is not in tail position and cannot be
      auto-converted to tail form (reason: <tree recursion | non-
      associative op | predicate use>); will grow the stack"`. User
      can rewrite manually if it matters.

   d. **Auto-conversion invariants**: the rewrite must preserve
      observable semantics. For associative ops with commutativity
      (add, mul), the accumulator order doesn't matter. For non-
      commutative associative ops (concat), the accumulator must be
      built in source order — i.e., `u32.add(x, acc)` for left-fold
      but `str.concat(acc, x)` for right-fold. Op annotations
      indicate associativity + commutativity + identity element.

   e. **Emit an info-level note** (not warning) when auto-conversion
      succeeds: `"recursion at <loc> auto-converted to accumulator
      form (helper: __asl_<fn>_tail)"`. Helps users understand what
      the compiler did — a debugging aid, not a scold.
4. **Self-tail-call rewrite**. The function body becomes a labeled
   loop; the tail call node becomes a "loop-back" jump that overwrites
   the function's parameter slots with the call's arg values. The
   bump allocator's watermark for this function is preserved across
   iterations — no growth.
5. **Sibling-tail-call codegen**. Emit as `[[clang::musttail]] return
   callee(...)` in the generated C (C23 / recent clang). Falls back
   to a normal call on compilers without the attribute — correct but
   less efficient.

### Concrete example

```
func fact(n: u32, acc: u32): u32
  match u32.eq(n, 0):
    case true:
      acc
    case false:
      fact(u32.sub(n, 1), u32.mul(acc, n))   # self-tail-call
```

The `false` arm's tail node is a call to `fact` itself. Marked
`SELF_TAIL_CALL`. Codegen:

```c
uint32_t fact(uint32_t n, uint32_t acc) {
start:
  if (n == 0) return acc;
  uint32_t new_n = n - 1;
  uint32_t new_acc = acc * n;
  n = new_n; acc = new_acc;
  goto start;
}
```

### Mutual recursion

A calls B, B calls A. Neither can be simply looped. Options:
- **Trampoline pattern**: A returns a "thunk" pointing to B; a top-
  level driver alternates. Correct but adds overhead.
- **Merge into a single loop with a dispatch state variable**:
  works when the mutual structure is small.

Recommendation: warn on mutual recursion at first ship (`"mutual
recursion detected between <A>, <B>; will grow the stack"`), leave
optimization for later.

### Sub-step 6 — Termination check and `@depth` requirement

ASL's core stance is "if it compiles, it runs correctly." Unbounded
recursion is a runtime failure mode we can't ship with. After TCO
(self-tail-call rewrite, auto-conversion, mutual-recursion detection),
any function that is STILL recursive at this point represents
potential unbounded stack growth. Every such function must have
provable termination — or an explicit user-visible bound.

Steps:

1. **Identify surviving recursion**. After Step 8's TCO passes, the
   remaining recursive functions are those where:
   - The recursive call is not in tail position AND
   - Auto-conversion didn't apply (tree recursion, non-associative op,
     predicate-gated recursion), OR
   - It's mutual recursion that didn't get trampolined.

2. **Attempt termination proof**. For each surviving recursive
   function, try to prove termination via one of:

   - **Structural decrease**: the recursive call's arg is a proper
     sub-structure of an input parameter. E.g., `sum(cons(x, xs))`
     recurses on `xs`, which is smaller than the matched `cons`
     structure. Verified by matching the case-pattern and confirming
     the recursive arg is one of the pattern's bound sub-parts.
   - **Well-founded measure decrease**: the recursive call decreases
     some natural-number measure. E.g., `fact(n)` where n's value
     domain (from Step 7) proves `n > 0` in the recursive branch AND
     the recursive call uses `n - 1`. The domain check on `n - 1`
     shows `[0..n.max - 1]` which is strictly smaller.
   - **Lexicographic decrease**: for multi-arg functions, tuple of
     arguments decreases lexicographically. Rare in ASL but formally
     supported.

   Value domain tracking from Step 7 feeds directly into this proof
   — the domain of the recursive call's args is what makes structural
   / measure decrease decidable.

3. **If provable → done**. The recursion is bounded; no annotation
   required. Note attached to the function's metadata: `termination:
   proved (structural | measure | lexicographic)`.

4. **If not provable → require `@depth(N)` annotation**. Compile
   error if absent: `"function <name> at <loc> has non-tail recursion
   that could not be proved terminating; add @depth(N) to bound the
   stack depth explicitly"`. The message names which recursion pattern
   defeated the proof (tree recursion, unmeasured decrease, etc.).

5. **`@depth(N)` invariants**:
   - `N` must be a compile-time positive integer literal.
   - The function's declared return type must be `Status[T]` — the
     runtime depth-limit hit returns an `Err`. Compile error if the
     return type isn't `Status[T]`: `"@depth requires the function to
     return Status[T]; got <actual>"`.
   - The `Status[T].Err` variant's error field must be able to
     represent a `STACK_OVERFLOW` code — this is a runtime-defined
     error variant that base.aslr will need to expose (e.g., an
     `Error.stack_overflow` u8 constant).

6. **Codegen for `@depth(N)`**:

   ```c
   // Generated for: @depth(1000) func fib(n: u32): Status[u32]
   Status_u32 fib(uint32_t n, uint32_t __asl_depth) {
       if (__asl_depth == 0) {
           return Status_u32_Err(STACK_OVERFLOW);
       }
       // ... body, each recursive call passes __asl_depth - 1 ...
   }
   ```

   Each function with `@depth(N)` gets an extra hidden parameter
   `__asl_depth`, initialized to N at the top-level call site. Every
   recursive call decrements it. When it hits 0, return
   `Status.Err { error: STACK_OVERFLOW }`. Callers propagate the Err
   via `try` (once Task 21 lands) or explicit match.

7. **Info-level note when auto-conversion or termination proof
   succeeds** — `"recursion at <loc> proved terminating via
   <structural|measure|lex>; no @depth needed"`. Debugging aid for
   users to understand what the compiler proved.

**Example flow**:

```
# structurally decreasing — no annotation needed
func sum(list: List[u32]): u32
  match list:
    case empty: 0
    case cons(x, xs):
      u32.add(x, sum(xs))    # tail-conversion + structural decrease → proved
```

Step 8 auto-converts to accumulator form. The helper is tail-
recursive → step 8's self-tail-call loop rewrite eliminates stack
growth. Termination proof isn't even needed since the loop has no
stack. No `@depth` required.

```
# measure decreases (from value domain) — no annotation needed
func fact(n: u32): u32
  match u32.eq(n, 0):
    case true: 1
    case false: u32.mul(n, fact(u32.sub(n, 1)))
```

Not tail-recursive. Step 8's auto-conversion pattern matches
(`u32.mul` is associative, `1` is its identity) → converts to
accumulator helper, self-tail-call → looped. Termination proved
trivially by the loop.

```
# tree recursion, un-provable — @depth REQUIRED
@depth(50)
func fib(n: u32): Status[u32]
  match u32.eq(n, 0):
    case true: Status.Ok { value: 0 }
    case false:
      match u32.eq(n, 1):
        case true: Status.Ok { value: 1 }
        case false:
          a = try fib(u32.sub(n, 1))
          b = try fib(u32.sub(n, 2))
          Status.Ok { value: u32.add(a, b) }
```

Without `@depth(50)`, compile error. With it, runtime returns Err on
overflow; callers must handle. Note: the return type had to be
`Status[u32]` to accommodate the depth-limit Err path.

---

## Step 9 (extension) — Frama-C spec generation

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

## Step 10 (extension) — Whole-program inlining + effect propagation

Aggressively inline every user-defined function until the program
reduces to a graph of extern calls (marked either `@effect` or default-
pure) plus opaque recursion nodes at recursion boundaries. This shapes
the DAG for the whole-program passes that follow (Steps 11-12).

### Sub-steps

1. **Effect annotation model**:
   - Extern functions may be marked `@effect` (has observable side
     effects — I/O, hardware access, allocation visible outside the
     runtime). Sequentially ordered in the DAG; act as reordering
     barriers.
   - Extern functions default to **pure**. Freely reorderable,
     dedupable, parallelizable. Explicit `@pure` opt-in kept
     equivalent to the default; may be omitted.
   - User-defined functions inherit effect status from their bodies:
     **user function is `@effect` iff any transitively-called extern
     is `@effect`.** Computed via call-graph propagation. No manual
     annotation on user functions.

2. **Non-recursive user function inlining**: every call to a non-
   recursive user function gets its body substituted at the call
   site. After inlining, the function's definition can be dropped
   from the output (unless it's exported or has debug info attached).

3. **Recursive function handling — the two-block split**:

   Every recursive function has this shape (after ANF):
   ```
   func f(args):
     match subject:
       case P1: body1     ← does body1 contain a call to f?
       case P2: body2     ← does body2 contain a call to f?
       ...
   ```

   For each arm:
   - Walk the arm's DAG.
   - If NO node calls `f` → **exit block**. This branch terminates
     the recursion.
   - If ANY node calls `f` → **continuation block**. This branch
     produces a "next iteration."

   Under the two-block split:
   - **Exit blocks are inlined normally** — their bodies are pure sub-
     DAGs (or effect chains), optimized freely alongside the rest of
     the program.
   - **Continuation blocks are inlined normally too**, EXCEPT that
     the recursive call `f(...)` inside them becomes a **loop-back
     edge** — an "opaque recursion node" pointing back at the
     function's condition branch.

   Result: the recursion boundary becomes ONE opaque node in the DAG.
   Everything around it (exit bodies, continuation bodies, the
   condition check itself) is fully visible and optimizable. Only the
   loop-back edge is opaque.

4. **Codegen for the opaque recursion node**:
   - If the recursion is tail (self-tail-call, Step 8 already
     confirmed): the loop-back is a simple `goto` with argument
     updates. No stack growth.
   - If the recursion is non-tail (needs @depth per Step 8 sub-step
     6): the loop-back pushes a continuation frame onto an explicit
     stack (bounded by `@depth(N)` — allocator has room for N
     frames). The condition check pops when a frame's exit-arm
     completes and combines its result with the pending computation
     above.
   - Mutual recursion: same treatment but the "opaque recursion
     node" spans multiple functions. Rare in practice; ships with a
     warning first as noted in Step 8's mutual-recursion section.

5. **Bounded unroll — DEFERRED**. The user's stance: don't unroll
   recursions even for small `@depth(N)`. The two-block split
   captures the optimization value of unrolling (exit/continuation
   bodies get inlined and optimized) without the code-size cost.
   Unroll can be added later as an opt-in optimization flag
   (`--unroll=N`) if profiling shows it helps hot recursion.

6. **Concrete example — fibonacci with `@depth(50)`**:

   ```
   @depth(50)
   func fib(n: u32): Status[u32]
     match u32.eq(n, 0):
       case true: Status.Ok { value: 0 }              ← exit block
       case false:
         match u32.eq(n, 1):
           case true: Status.Ok { value: 1 }          ← exit block
           case false:
             a = try fib(u32.sub(n, 1))               ← continuation
             b = try fib(u32.sub(n, 2))               ← continuation
             Status.Ok { value: u32.add(a, b) }
   ```

   After Step 10:
   - Exit blocks (returning `Status.Ok { value: 0 }` and `Status.Ok { value: 1 }`)
     are inlined into the DAG. Their allocation, initializer construction,
     everything is visible and optimizable.
   - The continuation block's body (`try fib(...)` × 2 + `u32.add` + wrap
     in `Status.Ok`) is inlined too. But the two `fib(...)` calls become
     loop-back edges pointing at the opaque recursion node.
   - The condition tree (two nested `match u32.eq(...)` checks) is a
     regular DAG structure fully visible for CSE / constant-folding.

   Codegen (roughly):
   ```c
   Status_u32 fib(uint32_t n, uint32_t __asl_depth) {
       // The condition tree, effect ops, allocation are inlined.
       // The recursion boundary is preserved as an explicit stack:
       ContinuationFrame stack[50];
       size_t stack_top = 0;
       start:
       if (__asl_depth == 0) return Status_u32_Err(STACK_OVERFLOW);
       if (n == 0) { /* exit inlined */ return Status_u32_Ok(0); }
       if (n == 1) { /* exit inlined */ return Status_u32_Ok(1); }
       // Push continuation frame, then jump back with n-1.
       // ... details on continuation stack management ...
   }
   ```

---

## Step 11 (extension) — Cross-function optimization on the flat DAG

Once user functions are inlined (Step 10), whole-program-level
optimizations become effective because every non-recursive sub-DAG is
now visible.

### Passes to run

- **Cross-function CSE**: structurally identical pure sub-DAGs merge.
  If `foo(1, 2)` appears in two places and `foo` is pure, both call
  sites share the computed result.
- **Cross-function constant folding**: fold chains that span multiple
  inlined layers. `u32.add(u32.mul(u32.add(1, 2), 3), 4)` collapses
  to `13` regardless of how many inlined layers of user helpers are
  between the literals and the outer ops.
- **Cross-function DCE**: pure computations whose result is never
  consumed die. Includes results whose ONLY consumer got DCE'd
  earlier in the pass — iterate until fixed point.
- **Fusion**: pipeline chains on persistent data structures (`map →
  filter → reduce`) collapse into a single walk of the input
  structure. Requires knowing which functions preserve iteration
  structure — likely encoded as `@fusible` annotations on library
  functions initially.

### What effect nodes constrain

Effect nodes (`@effect`-tagged externs) preserve their program order
— they act as sync barriers. Pure nodes BETWEEN two effect nodes may
be freely reordered, dedupped, or hoisted. Pure nodes may NOT cross
an effect node's ordering.

Practical consequence: reading `println("A"); pure_computation();
println("B")` — the `pure_computation` cannot move above `println("A")`
or below `println("B")`, even if it's pure. Between them it's free.

### Post-optimization: re-run core Steps 3-5

Cross-function passes change edge counts, escape sets, and
reachability. Re-run escape analysis, DCE, and refcount analysis
after each optimization pass. They're idempotent — running on an
unchanged graph produces no changes.

---

## Step 12 (extension) — Parallelism identification (metadata only, no auto-schedule)

For each pure sub-graph, identify sets of nodes that are mutually
independent — no data dependency between them. Such sets are
candidates for concurrent execution. **Codegen keeps everything
sequential-but-annotated** for now; a future scheduler / task
runtime can consume the annotations once WCET analysis exists.

### Sub-steps

1. **Sequential barriers**: effect nodes and the opaque recursion
   nodes from Step 10 are barriers. Nothing can be reordered across
   them.
2. **Between barriers, compute pure sub-DAGs**: the pure ops in each
   "region" (between consecutive barriers or between function entry
   and the first barrier) form a sub-DAG.
3. **Within a sub-DAG, compute topological levels**: level = length
   of the longest path from any input to this node. Nodes at the
   same level are mutually independent (no path between them) →
   parallelism candidates.
4. **Emit metadata**: each parallelism candidate group gets an
   attribute on the DAG node — `@parallel_candidate(group_id, N)` —
   where N is the count of nodes in the group and group_id is a
   handle so downstream tools can reference the group.
5. **Codegen stays sequential**: emits every node in topological
   order, one at a time. Attaches the parallel-candidate metadata as
   C comments or LLVM attributes for later consumption.

### Why identification only, not auto-schedule (in this step)

Auto-scheduling requires knowing whether parallelizing a group is
net-positive. Two costs to reason about:
- **Fixed overhead** per spawn (thread creation, task scheduling).
- **Variable cost** per unit of work (runtime of each node).

Without worst-case execution time (WCET) analysis for each function,
we can't know if spawning `N` parallel tasks is faster than running
them sequentially. Task spawn overhead is measured in microseconds;
a two-addition parallelization is a net loss.

**Step 13 delivers WCET analysis.** Once Step 13 lands, Step 12's
"identification only" mode gets upgraded to include an auto-scheduler
that consumes WCET data + spawn overhead constants to decide which
candidate groups get concurrent codegen. Until Step 13 is wired in:
metadata output allows humans to hand-optimize hot paths, and the
`@parallel` annotation lets advanced users opt in explicitly.

### Future extension: `@parallel` user annotation

For advanced users who know their code better than the compiler could,
a `@parallel` annotation on a function body indicates "this pure
region SHOULD be parallelized even without WCET data." Compiler
respects the annotation; emits the concurrent codegen. Same shape as
Rust's `#[inline]` — user hints the optimizer.

Recommendation: annotation opt-in ships alongside the identification
pass. Auto-scheduling in the WCET-informed form comes with Step 13.

---

## Step 13 (extension) — Worst-case execution time (WCET) analysis

Every function's upper-bound execution time, computed from a small
cost model on extern primitives combined with the DAG's structural
information (value domains, `@depth` bounds, effect propagation,
parallelism markers). Enables auto-scheduling (Step 12's deferred
piece), real-time bounds in Frama-C contracts, and user-facing
"this function may exceed X cycles" warnings.

This step is what ties every prior analysis together: value domains
from Step 7 bound loop iterations, `@depth(N)` from Step 8 bounds
non-tail recursion, effect propagation from Step 10 flags unknowable
costs, and parallelism candidates from Step 12 change the cost
formula from sum to max. Without any of those pieces, WCET couldn't
give tight bounds. With them, it's a straightforward bottom-up walk.

### Cost model

Extern functions carry an optional cost annotation:

- **`@cost(cycles: int)`** — fixed cycle count per call. Example:
  ```
  @cost(1)
  @pure
  public func add(a: u32, b: u32): u32   # extern
  ```
- **`@cost(fn: <cost expression>)`** — parametric cost for size-scaling
  ops. Example:
  ```
  @cost(size * 4)
  @pure
  public func memcpy(dst: Ptr, src: Ptr, size: u32): u32   # extern
  ```
  The cost expression may reference input parameters by name. Value
  domains from Step 7 substitute in the max bound to compute the
  worst case.
- **`@cost(unknown)`** or no annotation → cost is opaque. Any function
  transitively calling this becomes opaque too. This is the safe
  default for I/O and hardware ops until real numbers are measured.
- **`@effect(cost: N)`** — for `@effect` externs where the cost is
  bounded despite being side-effectful. E.g., a UART write bounded
  by hardware baud rate. Without a cost annotation, effect externs
  are opaque.

The compiler ships with cost annotations on base.aslr primitives
(u32/u64/f32/f64 arithmetic ops all measured; memcpy / memset scaled
by size). Users adding externs get to annotate their own.

### Sub-steps

1. **Bottom-up traversal** of the call graph. Each function's WCET
   is computed after all its callees' WCETs are known.

2. **For each function body's DAG**, compute the WCET as a walk:
   - **Sequential nodes** in a straight line → **sum** of their WCETs.
   - **Branch node** — worst case is the **max** of the arms' WCETs.
     If Step 7's value domains proved certain arms unreachable,
     they're already eliminated by that step's post-analysis; only
     reachable arms enter the max.
   - **Parallel candidate group** (from Step 12) — cost is the
     **max** of the group's members' WCETs (not the sum), reflecting
     that with auto-scheduling they'd run concurrently. If
     auto-scheduling isn't enabled at codegen time, this is an
     over-approximation of the real sequential cost — safe direction.

3. **For recursive functions** (post-Step 10's two-block split):
   - **Tail-recursive loop** (Step 8's TCO applied → converted to a
     `goto` loop): WCET = `body_cost × max_iterations`. Max
     iterations comes from Step 7's value domain analysis on the
     loop counter.
   - **Non-tail recursion with `@depth(N)`**: WCET = `body_cost × N`
     (each of the N possible recursive levels contributes one body
     execution). This is a conservative over-estimate — tree
     recursion actually costs `body_cost × 2^N` for a depth-N binary
     recursion, but the value-domain-guided body_cost usually shrinks
     with depth, so the tight bound is smaller. For now: use the
     conservative bound; refine to depth-parameterized cost later.
   - **Structurally-decreasing** recursion (Step 8 proved termination
     without `@depth`): value domain gives the max iterations
     directly.

4. **Store WCET on each function's metadata**: `wcet_bound: Option[Cost]`
   where `Cost` is either a concrete cycle count or `Unknown` (any
   opaque cost renders the containing function opaque too).

5. **Emit user warnings** when:
   - Function WCET exceeds a user-declared bound: `@max_cost(cycles)`
     annotation. Missing → no bound checked.
   - Function is marked with an implicit real-time constraint (e.g.,
     interrupt handler) but has non-bounded cost.

### Consumers of WCET data

- **Step 12 auto-scheduler**: with WCET, decides which parallel
  candidate groups actually benefit from concurrent execution. Rough
  rule: parallelize if the sum-of-nodes-in-group WCET is at least
  10× the thread-spawn overhead (measurable per-target constant).
  Below that threshold, sequential is faster.
- **Frama-C ACSL**: emit `@ensures ExecutionTime <= <cycles>` clauses
  alongside the existing type / purity contracts (from Step 9).
- **User warnings**: `"function 'foo' at <loc> has WCET <N> cycles;
  exceeds declared @max_cost(<M>)"`. Fires only when the user
  declared a bound.
- **CLI reporting**: `--report-wcet` flag dumps per-function WCET
  bounds as a table — useful for real-time system audits and for
  spotting regressions across compiler versions.

### Concrete example

```
@cost(1) @pure
public func add(a: u32, b: u32): u32              # extern, WCET 1

@cost(size * 4) @pure
public func memcpy(dst: Ptr, src: Ptr, size: u32): u32   # extern

public func step(x: u32, y: u32): u32
  a = add(x, y)                                   # WCET 1
  b = add(a, x)                                   # WCET 1
  b                                                # (return; no cost)
# WCET(step) = 1 + 1 = 2 cycles

public func window(base: Ptr, buf: Ptr): u32
  # size is a u32 param with domain [0..1024] narrowed by upstream
  memcpy(base, buf, 512)                          # WCET 512 * 4 = 2048
# WCET(window) = 2048 cycles
```

Recursive example (assuming `@depth(50)`):

```
@depth(50)
public func fib(n: u32): Status[u32]
  match u32.eq(n, 0):                             # cost 1
    case true: Status.Ok { value: 0 }             # cost ~5 for wrap
    case false:
      match u32.eq(n, 1):                         # cost 1
        case true: Status.Ok { value: 1 }
        case false:
          a = try fib(u32.sub(n, 1))              # recursive: ~body_cost
          b = try fib(u32.sub(n, 2))              # recursive: ~body_cost
          Status.Ok { value: u32.add(a, b) }      # cost ~6
# body_cost ≈ 15 cycles (arithmetic + Status wraps)
# WCET(fib) = 15 * 50 = 750 cycles (conservative single-path count)
# Tighter tree-recursion bound: 15 * (2^50 - 1) — but bounded by @depth's
# stack limit; the compiler picks whichever is smaller when it can
# derive both. For now: conservative single-path × N.
```

### Limitations

- **No cache / pipeline modeling**. Real CPUs have unpredictable
  memory access costs. Our cost model assumes "each op costs X
  cycles" as a linear approximation. Fine for coarse scheduling
  decisions; not for hard-real-time verification of nanosecond-
  scale bounds. If we later need tighter bounds, per-target cost
  models (that account for cache behavior on specific hardware) can
  be layered on.
- **Non-tail tree recursion bound is loose**. `fib(N)` costs
  ~`O(2^N)` in reality, but the conservative bound above gives
  `O(N × single-invocation)`. For tree recursion this is
  optimistic; the compiler should either fall back to `O(2^N)`
  worst case OR require the user to write a tighter cost model
  (`@cost(2^n)` on the recursive function). Design decision to
  refine.
- **`@effect` externs without `@effect(cost: N)`**: propagate as
  opaque. Any function transitively calling one has unknown WCET.
  Users adding real-time systems in ASL will need to annotate the
  effect costs for the specific hardware they target.

---

## What's deferred (not in the core 1-6 or extensions 7-13)

- **Node origin** (`user` vs `uplifted` vs `expanded` vs `injected`).
  Add later for warning-quality attribution.
- **Purity discrimination** on function calls. Currently treated
  uniformly; extern functions may need `@pure` decorator to
  participate in DCE. Also fed into Step 9 — Frama-C spec generation
  wants the same annotation for `@pure` clause emission.
- **Warning collection** — when DCE removes a user-written node, emit
  a warning through a collector that reports at end-of-pass. Same
  collector serves Step 7 (overflow / bounds warnings), Step 8 (non-
  tail recursion warnings + auto-conversion info notes), and Step 9
  (contract-violation warnings).
- **Cross-function optimization** — inlining, whole-program CSE, cross-
  function value-domain propagation. Per-function scope for now;
  whole-program passes are a later phase.
- **Cyclic-DAG handling** — recursion within a function body doesn't
  produce cycles in the value graph (each invocation is a fresh set
  of nodes). Recursive function calls are opaque edges pointing at
  the function's declaration, not into its body. So the per-function
  DAG stays acyclic per invocation.
- **CPS / defunctionalization for complex non-tail recursion**. Step 8
  auto-converts linear recursion under associative ops via accumulator
  passing. For tree recursion (`fib(n-1) + fib(n-2)`) or non-
  associative op contexts, no auto-conversion — user annotates with
  `@depth(N)` and gets Err propagation. Full CPS-based conversion
  would need closures or defunctionalized continuation records;
  neither exists in the language yet.
- **Inferring `@produces(param)` from function bodies**. Step 6 uses a
  manual annotation to mark producer consumers (functions that return
  a new version of an input). Inference from "does the return value
  transitively share memory with the input?" is decidable on the DAG
  but requires cross-function analysis. Deferred until we have real
  persistent-data-structure APIs (Vector, Map) to test against.
- **Termination proof beyond structural / measure / lex decrease**.
  Step 8's sub-step 6 covers the three standard well-founded orderings.
  More exotic patterns (co-inductive definitions, size-change
  termination via automata) can be added later if real code needs
  them. For now, non-provable → `@depth(N)`.
- **Cache-aware / pipeline-aware WCET**. Step 13 provides linear-cost
  WCET based on `@cost` annotations. Modern CPUs' cache misses, branch
  mispredicts, and pipeline stalls introduce nonlinear variance. A
  per-target cost model that layers on top of Step 13 (using measured
  hardware profiles) is a future refinement.
- **Tight tree-recursion cost bounds**. Step 13's initial approach
  uses `body_cost × @depth(N)` for non-tail recursion — conservative
  for linear cases, optimistic for tree recursion. A refined analysis
  that derives `O(2^N)` bounds for genuine tree recursion (like `fib`)
  requires either user-annotated cost formulas or automated
  recurrence-relation solving. Deferred until real code needs it.
- **Bounded unroll of small `@depth(N)` recursion**. Step 10's two-
  block split captures the optimization value of unrolling (exit /
  continuation bodies get inlined and optimized) without the code-
  size cost of unrolling itself. Adding an `--unroll=N` flag as an
  opt-in optimization is straightforward once profiling shows hot
  recursion where full unroll would help — deferred until then.

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
4. Add refcount analysis + DCE (core steps 4-5).
5. Add escape set computation (core step 3).
6. Wire codegen (core step 6) — bump allocator with reuse-in-place
   for `refcount == 1`.
7. Extension: value domain tracking (Step 7). Ships in phases —
   initial-domains + transfer-function walk first; post-analysis
   (constant folding, dead branch elimination, overflow warnings,
   bounds check elimination) added incrementally.
8. Extension: tail call optimization (Step 8). Self-tail-call loop
   rewrite first (simplest, biggest win). Auto-conversion of non-tail
   recursion (accumulator-passing rewrite) second. Mutual recursion
   warning + trampoline third. Termination check + `@depth(N)`
   enforcement last (relies on value domains from Step 7 for
   structural / measure decrease proofs).
9. Extension: Frama-C spec generation (Step 9). Minimal ACSL surface
   (`@requires` / `@ensures` / `@pure`) first. Numeric bounds in
   contracts (feeding off Step 7's domain tracking) second.
   `@assigns` clauses (memory footprint from escape sets) third.
10. Extension: whole-program inlining + effect propagation (Step 10).
    Non-recursive user functions inline unconditionally; recursive
    functions get the two-block split (exit + continuation bodies
    inlined; recursion boundary as an opaque loop-back node).
    `@effect` annotation on externs; user function purity derived
    transitively from the call graph.
11. Extension: cross-function optimization on the flat DAG (Step 11).
    CSE / constant folding / DCE / fusion, all effective once Step 10
    has flattened the graph. Effect nodes preserve program order;
    pure ops reorder freely between barriers.
12. Extension: parallelism identification (Step 12). Metadata-only
    output ("these N nodes at level L are mutually independent").
    Sequential codegen with annotations. Auto-scheduler upgraded
    with Step 13's WCET data.
13. Extension: WCET analysis (Step 13). Cost annotations on extern
    primitives + bottom-up walk. Feeds Step 12's auto-scheduler,
    Frama-C ExecutionTime bounds (Step 9), and user-facing
    `@max_cost` violation warnings.

Core steps 3-6 can ship independently, each adding capability without
breaking the prior stage. Extensions (Steps 7-13) run atop the core
DAG and each can ship in phases as described above. The pipeline
order at codegen time:

```
Core Step 1-5:   Build → return → escape → DCE → refcount
Extension 7:     Value domain tracking (+ post-pass: const fold,
                 dead branch elimination; re-run 3-5 if any changes)
Extension 8:     Tail call detection + auto-conversion + termination
                 proof + @depth enforcement for non-tail recursion
Extension 10:    Whole-program inlining (non-recursive functions
                 fully; recursive via two-block split); effect
                 propagation across the call graph
Extension 11:    Cross-function CSE / constant folding / DCE /
                 fusion (re-runs core Steps 3-5 as needed)
Extension 13:    WCET analysis (bottom-up cost walk; uses Step 7's
                 value domains + Step 8's @depth + Step 10's effect
                 propagation)
Extension 12:    Parallelism identification (metadata output) +
                 auto-scheduling using Step 13's WCET data
Core Step 6:     Codegen (informed by all metadata above)
Extension 9:     Frama-C spec emission alongside codegen output
                 (includes WCET as @ensures ExecutionTime clauses)
```
