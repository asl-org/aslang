# Plan — Expression Uplifting + `try` Operator

**Status (2026-07-14)**: Part A (expression uplifting / A-normal form
expansion) has **landed**. See `overview.md` Phase 2 → "Post-parse
A-normal form expansion" and `validations.md §4.10` for what shipped.
The implementation differs from the sketch in this file — notably:
- Literals stay unlifted (preserves Approach C's concrete-adopt for
  bare literals). Value positions accept `Variable` OR `Literal`.
- Bare-expression statements are explicitly wrapped in an assignment
  (`__asl_arg_N = <expr>`) so every top-level statement is an
  Assignment or Setter — one uniform ANF shape.
- No predicate parameter — the rewrite rules are baked in.

Part B (the `try` operator) is now unblocked. This file's Part B and
the open questions Q1/Q2 still apply. Part A's design section below
is preserved as historical context but is superseded by the
implementation.

---

Original framing:

Two features, one dependency chain. Expression uplifting is a general
AST-normalization pass that rewrites the source AST into A-normal form:
every value-position expression (function-call arg, initializer kwarg
value, setter RHS) is a bare `Variable`. Any non-`Variable` expression
in those positions is lifted into a preceding synthesized assignment.

`try` (Part B) is one of several downstream features that assume this
shape. It's part of the motivation, but uplifting stands on its own —
it simplifies the analyzer's value-flow reasoning across the board
(every arg has a name; every temporary is bound; every intermediate
value has a scope).

Both features live entirely in the parser layer. Downstream (resolver,
analyzer) sees the normalized AST as if the user had hand-written every
intermediate value.

---

## Open questions (resolve before implementation)

### Q1 — Strict vs structural Status typing *(try-specific)*

`try u8.subtract(x, 1)` inside `func fib(x: u8): Status[u32]`:

- **Strict**: reject. All `try`d expressions must return `Status[R]` where
  R matches the enclosing function's declared return-type inner. Users
  must explicitly convert (`try u32.from(u8.subtract(x, 1))` or similar)
  when the inners don't match.
- **Structural**: accept. Since Status's `Err { error: u8 }` is uniform
  across `Status[T]` for any T, the Err payload is structurally
  compatible. Requires a type-system carve-out: `Status[T].Err` is
  assignable to `Status[U].Err` for any T, U.

Blocking Part B implementation. Doesn't affect uplifting.

### Q2 — Bare-statement `try foo()` policy *(try-specific)*

Under the uniform-uplifting rule (see Part A), bare-statement `try foo()`
uplifts to `__asl_arg_N = try foo()` where the binding is unused. Two
readings:

- Legal always — synthesized binding is an implementation detail.
- Rejected — bare `try` on a non-`_` receiver is an anti-pattern
  because the Ok value is silently discarded (contradicts the
  "no unused function outputs" stance).

Current inclination: legal always via uniform uplifting.

### Q3 — Naming of synthesized identifiers *(shared)*

`__asl_arg_N` uses the compiler-reserved namespace that
`newIdentifier` already rejects, so user collision is impossible by
construction. Requires adding a `newSyntheticIdentifier` proc that
bypasses the check for compiler-internal use.

**Settled**: one shared per-function counter, naming scheme
`__asl_arg_N`. Uplifting and (later) try both draw from the same
counter.

### Q4 — AST modification approach *(uplifting-specific)*

The uplifter replaces a nested subexpression with a `Variable(temp)`
reference. Since AST types are `ref object` with private fields and no
setters, the modification has to happen either by:

- **Reconstruct**: return new AST nodes with modified subtrees. Cascades
  up through parents — reconstruct FunctionCall to swap an arg,
  reconstruct KeywordArgumentList to swap a kwarg's expression,
  reconstruct KeywordArgument to swap its expression, etc. Preserves
  the "constructors own state" invariant strictly. Requires adding
  helper builders (`FunctionCall.withArgs(newArgs)`, etc.) — several
  files worth of boilerplate. Zero mutation.
- **Mutate**: add compiler-internal setters on the same-file cluster
  (e.g., `unsafeSetArgs` inside `body.nim`, only used by `uplift.nim`).
  Breaks strict immutability but keeps the mutation surface minimal
  and named to signal intent. Roughly 5-8 setters total.

Blocking Part A implementation. Recommendation: mutate, since the AST
cluster is large and reconstruction adds significant surface area with
no runtime benefit. Setters should live in the same file as the AST
type (so they can touch private fields directly) and be named with an
`unsafe`/`internal` prefix so it's obvious they're compiler-internal.

### Q5 — Predicate signature *(uplifting-specific — obsolete)*

Was: should the uplifter be predicate-driven?

**Settled (revised)**: no predicate. Uplifting-to-ANF is a language-
wide invariant, not a per-consumer choice. The uplifter bakes in
"lift complex expressions at value positions." If future macros need
different lift criteria, we'll add a predicate at that point.

### Q6 — Uplift match subjects? *(uplifting-specific)*

`match Module.function(x): case ...` — is the subject `Module.function(x)`
a value position that gets uplifted to
`__asl_arg_0 = Module.function(x); match __asl_arg_0: case ...`?

Arguments for:
- Uniformity: every value position gets uplifted.
- Simplifies the analyzer's match-subject handling.

Arguments against:
- Match subjects are already the "primary expression" of a match
  statement; lifting adds a trivial rename that maybe adds noise.
- ANF isn't strictly a language-wide invariant if match subjects are
  exempt.

Current inclination: uplift, for consistency.

### Q7 — Setter RHS as value position *(uplifting-specific)*

The user's original example listed "mutation" (setter) as a site
where uplifting applies:

```
x.field = Module.function(...)   # complex RHS
# becomes
__asl_arg_0 = Module.function(...)
x.field = __asl_arg_0
```

Confirming: setter RHS is a value position (unlike assignment RHS,
which is top-level and stays as-is). The asymmetry:

- `x = foo()` — `foo()` is the assignment RHS, no lift needed. `x`
  is bound to the FunctionCall's result directly.
- `x.field = foo()` — `foo()` is the setter RHS, gets lifted.

Confirming (yes/no) — the design intent seems to be that setters
are "value consumers" like function args, so they get the value-
position treatment.

### Q8 — Literals as value-position expressions *(uplifting-specific)*

**Settled**: literals ARE lifted. `foo(10, 20)` → `t0 = 10; t1 = 20;
foo(t0, t1)`. Full ANF, no exceptions.

This requires an analyzer enhancement to preserve Approach C's
concrete-adopt behavior — see **Q9** below.

### Q9 — Analyzer support for typed uplifted literals *(analyzer-side)*

Once literals are lifted (Q8), the naive analyzer flow breaks:

```
t0 = 10           # analyzed with expected=none → t0 defaults to i32
foo(t0)           # foo(a: u8): expected u8, but t0 is i32 → TYPE ERROR
```

To preserve `foo(10)`-with-`foo(a: u8)` working, the analyzer needs
to type compiler-generated temps based on their USE, not their
default:

- When analyzing a function call, kwarg value, or setter RHS, if the
  arg is a `Variable` bound to a compiler-generated temp
  (`__asl_arg_N`), and the temp's assignment RHS is a bare literal,
  re-analyze the temp's assignment with the use-site's expected type.
- Equivalently: propagate expected type BACKWARD from the use site to
  the compiler-generated temp's definition.

This is a form of local bidirectional inference for uplifted temps.
Scoped tightly to compiler-generated variables (identified by the
`__asl_arg_` prefix). User-written variables are unaffected — they
type at their definition site as today.

**Implementation options**:

- **A. Look-ahead during assignment analysis.** When analyzing a
  `__asl_arg_N` assignment, scan the current statement list for the
  next use of that variable, determine its expected type from context,
  and pass that expected to `analyzeExpression` for the RHS.

- **B. Deferred typing of temps.** Don't type `__asl_arg_N`
  assignments immediately. Instead, when analyzing their use site,
  look up the temp's assignment, analyze with correct expected, and
  cache the resulting type in scope.

- **C. Two-pass analysis.** First pass: identify all temp uses and
  their expected types. Second pass: type-check with that info.

A is simplest but couples definition-analysis to use-scanning.
B is cleanest but changes the linear-walk model.
C is uniform but doubles the analyzer's work.

Recommendation: **A** (look-ahead). Since each temp is used exactly
once in the immediate statement stream (that's how uplifting produces
them), the look-ahead is O(1) — just check if the next statement's
expression tree contains a use.

Blocking Part A implementation. Uplifting can't ship without this
analyzer enhancement, or Approach C's concrete-adopt breaks.

---

## Part A — Expression Uplifting

### Motivation

The analyzer's job — resolving argument types, matching function
signatures, checking initializer field types — is much simpler when
every "value-position" expression is already a named binding. Instead
of:

```
x = Module.function(foo(y), bar(z), var1, var2)
```

the parser rewrites to A-normal form:

```
__asl_arg_0 = foo(y)
__asl_arg_1 = bar(z)
x = Module.function(__asl_arg_0, __asl_arg_1, var1, var2)
```

Every function-call argument is now a bare `Variable`. Same rewrite
applies to initializer kwarg values (`Struct { field: expr }`), setter
RHS (`x.field = expr`), and every other value position that expects a
runtime value.

The user still writes the compact form. The parser normalizes it. The
resolver / analyzer sees the ANF-shaped AST.

### Value positions (where uplifting applies)

An expression is at a **value position** if it's a runtime value being
consumed by an enclosing construct:

- **Function-call argument** — each `ArgumentList` entry.
- **Initializer kwarg value** — each `KeywordArgument`'s expression
  (both struct and union initializers).
- **Setter RHS** — the setter's expression.
- **Match subject** — the expression being matched. *(Open question —
  see Q6.)*

An expression at a value position must be a `Variable` after
uplifting. Anything else — `FunctionCall`, `Getter`, `Initializer`,
`MatchExpression`, `Literal` (per Q8 settlement), later `Try` — is a
**complex expression** that gets lifted.

### Positions where uplifting does NOT apply

The following are **statement-level positions**, not value positions.
Complex expressions here stay as-is:

- **Assignment RHS** (`x = <expr>`). `<expr>` can be arbitrarily
  complex; the assignment binds the result to `x`.
- **Setter RHS** — wait, this IS a value position (see above). *Note
  the split*: assignment RHS is fine, setter RHS is lifted. Confirming
  the intent — the user's example listed "mutation" (setter) as a
  place uplifting applies, so setter RHS is normalized like function
  args. Confirming below (Q7).
- **Bare-expression statement** (`<expr>` alone as a statement).
  Whatever value it produces is either the function's return (if
  tail) or discarded.
- **Assignment target** — an Identifier, not an Expression.
- **Setter LHS** — a Getter with an Identifier source; nothing to
  lift.
- **Getter source** — an Identifier by grammar.

### Design

**Post-parse pass.** Runs immediately after each function body is
parsed, before the file's constructor validates and hands off to the
resolver.

**Bottom-up post-order walk.** For each statement, walk the expression
tree post-order. Innermost complex expressions lift first; outer
expressions then reference the freshly-lifted temp bindings.

**Left-to-right evaluation order.** Sibling value-position expressions
lift in source order, preserving the language's eager left-to-right
semantics. `foo(a(), b())` lifts to `t0 = a(); t1 = b(); foo(t0, t1)`.

**Scope-local.** Uplifting operates on a single statement list at a
time. Synthesized assignments are inserted into the same list, never
crossing scope boundaries. When the walker descends into a nested
case-block body, it recurses on that scope's own statement list.

**Fresh identifiers.** A per-function counter (see Q3) provides
unique names: `__asl_arg_0`, `__asl_arg_1`, .... The `__asl` prefix
is compiler-reserved (`newIdentifier` rejects it), so no collision
with user code is possible by construction.

**Idempotence.** A `Variable` at a value position never lifts. Users
can write hand-optimized ANF-shaped code, and it passes through
unchanged.

### AST modification approach — Q4 open

Same as before — mutate via compiler-internal setters (recommended)
vs reconstruct. See Q4.

### API

New file `src/parser/uplift.nim`:

```nim
proc newSyntheticIdentifier*(name: string, loc: Location): Identifier
  # Bypasses newIdentifier's __asl-prefix rejection. Compiler-internal.

type UpliftCounter* = ref object
  count: int
proc newUpliftCounter*(): UpliftCounter
proc nextName*(c: UpliftCounter, loc: Location): Identifier
  # Returns __asl_arg_<count> and increments.

proc uplift*(statements: seq[Statement], counter: UpliftCounter): seq[Statement]
  # Main entry. Called with a fresh counter per function body.
  # No predicate — the "lift complex value-position expressions" rule
  # is baked in.
```

The rule is baked in (not predicate-driven) because uplifting-to-ANF
is a language-wide invariant, not a per-consumer choice. If future
macros need different lift criteria, we'll add predicate support at
that point — for now, YAGNI.

### Data flow

Input: `seq[Statement]` for one scope + counter.
Output: rewritten `seq[Statement]`. Guarantee: every value-position
expression in the output is a `Variable`.

Per statement, walker steps:
1. Walk the statement's top-level expression tree post-order.
2. For each subexpression `e` at a **value position** where `e` is not
   already a `Variable`:
   - `newIdent = counter.nextName(e.loc)`.
   - In `e`'s containing node, replace `e` with `Variable(newIdent)`
     via the internal setter.
   - Insert a new statement `newIdent = e` into the output list
     immediately before the current statement.
3. Recurse into any case-block bodies within the statement's
   expression tree (each is its own uplift call sharing the same
   counter).

Termination: each iteration reduces the number of non-`Variable`
value-position expressions by 1. Bounded by input complexity.

### Testing

Test suite in `tests/test_uplift.nim`. No scaffolding predicate needed
— we test the real behavior directly against real ASL sources:

- **Simple**: `foo(bar(x))` → `t0 = bar(x); foo(t0)`.
- **Nested**: `foo(bar(baz(x)))` → `t0 = baz(x); t1 = bar(t0); foo(t1)`.
- **Multiple args, left-to-right**: `foo(bar(), baz())` →
  `t0 = bar(); t1 = baz(); foo(t0, t1)`.
- **Mixed variables and complex**: `foo(a, bar(), b)` →
  `t0 = bar(); foo(a, t0, b)`.
- **No lifting**: `foo(a, b)` → unchanged (both args already
  `Variable`).
- **Assignment RHS untouched (as top-level)**: `x = foo(a, b)` →
  unchanged (top-level; args are variables).
- **Kwarg value lifted**: `Struct { f: bar() }` → `t0 = bar();
  Struct { f: t0 }`.
- **Setter RHS lifted**: `x.field = bar()` → `t0 = bar();
  x.field = t0`.
- **Match subject**: TBD depending on Q6 resolution.
- **Case block body recursion**: complex expressions inside case body
  lift within the case scope (not into the outer function body).
- **Counter monotonicity**: multiple lifts in one function get
  distinct names; counter resets at 0 for each function.
- **Literal lifting**: `foo(10, 20)` → `t0 = 10; t1 = 20; foo(t0, t1)`.
  Bare literals are complex expressions and get lifted like any
  other. Depends on Q9's analyzer enhancement to preserve concrete-
  adopt behavior downstream.
- **Mixed literals and variables**: `foo(10, x)` → `t0 = 10; foo(t0, x)`.
- **Nested with literals**: `foo(bar(10))` → `t0 = 10; t1 = bar(t0);
  foo(t1)`.

---

## Part B — `try` Operator

### Grammar

```
Expression: 'try' Expression | (existing forms)
```

`try` is a reserved word (added to the tokenizer's keyword set). It
cannot appear as an identifier. Grammar file updated.

### AST

New variant on `Expression`:

```nim
type ExpressionKind = enum
  ekVariable, ekLiteral, ekFunctionCall, ekGetter,
  ekInitializer, ekMatchExpression, ekTry   # <-- new

case kind: ExpressionKind
of ekTry: tryInner: Expression, tryLoc: Location
...
```

Constructor: `newExpression(tryInner: Expression, tryLoc: Location):
Expression`.

### Parser spec

`tryPrefixSpec = pair(keywordSpec("try"), prefixed(ws1, expressionSpec))`
producing `ekTry` at the top of `expressionSpec`'s `oneOf` (highest
priority so `try` binds before other prefix forms).

### Post-parse pipeline (per function)

Runs immediately after the function body is parsed, before any
downstream layer sees the AST.

1. **Uplift** — call the Part A uplifter with `shouldLift = isEkTry`.
   After this pass, every remaining `ekTry` in the function body is
   at a top-level statement position.
2. **Validate** — PC-1 and PC-3 (see below). Collect all violations
   and report as a single error message with all locations.
3. **Expand** — apply the transformation rules recursively over the
   function body's statement list.

After all three passes, the function body contains zero `ekTry`
nodes — only regular match expressions with fully-typed structure.

### Pre-checks

**PC-1 — Enclosing function returns Status.** The function's declared
return type must be `Status[R]` for some R (concrete or generic).
Rejection message: `` `try` requires the enclosing function to return
Status[...] but this function returns `<type>` ``.

**PC-2 — Position (implicit).** No longer needed after uplifting;
every remaining `try` is guaranteed to be at a top-level statement
position.

**PC-3 — Tail-chain reachability.** The `try`'s containing statement
must be on the function's tail-propagation chain, so the desugared
Err can flow up to the function's return via normal expression
propagation.

Definition: a statement is on the tail chain if:
- It is inside the function body statement list (top-level of the
  function).
- OR it is inside a case block whose enclosing match is a
  **bare-expression statement** (not assigned to a variable, not
  nested inside another expression) at a position on the tail chain,
  recursively.

Rejection when: a `try` appears inside a case block whose match is on
the RHS of an assignment. The Err would propagate to the match's
return value, which is bound to a variable and *discarded from the
function's control flow* — the try's Err would vanish silently.

Rejection message: `` `try` inside a case block whose match value is
captured (`{targetVar}` at `{matchLoc}`) — the error would be
silently discarded. Move the `try` out of the match or restructure
the match to be a bare expression. ``.

### Transformation rules

**Rule A — Assignment with `try` RHS.**

Given a statement list `[s1, ..., s(i-1), <target> = try <expr>,
s(i+1), ..., sn]`, rewrite to `[s1, ..., s(i-1), M]` where M is:

```
match <expr>:
  case Ok { value: <target> }:
    s(i+1)
    ...
    sn
  case error:
    error
```

Then recurse into the Ok arm's body (which is a fresh statement list
that may contain more trys or nested matches).

**Rule B — Match with `try` in any case body.**

If any case body in a match expression contains a `try` (at any depth,
which post-uplifting means at top-level statement position within
that case body), rewrite the whole match. Given
`[..., <target> = match <subj>: <cases>, s(i+1), ..., sn]`
where `<cases>` includes at least one case body containing a `try`:

1. Normalize each case body to yield `Status[FR]` uniformly (FR = the
   type inferred from the match's own uniform return type, NOT the
   enclosing function's return type — see notes below):
   - Case body whose tail is `try e` (post-uplifting, top-level): drop
     the `try`, body's tail is `e` directly (already `Status[FR]`).
   - Case body whose tail is not a `try`: append a wrap statement:
     `value = <tail>; Status.Ok { value }`, producing `Status[FR]`.
     Actually simpler: rewrite the tail expression from `<tail>` to
     `Status.Ok { value: <tail> }` in place. (Verify: the leave-as-is
     bare `Status.Ok { value: … }` should unify with the try'd cases'
     `Status[FR]` via the analyzer's existing union-initializer
     inference.)
   - Case body containing a `try` at non-tail position: Rule A already
     cascaded into this scope during a prior recursion, so the case
     body's tail is now a match expression yielding `Status[FR]`. No
     further wrapping needed.
2. Assign the rewritten match to a synthesized name:
   `__asl_arg_N = match <subj>: <normalized cases>`.
3. Append the unpack match:
   ```
   match __asl_arg_N:
     case Ok { value: <target> }:
       s(i+1)
       ...
       sn
     case error:
       error
   ```

Then recurse into the Ok arm's body.

**Rule C — Cascade for nested `try`.**

Rule A and Rule B both call themselves recursively on the Ok arm's
body. Since the Ok arm is a fresh statement list, any `try`s inside
it get expanded on the next recursion.

Termination: each rewrite reduces the number of unexpanded `try`
nodes by exactly one. Total rewrites ≤ number of `try`s in the
function body.

### Bare-statement `try` (uplifted)

Under the uniform-uplifting rule, `try foo()` as a bare-expression
statement uplifts to `__asl_arg_N = try foo()`. Then Rule A applies
with `<target> = __asl_arg_N`. The synthesized name is unused in the
continuation. Correct but produces a bound-but-unused variable in the
desugared AST — resolver/analyzer sees this as normal.

### Location reuse

Every synthesized node reuses a source location from the user's code:

| Synthesized node | Location source |
|---|---|
| Outer match expression | try keyword's loc |
| Ok case pattern | try keyword's loc |
| Ok binding identifier | Assignment target's loc (Rule A) OR try loc (bare case) |
| Err case pattern's `error` identifier | try keyword's loc |
| Err arm body's `error` reference | try keyword's loc |
| `__asl_arg_N` synthesized binding | try keyword's loc |
| Wrapping `Status.Ok { value: ... }` initializer (Rule B) | Tail expression's loc |

Every diagnostic from the desugared form points at a token the user
actually wrote. No `Location.synthetic()`, no fake source positions.

### Return-type constraint (depends on Q1)

**Under strict typing (Q1 = strict):**
- Validate: for each `try <expr>` in the function body, verify
  `<expr>`'s declared return type is `Status[R]` where R matches
  the function's declared return-type inner.
- This check happens at parser time using the try'd expression's
  syntactic form (function call → look up funcDef in scope for its
  return type). Requires the parser to have access to the file's
  scope, which it currently doesn't. Would need to defer to
  post-resolver, or expose a limited-scope lookup.

**Under structural typing (Q1 = structural):**
- No syntactic pre-check at parser time.
- Analyzer needs a special-case: when comparing `Status[T].Err`
  against `Status[U].Err`, treat as compatible.
- The desugared `case error: error` propagation "just works" — the
  Err arm returns whatever the try'd expression returned, and the
  analyzer accepts it as compatible with the function's return type.

The strict interpretation is more restrictive but doesn't require an
analyzer carve-out. The structural interpretation is more ergonomic
but adds a permanent piece of subtyping to the language.

**Currently unresolved** — plan will branch on Q1's resolution.

---

## Commit sequence (draft)

Uplifting first, then try. Each commit passes both `nimble test` and
`./test.sh` at its current baseline.

### Uplifting (Part A)

**U1** — `newSyntheticIdentifier` proc in `identifiers.nim` (bypasses
`__asl` check). Unit tests for the constructor.

**U2** — New file `uplift.nim` with the counter type and the main
`uplift(...)` proc using a predicate. Recurses into case blocks. No
callers yet.

**U3** — Unit tests for the uplifter using a synthetic predicate
(lifts function calls with a marker name). Covers the six cases in
Part A's Testing section.

### `try` operator (Part B)

**T1** — Failing tests: grammar (`try` accepted as prefix, various
positions), analyzer end-to-end (fibonacci-like example, sequential
trys, try in match case, try in nested match).

**T2** — Tokenizer reserves `try` keyword. AST: `ekTry` variant +
constructor + accessors. Parser: `tryPrefixSpec` prepended to
`expressionSpec`. AST-level grammar tests turn green; analyzer tests
still fail (no expansion yet).

**T3** — Wire the uplifter into function-body construction using
`shouldLift = isEkTry`. Verify that post-uplift, every `ekTry` in a
function body is at a top-level statement position.

**T4** — Validation pass: PC-1 + PC-3. Failing test cases (try in
non-Status function, try in captured-match case block) pass with
clear error messages.

**T5** — Expansion pass: Rule A + Rule B + cascade. Analyzer tests
turn green.

**T6** — Docs: `grammar.md` (`try` production, `Status.Ok`/`Status.Err`
sugar note), `validations.md` (new subsection on `try`), `lessons.md`
(entry on parser-layer restructuring macros).

Rough commit count: 3 for uplifting + 6 for try + 1 for docs = 10.
Grouping may reduce to 6-7 if commits combine cleanly.

---

## Implementation locus summary

| Concern | File |
|---|---|
| `try` keyword reservation | `src/tokenizer/*.nim` (wherever keywords live) |
| `ekTry` AST variant | `src/parser/statement.nim` |
| `tryPrefixSpec` | `src/parser/statement.nim` |
| `newSyntheticIdentifier` | `src/parser/identifiers.nim` |
| Uplifter | `src/parser/uplift.nim` (new) |
| Try expansion (validation + rewrite) | `src/parser/try_expand.nim` (new) |
| Wiring in function-body construction | `src/parser/statement.nim` or `function.nim` |
| Grammar doc | `grammar.md` |
| Validation doc | `validations.md` |
| Lesson entry | `lessons.md` |

---

## Out of scope (explicit deferrals)

- **General macro system.** `try` is one leaf macro among the existing
  set (`extern`, struct/union init/release/update). API extraction
  happens later, after more leaf examples inform the design.
- **`try` in match subject position.** Uplifting handles this — the
  `try` in `match try foo(): ...` lifts to `__asl_arg_N = try foo();
  match __asl_arg_N: ...`. Falls out of the general uplifter with no
  special-casing.
- **Multiple return values / early return statement.** ASLang stays
  expression-based. `try` is the only sanctioned early-return
  mechanism.
- **Cross-file try expansion.** Every function's try expansion is
  self-contained. No cross-file work.

---

## Verification

At each commit:
- `nimble build` — clean.
- `nimble test` — baseline + new tests.
- `./test.sh` — baseline preserved (currently 33/35; two pre-existing
  failures unrelated to this work).

Final: fibonacci-like example (once Q1 is resolved) compiles and
analyzes cleanly, producing the correct nested-match desugar.
