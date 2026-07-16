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

### Algorithm

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

### Algorithm

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
time properties that map directly onto ACSL annotations. This step
emits the ACSL alongside the generated C code.

### Algorithm

For each function `f` in the DAG:

1. **Open an ACSL block** (`/*@ */`) immediately before the C function
   definition.

2. **Emit `@requires` clauses from parameter types**:
   - For each pointer parameter `p`: emit `\valid(p)`.
   - For each parameter with a value-domain-narrowed range `[lo..hi]`
     from Step 7: emit `p >= lo && p <= hi`.

3. **Emit `@ensures` clauses on the return**:
   - Base type invariant (matches the declared return type).
   - If Step 7 narrowed the return's value domain to `[lo..hi]`:
     emit `\result >= lo && \result <= hi`.

4. **Emit `@assigns` clause from the escape set** (core Step 3):
   - For each escaping value, name the memory region it writes into
     (caller's frame vs local bump vs a specific global).
   - If no writes escape: emit `assigns \nothing;`.

5. **Emit `@pure` if the function is pure** (Step 10's transitive
   effect propagation says no `@effect` extern is reachable).

6. **Emit `@ensures ExecutionTime <= N`** where N is the WCET from
   Step 13.

7. **Emit module-level `@axiom` and `@invariant` blocks for the bump
   allocator** — once per compilation unit, not per function.
   `bump_ptr <= capacity`, `watermark_stack.top >= 0`, etc.

8. **Close the ACSL block** and emit the C function body from Step 17.

### What the ACSL captures per source construct

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

### Algorithm

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

### Algorithm

Run these passes to fixed point (re-run until no pass makes changes):

1. **Cross-function CSE**. Walk the DAG bottom-up. For each pair of
   pure nodes with identical function ref AND identical input edges,
   merge into a single node whose out-edge set is the union of both
   originals. Structurally identical pure sub-DAGs collapse to one.
   Example: `foo(1, 2)` appearing in two places (with `foo` pure)
   becomes one computed value shared by both call sites.

2. **Cross-function constant folding**. For each pure node whose
   every input is a constant (singleton domain from Step 7),
   evaluate the function at compile time. Replace the node with a
   constant node holding the result. Example:
   `u32.add(u32.mul(u32.add(1, 2), 3), 4)` collapses to `13`
   regardless of how many inlined layers separate the literals from
   the outer ops.

3. **Cross-function DCE**. For each node with zero outgoing edges,
   not in the escape set, and not `@effect`-side-effecting: remove.
   May cascade — removing a node reduces its inputs' out-degrees,
   which may make them removable. Iterate until stable.

4. **Fusion**. For each pipeline chain (`map → filter → reduce`
   over a persistent structure), merge the operations into a single
   walk of the input. Requires `@fusible` annotation on library
   functions to participate. The pipeline chain must be pure end-to-
   end; any `@effect` node in the middle is a fusion barrier.

5. **Re-run core Steps 3-5** (escape → DCE → refcount) after each
   optimization pass since edge counts and reachability may have
   changed. Passes are idempotent — running them on an unchanged
   graph produces no changes.

### What effect nodes constrain

Effect nodes (`@effect`-tagged externs) preserve their program order
— they act as sync barriers. Pure nodes BETWEEN two effect nodes may
be freely reordered, dedupped, or hoisted. Pure nodes may NOT cross
an effect node's ordering.

Practical consequence: reading `println("A"); pure_computation();
println("B")` — the `pure_computation` cannot move above `println("A")`
or below `println("B")`, even if it's pure. Between them it's free.

---

## Step 12 (extension) — Parallelism identification (metadata only, no auto-schedule)

For each pure sub-graph, identify sets of nodes that are mutually
independent — no data dependency between them. Such sets are
candidates for concurrent execution. **Codegen keeps everything
sequential-but-annotated** for now; a future scheduler / task
runtime can consume the annotations once WCET analysis exists.

### Algorithm

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

### Algorithm

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

## Step 20 (extension) — Pure kernel extraction

Every real computation is triggered by a side-effect input (a syscall
return, an interrupt, a UART byte arriving, a timer tick) and ends in
another side-effect output (a MMIO write, a syscall, a network send,
an actuator command). Between those two effect boundaries lives
**pure computation** — nodes with no observable interaction with the
outside world.

This step **cuts the DAG at effect nodes** and extracts each
connected pure sub-DAG as a standalone function ("**pure kernel**").
The whole program then reshapes into:

```
event loop:
  for each triggering effect:
    read the effect's output
    run the downstream pure kernel
    write the kernel's output to the next effect
```

Because every kernel is pure, its full storage footprint is derivable
at compile time from Steps 5 (refcount), 7 (value domains), 14
(bit-widths), and 15 (data layout). One kernel = one fixed
scratch region. No dynamic allocation. No GC. No malloc. Ever.

### Motivation

The insight the user articulated: every computation has an effect
boundary on both ends. Extracting the pure interior as its own
function creates a tight, closed unit that the compiler can size,
schedule, and place with full information. This mirrors the actor
model, the Elm architecture, and ROS's callback-per-topic design —
but applied structurally by the compiler, not manually by the
programmer.

Once kernels are the unit of codegen, the runtime becomes trivial:
a dispatcher that maps effect events to kernels. Everything
non-trivial happens inside pure functions with pre-computed
resource envelopes.

### Algorithm

1. **Locate effect boundaries.** Walk the fully-inlined DAG (post
   Step 10). Mark every `@effect` extern node as a **boundary**.
   Boundaries have two roles: **effect input** (produces data,
   consumed by pure nodes) and **effect output** (consumes data,
   produced by pure nodes). A single boundary can play both roles
   for adjacent kernels.
2. **Partition into pure regions.** Remove every boundary node from
   the DAG. What remains is a forest of connected pure sub-DAGs.
   Each connected component is one **kernel candidate**.
3. **Assign inputs/outputs per kernel.** For each candidate:
   - Inputs = edges that crossed into the region from a removed
     boundary (effect input's output).
   - Outputs = edges that crossed out of the region into a removed
     boundary (effect output's input).
   - Kernel signature: `kernel_N(inputs...) -> outputs...`.
4. **Compute the fixed memory footprint.** Walk each kernel's DAG:
   - Sum every intermediate node's storage width (Step 14).
   - Subtract savings from Step 5 reuse-in-place (values whose
     lifetime ends before the kernel exits share storage with later
     nodes).
   - Add any Step 15 struct-layout padding.
   - Round to Step 15's cache-line alignment.
   - Result: one `KERNEL_N_SCRATCH_BYTES` constant per kernel.
5. **Compute the fixed WCET.** Sum Step 13 per-node WCETs along
   each kernel's critical path. Result: one `KERNEL_N_WCET_CYCLES`
   constant per kernel.
6. **Build the dispatch table.** Emit a static table:
   `event_type → kernel_id`. Every boundary that acts as an
   effect input becomes an entry; the kernel it triggers is the
   downstream pure region.
7. **Wire kernel outputs to next effects.** Each kernel's outputs
   feed one or more downstream effect boundaries. Emit the direct
   wiring — kernel returns a struct; dispatcher hands each field
   to the right effect output.
8. **Assemble the top-level runtime.** For CPU (Step 17): a loop
   that reads events, looks up the kernel, invokes it against the
   kernel's pre-allocated scratch, and dispatches outputs. For
   FPGA (Steps 18-19): each kernel becomes a SystemVerilog module;
   boundaries become I/O ports; wiring is direct hardware.

### Concrete example

Source:

```
func on_button_press():
  raw    = read_button()          # effect input
  scaled = u32.mul(raw, 100)      # pure
  offset = u32.add(scaled, 42)    # pure
  write_display(offset)           # effect output
```

DAG after inlining:

```
  [read_button]           # effect input boundary
       │
       ▼
  ┌─────────────────────┐
  │  scaled = mul(raw)  │ ← pure kernel A
  │  offset = add(scld) │
  └─────────────────────┘
       │
       ▼
  [write_display]         # effect output boundary
```

Extracted:

```
kernel_A(raw: u10) -> u17:
  scaled = raw * 100     # domain [0..99900] → 17 bits
  offset = scaled + 42   # domain [0..99942] → 17 bits
  return offset

KERNEL_A_SCRATCH_BYTES = 4   # single u17 intermediate, byte-aligned
KERNEL_A_WCET_CYCLES   = 2   # mul + add per Step 13

dispatch_table:
  BUTTON_PRESS → kernel_A → write_display
```

Runtime loop (CPU):

```
static uint8_t kernel_A_scratch[KERNEL_A_SCRATCH_BYTES];

while (true) {
    event = wait_for_event();
    switch (event.type) {
    case BUTTON_PRESS: {
        u17 result = kernel_A(event.raw, kernel_A_scratch);
        write_display(result);
        break;
    }
    // ...
    }
}
```

FPGA (SystemVerilog): `kernel_A` becomes a module with `raw`/`clk`
input ports and `offset` output port; `write_display` is a
downstream module wired directly to `kernel_A.offset`; the
dispatcher collapses into hardware event registers.

### Consequences

- **Zero dynamic allocation** inside pure kernels. The scratch is
  a fixed static buffer per kernel.
- **Deterministic per-event WCET.** Combined with Step 13, each
  event's response latency is a compile-time constant.
- **Deterministic memory profile.** Total RAM = sum of every
  kernel's scratch + effect boundary buffers. Known at link time.
- **Composable.** Kernels connect via effect boundaries; any
  kernel can be swapped or re-targeted independently.
- **Natural parallelism unit.** Two kernels triggered by
  independent effects can run concurrently — on separate cores,
  separate SIMD lanes, or separate hardware modules. Step 12's
  parallelism analysis lifts to the kernel level for free.
- **Cache-friendly.** Each kernel's scratch is sized to fit in
  L1/L2. Since Step 14 has already narrowed widths, kernels
  become surprisingly small (often a few dozen bytes).
- **FPGA-friendly.** The kernel graph *is* the netlist.
  Effect boundaries are I/O ports; kernels are combinational
  modules; the whole thing synthesizes as-is.
- **Real-time-friendly.** Bounded WCET per event = deterministic
  latency. The scheduler needs no runtime analysis; every kernel's
  worst case is stamped at compile time.

### Kernel-level allocation (from the user's `examples/allocator.c`)

The bump-allocator watermark pattern from `examples/allocator.c`
becomes structurally trivial under kernel extraction:

- Each kernel has one static scratch region sized to
  `KERNEL_N_SCRATCH_BYTES`.
- On kernel entry: `bump_ptr = 0` (implicit — the scratch is empty
  because the previous invocation returned).
- All intermediate values allocate from the scratch by bump —
  literally `scratch + offset` where offset is the compile-time
  layout position.
- On kernel exit: no explicit release needed. The scratch is
  logically empty again (nothing outlives the kernel — that's the
  definition of "pure").
- The watermark-based `stack_release` from the C prototype maps
  to kernel exit: the entire scratch is "released" at once.

Nested watermarks (Frame 1 / Frame 2 in the prototype) collapse
into nested kernel invocations — one kernel calls another (via
Step 10 inlining they usually flatten, but if a kernel is emitted
as a helper the caller reserves the callee's scratch region
inside its own).

### Effect chains and boundary buffers

Values crossing effect boundaries need somewhere to live between
kernels. Options:

- **Register-passed** — kernel N returns a small struct; the
  dispatcher immediately passes it to boundary N+1 (no buffer
  needed).
- **Boundary buffer** — for wide payloads, a fixed-size static
  buffer sits between the kernel and the effect output. Sized
  from the kernel's output signature.
- **FIFO / async channel** — if the boundary crosses a clock
  domain or the effect produces asynchronously, a bounded FIFO
  (whose depth is compile-time picked from arrival-rate
  annotations, when available; otherwise a user-set default).

Design: default to register-passed; upgrade to buffer or FIFO
when kernel outputs exceed a threshold OR when the boundary is
marked `@async`.

### Kernels that are trivial

- **Effect-to-effect with no pure computation.** `read_uart → write_led`
  extracts an empty kernel; codegen collapses it to direct wiring.
  No scratch. Zero WCET contribution.
- **Kernels with a single node.** Common case. Scratch = one
  storage width. Still worth extracting for uniformity.
- **Effect fan-out.** One effect input feeds two independent pure
  regions. Extract each as its own kernel; the dispatcher invokes
  both (concurrently if independent — see Step 12).

### Interaction with other steps

- **Step 10 (whole-program inlining)** — MUST run first. Kernels
  are extracted from the fully-inlined DAG so no user function
  boundary blocks a pure region from being one connected
  component.
- **Step 11 (cross-function CSE / fusion)** — MUST run first.
  Redundant nodes eliminated before extraction give tighter
  kernel footprints and shorter WCET.
- **Step 12 (parallelism)** — kernel boundaries become the
  natural parallelism unit. Step 12's node-level metadata lifts
  to kernel-level metadata: "kernels A and B triggered by
  independent effects have no data dependency → run concurrently".
- **Step 13 (WCET)** — per-node WCETs from Step 13 sum into
  per-kernel WCET. Step 20 does not re-derive; it aggregates.
- **Steps 14-16 (codegen prep)** — now operate **per-kernel**.
  Bit-width narrowing is scoped inside each kernel's scratch.
  AoS/SoA layout is per-kernel. Register allocation is per-kernel.
  The unit of preparation shrinks from "one function" to "one
  kernel", which is smaller and tighter — better register
  pressure, better cache behavior.
- **Step 17 (CPU codegen)** — emits one C function per kernel
  plus one dispatch loop plus one static scratch buffer per
  kernel. No malloc/free anywhere in generated code.
- **Steps 18-19 (FPGA codegen)** — emits one SystemVerilog
  module per kernel plus wiring for effect boundaries. Kernel
  extraction *is* the RTL structure.

### Limitations

- **Requires `@effect` accuracy.** If the user omits `@effect` on
  an extern that IS effectful, that node will be treated as pure
  and get inlined into a kernel — subtle correctness bug. Step 10
  already relies on the annotation; Step 20 inherits that
  assumption.
- **Kernels containing long-running loops** (bounded but large N)
  can produce large WCET numbers. Not a correctness issue but the
  scheduler may want to split them. Design decision to refine:
  optional `@split_at(loop)` to force a kernel boundary in the
  middle of a long computation.
- **Effect fan-in coalescing.** If two effects want to trigger
  the same kernel (e.g., either of two buttons updates the
  display), the dispatcher gets N entries pointing at the same
  kernel. Straightforward but worth noting for dispatch-table
  size.

---

## Target-agnostic codegen preparation (Steps 14-16)

Steps 1-13 are DAG-level analyses. Step 20 reshapes the DAG into
kernels + dispatch. Steps 14-16 are optimization passes that
decorate **each kernel** with codegen-ready metadata, usable by both
the CPU backend (Step 17) and the FPGA backend (Steps 18-19). They
run once per kernel and their output feeds every target.

## Step 14 (extension) — Bit-width narrowing

Value domain tracking (Step 7) already knows every variable's actual
range. This step CONSUMES those domains and annotates each node with
the narrowest storage type that fits.

### Algorithm

For each node `N` in the DAG:

1. **Read `N`'s value domain** from Step 7's tracking.

2. **Compute minimum storage width** based on the domain:
   - **Unsigned integer type**: find smallest `w ∈ {8, 16, 32, 64}`
     such that `hi < 2^w`. Assign width `w` bits.
   - **Signed integer type**: find smallest `w ∈ {8, 16, 32, 64}`
     such that `-2^(w-1) ≤ lo` AND `hi < 2^(w-1)`. Assign width
     `w` bits.
   - **Float type** (`f32`, `f64`): no narrowing (IEEE-754 widths
     are fixed). Preserve original type. Later: `f16` narrowing
     for targets with hardware support.
   - **Singleton domain `{k}`**: mark as **constant**, width = 0.
     Codegen inlines the literal wherever the value is referenced;
     no runtime storage.

3. **Store `narrowed_width` and `is_constant` on `N`'s metadata**.

Downstream steps consume this metadata when picking storage form.

### Consumers

- **Step 15** — layout optimization uses narrowed widths to decide
  struct field ordering and packing.
- **Step 17** — CPU codegen emits bit-fields when packing saves memory.
- **Step 19** — SystemVerilog emission uses narrowed widths as exact
  `logic [WIDTH-1:0]` wire widths (big FPGA area savings on custom
  logic).
- **Step 9** — Frama-C `@requires` clauses gain tighter bounds.

### Trade-off

Bit-packed struct fields are slower to access than word-aligned on
CPUs (require mask + shift). Codegen (Step 17) picks the trade-off:
narrow-when-storage-dominates, word-align-when-access-dominates.
Heuristic driven by Step 7's access-frequency data (from parallelism
scheduling; hot fields stay word-aligned).

---

## Step 15 (extension) — Data layout optimization

Access-pattern analysis on the DAG picks the memory layout for each
composite type (struct, union, array-of-struct):

### Algorithm

1. **For each struct type**, walk every DAG node that accesses one of
   its fields. Build a co-access matrix: `M[i][j] = # of nodes that
   read both field i and field j`.
2. **Cluster co-accessed fields**: fields with high mutual co-access
   go into the same cache line; fields never co-accessed can be split
   into separate structs (**Struct-of-Arrays**) or pushed to a cold
   area.
3. **For arrays of struct**, decide **AoS vs SoA**:
   - **AoS (Array of Struct)**: layout as `[s0, s1, s2, ...]` where
     each `si` has all fields together. Good when all fields of one
     element are read together.
   - **SoA (Struct of Arrays)**: layout as `[f0_0, f0_1, ..., f1_0,
     f1_1, ...]` where each field forms a contiguous array. Good when
     one field is read across many elements (SIMD-friendly).
   - Decision: SoA when any field is accessed in a hot loop
     independently of the others (from parallelism candidates in
     Step 12 + WCET hotness in Step 13); AoS otherwise.
4. **Align hot fields to cache lines**. Cache line size is a target
   parameter (64 bytes on x86, 128 on some ARM). Emit padding to
   avoid false sharing between hot fields of different logical
   objects.
5. **Push cold fields to separate cache lines**. Fields never
   co-accessed with the hot set live in their own memory region.

### Consumers

- **Step 17** — CPU codegen emits struct definitions with the chosen
  layout, padding, and split (AoS-vs-SoA).
- **Step 19** — SystemVerilog emission uses layout choices to
  instantiate BRAM banks and their access ports (SoA fields →
  separate BRAM banks enabling parallel access).

### Concrete example

```
type Particle:
  struct:
    x: u32          # accessed in every physics step
    y: u32          # accessed in every physics step
    color: u32      # accessed only during rendering
```

Access pattern shows `x` and `y` co-accessed constantly (hot); `color`
accessed rarely (cold). Layout decision: `x` and `y` co-located
(same cache line); `color` split into a parallel array
(`particle_colors[]`) that only rendering touches. Cache footprint
during physics loop halved.

---

## Step 16 (extension) — Instruction scheduling + register allocation

Whole-program DAG lets us do register allocation and instruction
scheduling BETTER than a per-function optimizer typically does,
because we see all producer/consumer relationships including across
inlined function boundaries.

### Algorithm

1. **Live range analysis**. Already computed as refcount + escape
   metadata (core Step 5). For each value: live from definition to
   last use.
2. **Register allocation** — graph coloring or linear scan on the
   DAG's live ranges. Prefer registers for values with:
   - Small live range (short-lived intermediates).
   - Refcount == 1 (linear, no aliasing concerns).
   - High access frequency (from Step 13's WCET path analysis).
3. **Spill decisions** — when register pressure exceeds count,
   pick which values spill to memory. Prefer to spill:
   - Values with the longest remaining live range.
   - Values in cold branches.
   - Values whose consumers are far in the topological order.
4. **Instruction scheduling** — topological order gives basic
   correctness; latency-aware scheduling picks a schedule that
   minimizes stalls:
   - Reorder within same topological level based on producer latency.
   - Software pipelining for loops: overlap iterations to keep
     pipelines full.
   - Loop unrolling driven by value-domain bounds (Step 7) + WCET
     (Step 13) — unroll iff unrolled code fits in the target's
     instruction cache.
5. **SIMD grouping** — parallel candidates from Step 12 group into
   vector ops when the group is uniform (same op on different
   inputs). Emits SIMD intrinsics on CPUs; parallel hardware
   pipelines on FPGA.

### Consumers

- **Step 17** — CPU codegen uses the register-allocated + scheduled
  representation directly. Little further optimization needed at the
  C level — the C code emitted encodes the schedule via variable
  ordering and explicit `register` hints (though modern compilers
  ignore `register`; we lean on LLVM's own scheduler as backup).
- **Step 19** — SystemVerilog emitter uses the schedule as the
  pipeline stage assignment: each topological level = one clock
  cycle; SIMD group = parallel hardware modules.

---

## Level 1 — CPU codegen (target-first)

## Step 17 (extension) — CPU C codegen backend

Emit optimized C for each function using the analyses from Steps
1-16. Target: hand-written-assembly quality without user intervention.

### Algorithm

For each function `f` in the flattened DAG, emit the following C
constructs in order:

1. **Function signature**: derived from analyzed type + calling
   convention. For hot pure functions with few args, emit as
   `static inline`; for cold or externally-visible, standard function.
2. **Parameter passing**: use registers where possible (small values,
   pointer to bump region for escapes).
3. **Local variables**: emitted in the register-allocation order from
   Step 16. Bit-packed struct fields per Step 14.
4. **Struct definitions**: use the layout chosen in Step 15 (AoS vs
   SoA, padding, cache alignment via `alignas`).
5. **Loop code**: unrolled / tiled / software-pipelined per Step 16.
6. **SIMD**: parallel groups from Step 12 emit as SIMD intrinsics
   (`_mm256_add_epi32` on x86 AVX2, `vaddq_u32` on ARM NEON).
   Compiler-target-portable via `<simde/simde.h>` or LLVM
   intrinsics.
7. **Branches**: reorder branch arms by execution frequency (from
   Step 13 WCET). Emit `__builtin_expect` hints for cold arms.
8. **Function calls**: only remain for opaque recursion nodes
   (Step 10) and `@effect` externs. Everything else was inlined
   away.

### Frama-C ACSL comments

Step 9's ACSL clauses are emitted as C comments in the same output.
The `@requires` / `@ensures` / `@assigns` clauses derive from types
+ value domains + escape sets already computed. Frama-C's proof
kernel can then verify the emitted C matches its contract.

### Output shape

For a function like `step(x, y)` from the earlier example, the C
output would look like:

```c
/*@ requires x < 1000 && y < 1000;
    ensures \result <= 2000;
    assigns \nothing;
    pure;
    ensures ExecutionTime <= 2;
*/
static inline uint16_t step(uint16_t x, uint16_t y) {
    return (uint16_t)(x + y + x);   // bit-narrowed from u32 → u16 (Step 14)
}
```

Note the `uint16_t` instead of `uint32_t` (bit-narrowing), the
`static inline` (Step 10's inlining decision), and the ACSL clauses
including `ExecutionTime` (Step 13).

### No abstraction penalty guarantee

By the end of Step 17, generated code has:
- Zero dynamic dispatch.
- Zero runtime type checks.
- Zero unnecessary allocations (bump only, with refcount-driven
  reuse).
- Zero call overhead for user functions (all inlined).
- Zero branch overhead for match arms proved dead (Step 7's
  post-analysis).
- Zero bounds checks that Step 7 proved safe.

This is the "if it compiles, it runs correctly AND fast" delivery.

---

## Level 2 — FPGA / SystemVerilog codegen (future target)

## Step 18 (extension) — FPGA resource estimation

Companion to WCET (Step 13) but measures HARDWARE AREA instead of
execution TIME. Every operation costs some number of FPGA primitives
(LUTs for logic, BRAMs for memory, DSPs for multiplication).

### Cost model

- **`@fpga_cost(luts: N, brams: M, dsps: K)`** on extern functions
  (e.g., a hardware-multiplier op costs 1 DSP block; a u32 add costs
  ~32 LUTs).
- **Value-domain narrowed widths** (Step 14) directly reduce LUT
  counts (a 7-bit add costs 7 LUTs, not 32).
- **Data layout** (Step 15) determines BRAM organization: AoS uses
  wide BRAM ports; SoA uses multiple parallel BRAM banks.

### Algorithm

Bottom-up traversal of the call graph, mirroring WCET (Step 13):

1. **For each extern function**, look up its `@fpga_cost(luts, brams,
   dsps)` annotation. Missing annotation → resource cost is opaque;
   propagates up as opaque for any function transitively calling it.

2. **For each user-defined function** (post-Step 10 inlining, only
   opaque calls remain):

   Compute resource cost per DAG node then combine:
   - **Sequential nodes**: sum resource costs (LUTs + LUTs, BRAMs +
     BRAMs, DSPs + DSPs component-wise).
   - **Branch node**: max of arms' costs — both arms must exist in
     hardware simultaneously; the branch is a mux selecting one.
   - **Parallel candidate group** (Step 12): sum — each parallel
     pipeline exists as physical hardware, not shared.
   - **Opaque recursion** (Step 10's two-block split): cost of one
     iteration. Hardware reuses the same pipeline stages across
     iterations; depth doesn't multiply area.

3. **Apply Step 14's bit-width narrowing** to reduce per-operation
   LUT counts. A u8 add costs ~8 LUTs, not 32 like a u32 add.

4. **Store `fpga_resource: Option[ResourceCost]` on each function's
   metadata**, where `ResourceCost = (luts, brams, dsps)`.

5. **Compare against target FPGA capacity** (a target-specific
   configuration constant). For each function exceeding budget on
   any resource dimension, emit a warning: `"function 'foo' at
   <loc> requires <X> LUTs; exceeds target FPGA budget (<Y> LUTs)"`.

6. **Auto-serialization decision**: if a parallel candidate group
   from Step 12 would blow the LUT budget when parallelized,
   demote it back to sequential codegen — trades time for area.
   This is the inverse of Step 12's parallelization promotion.

### Consumers

- **Step 19** — SystemVerilog emitter uses total resource cost to
  fail fast if the design won't fit the target FPGA.
- **User warnings**: `"function 'foo' at <loc> requires <X> LUTs;
  exceeds target FPGA's budget (<Y> LUTs)"`.
- **Auto-serialization decisions**: if a parallel group blows the
  LUT budget, serialize it instead (opposite of Step 12's parallel
  candidate promotion; trade time for area).

---

## Step 19 (extension) — SystemVerilog emitter backend

Emit synthesizable SystemVerilog directly — bypassing HLS entirely.
The DAG's structure (Steps 1-16) already carries the pipelining,
resource, and scheduling decisions HLS would compute; going direct
to SystemVerilog cuts a translation layer and its associated
overhead (HLS-injected FIFOs, extra state registers, generic control
logic that our analyses make unnecessary).

Chosen dialect: **SystemVerilog (IEEE 1800)** rather than Verilog
2005 or VHDL. Reasons:
- `logic` type + `always_ff` / `always_comb` blocks give unambiguous
  register vs combinational intent (Verilog's `reg`/`wire` is a
  common source of synthesis surprises).
- Packed structs and arrays map directly onto Step 15's AoS layouts.
- Interfaces / modports let us bundle bus signals cleanly for
  effect-node peripherals.
- Bit-width parameterization (`logic [WIDTH-1:0]`) accepts Step 14's
  narrowed widths as generic parameters.
- Supported by every major open-source and vendor toolchain
  (Verilator, Yosys, Vivado, Quartus, IceStorm).

### Algorithm

For each function in the flattened DAG (post-Step 10 inlining), emit
a SystemVerilog module:

1. **Module declaration**. `module <name> #(parameter WIDTH_...)
   (input logic clk, input logic rst_n, ...ports)`. One `input`
   port per parameter, one `output` port per return value. Widths
   from Step 14 (`logic [6:0] p` for a u7 parameter, not
   `logic [31:0]`).

2. **Declare intermediate signals**. For every DAG node, emit a
   `logic [WIDTH-1:0] <node_name>;` declaration. Naming follows the
   ANF `__asl_arg_N` scheme so names are traceable back to source
   for waveform debugging.

3. **For each DAG node in topological order**, emit its hardware:
   - **Pure combinational op** (add, mul, and, comparisons):
     `assign <out> = <op>(<in1>, <in2>);` — inferred as LUTs/DSPs
     by the synthesis tool.
   - **Extern call**: instantiate the pre-existing IP module by
     name — `add32 u_add_0 (.a(x), .b(y), .out(z));`. Extern IPs
     ship as SystemVerilog libraries in a companion `runtime.sv`.
   - **Branch node**: ternary or `always_comb` mux —
     `assign <out> = <cond> ? <arm_true> : <arm_false>;`.
   - **Opaque recursion** (Step 10's two-block split): a
     `typedef enum {S_COND, S_ARM_...} state_t;` state machine
     with an `always_ff @(posedge clk)` block that transitions
     between states and holds iteration-state registers.

4. **Wire producer outputs to consumer inputs** following DAG edges.
   Widths carry through Step 14's narrowed types end-to-end.

5. **Instantiate BRAMs for large data structures** per Step 15's
   layout decisions:
   - **AoS layout** → single BRAM with wide data ports. Emit as
     `bram_1p #(.WIDTH, .DEPTH) u_bram (...)` instantiation.
   - **SoA layout** → one BRAM per field, enabling parallel access.
     Each field's BRAM sized by that field's Step 14 width.

6. **Assign pipeline stages from Step 16's schedule**. Each
   topological level = one clock cycle where possible:
   - Combinational-only levels: `assign` statements chained.
   - Multi-cycle boundaries: insert `always_ff` register between
     the levels — `pipe_reg_N <= pipe_reg_N_1;`.

7. **Emit `always_ff` blocks for state**:
   - Iteration counters for opaque recursion.
   - Pipeline stage registers between clock-cycle boundaries.
   - Any Step 12 parallel candidate group synchronization
     (barrier registers at group boundaries).

8. **Emit CDC synchronizers** where the DAG crosses a clock-domain
   boundary. Two-flop synchronizer for single-bit signals; async
   FIFO for multi-bit buses. Boundary is any edge from a pure-region
   node to an `@effect` extern node whose peripheral runs on its
   own clock.

9. **Emit a testbench stub** — a `<module_name>_tb.sv` file with
   the module instantiated + clock generator + reset sequence.
   Not for shipping, but for local Verilator / iverilog runs
   during development.

10. **Verify total resource usage against Step 18's estimate**. If
    Step 18 said the design won't fit, abort with a diagnostic
    pointing at the highest-cost sub-graphs.

### Example emission

Given source:
```
public func step(x: u32, y: u32): u32
  a = u32.add(x, y)
  b = u32.add(a, x)
  b
```

With Step 7 narrowing `x, y ∈ [0..999]` → u10 each:

```systemverilog
module step (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [9:0]  x,       // narrowed from u32 → u10 (Step 14)
    input  logic [9:0]  y,
    output logic [10:0] result   // narrowed: max value 2999 → 11 bits
);
    logic [10:0] a;              // x + y max = 1998 → 11 bits
    logic [11:0] b_full;         // a + x max = 2997 → 12 bits
    // Combinational pure ops (Step 16 scheduled to single cycle).
    assign a      = x + y;
    assign b_full = a + x;
    assign result = b_full[10:0];
endmodule
```

No pipeline registers because Step 16 fit both adds within one
clock. Wider bus would need multi-cycle pipelining; `always_ff` gets
inserted then.

### Clock domain considerations

- **Pure regions** run in a single clock domain (the fabric clock).
- **`@effect` externs** may cross clock domains (I/O peripherals have
  their own clocks). Emit CDC synchronizers per step 8 above.
- **Multi-clock optimization** — running different pipeline stages
  at different clock rates — deferred until a real target demands
  it.

### Why bypass HLS

- **Analyses replace HLS's pass**. Steps 7 / 12 / 13 / 14 / 15 / 16
  already compute what HLS's scheduler would. Handing the same info
  to HLS as pragmas and letting it re-derive the schedule is a
  wasted pass.
- **HLS injects overhead we don't need**. Vendor HLS tools add
  bookkeeping (control FIFOs, generic AXI wrappers, dataflow FSMs)
  that assume a wider input than we produce. Our DAG-derived
  SystemVerilog is tighter by construction.
- **Vendor lock-in**. Vitis HLS and Intel oneAPI produce different
  output; our SystemVerilog is portable across every mainstream
  synthesis flow.
- **Toolchain reach**. Open-source flows (Yosys + nextpnr + Verilator
  simulation) work with SystemVerilog; most HLS tools require the
  proprietary vendor stack.

---

## What's deferred (not in the core 1-6, Level 1 CPU pipeline Steps 7-17, Level 2 FPGA pipeline Steps 18-19)

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
- **Multi-clock-domain SystemVerilog codegen**. Step 19's initial
  emitter targets a single fabric clock. Real designs may benefit
  from running different pipeline stages at different clocks (e.g.,
  I/O slower than compute). Requires more CDC synchronizers and
  scheduling under multiple clock constraints. Deferred until
  Level 2 is delivering on a single-clock target.
- **VHDL emission**. Step 19 emits SystemVerilog. VHDL is a viable
  alternative (some fabs / vendors prefer it); the analyses are the
  same, only the syntactic emission changes. Deferred unless a real
  user constraint requires VHDL.
- **Post-route timing feedback**. FPGA place-and-route may exceed
  the design's target clock frequency. Feeding that back into the
  compiler (retry with different scheduling, tighter pipelining,
  or narrower widths) would close the loop. Non-trivial — requires
  parsing vendor-tool output and re-running the affected passes.
  Deferred to real user need.

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
13a. Extension: pure kernel extraction (Step 20). Cuts the flat DAG
    at `@effect` boundaries; each connected pure sub-DAG becomes a
    standalone kernel with a fixed scratch buffer, fixed WCET, and
    fixed signature. Reshapes the whole program into "event loop +
    kernels + dispatch table" — the shape both CPU and FPGA
    codegen consume. Steps 14-16 now operate per-kernel.
14. Extension: bit-width narrowing (Step 14). Consumes Step 7's value
    domains; decorates each node with narrowest storage width.
15. Extension: data layout optimization (Step 15). Access-pattern
    analysis picks AoS vs SoA per struct; hot/cold separation;
    cache-line alignment.
16. Extension: instruction scheduling + register allocation (Step 16).
    DAG-aware live ranges, register coloring, SIMD grouping, loop
    scheduling.
17. **Level 1 target: CPU codegen (Step 17)**. Emits optimized C
    using Steps 14-16 plus all prior analyses. First target — proves
    the analysis foundation, ships to actual users on standard
    hardware.
18. Level 2 target: FPGA resource estimation (Step 18). Companion
    to WCET but measures LUT / BRAM / DSP area.
19. Level 2 target: SystemVerilog emitter (Step 19). Direct
    synthesizable SystemVerilog — bypasses HLS entirely because
    Steps 7 / 12 / 13 / 14 / 15 / 16 already compute the
    scheduling / bit-width / layout info HLS would derive.
    IEEE 1800 dialect for `logic` / `always_ff` / `always_comb`
    clarity; portable across Vivado / Quartus / Yosys /
    Verilator.

Core steps 3-6 can ship independently, each adding capability without
breaking the prior stage. Extensions (Steps 7-19) run atop the core
DAG and each can ship in phases as described above. **CPU (Level 1)
is the first shipping target — Steps 14-17 are on the critical path.
Level 2 (Steps 18-19, FPGA) is scoped and roadmapped but not
prioritized until Level 1 proves the analyses in production.**

The pipeline order at codegen time:

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
Extension 20:    Pure kernel extraction (cut DAG at @effect
                 boundaries; each pure sub-DAG becomes a kernel
                 with fixed scratch + fixed WCET + fixed I/O
                 signature; dispatch table maps effects to kernels)
Extension 14:    Bit-width narrowing (per kernel; consumes Step 7
                 domains)
Extension 15:    Data layout optimization (per kernel; AoS/SoA,
                 hot/cold split)
Extension 16:    Instruction scheduling + register allocation
                 (per kernel; uses live ranges from Steps 3+5,
                 SIMD grouping from Step 12, latency data from
                 Step 13)
Level 1 target:
Step 17:         CPU C codegen (target-first shipping backend)
Extension 9:     Frama-C spec emission alongside codegen output
                 (includes WCET as @ensures ExecutionTime clauses)

Level 2 target (future):
Extension 18:    FPGA resource estimation (LUT/BRAM/DSP area)
Step 19:         SystemVerilog emitter (direct RTL, bypasses HLS;
                 IEEE 1800 dialect for portability across major
                 open-source and vendor toolchains)
```
