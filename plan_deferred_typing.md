# Idea — Deferred typing for bare literals (and beyond)

**Status (2026-07-14)**: parked, exploratory. The immediate motivation
(uplifting would lift literals and break Approach C) turned out to be a
non-issue in practice — the ANF expansion that shipped in `body.nim`
deliberately does NOT lift `ekLiteral` at any value position (see
`validations.md §4.10`, "Interaction with Approach C"), so bare
literals still reach `analyzeBareLiteral` with their expected context
intact. This idea is still worth having on record for the next time an
ergonomic gap in eager literal typing surfaces (e.g., `x = 10; foo(x)`
where `foo` takes `u8`), but it's no longer blocking any downstream
work.

Revisit when the analyzer's scope/variable-analysis pass is due for a
rework, or when user code accumulates cases where the `x = u8 10`
explicit-prefix pattern feels awkward often enough to justify a
bidirectional inference pass.

## Motivation

Approach C (`validations.md §8.3a`) types bare literals eagerly:

```
x = 10        # analyzed with expected=none → x defaults to i32
foo(x)        # if foo takes u8, this mismatches — user must write `x = u8 10`
```

Approach C's `analyzeBareLiteral` handles the concrete-adopt case only
when the bare literal is *directly* in a typed position. Once a literal
is bound to a variable, its type is pinned at binding time and no
downstream context can change it.

(The ANF-expansion sequencing concern that originally motivated this
idea — "uplifting would lift literals into temp assignments and break
Approach C" — has been sidestepped by not lifting literals during
expansion. See `validations.md §4.10` for the invariant.)

**Deferred typing**: don't type `x` at `x = 10`. Type it *at each use
site* using the use site's expected context. Same three-branch rule
`analyzeBareLiteral` already runs — just triggered lazily instead of
eagerly. Polymorphic numeric literals in the Haskell/OCaml sense.

## Core design — `ScopeEntry` variant

Today: `AnalyzedFunctionScope = Table[Identifier, AnalyzedArgumentType]`.

Under deferred typing:

```nim
type
  ScopeEntryKind = enum
    sekTyped, sekDeferredLiteral
  ScopeEntry = ref object
    case kind: ScopeEntryKind
    of sekTyped: argType: AnalyzedArgumentType
    of sekDeferredLiteral: literal: Literal   # untyped until used

AnalyzedFunctionScope = Table[Identifier, ScopeEntry]
```

**At assignment `x = <expr>`:**
- If `<expr>` is a bare literal → `scope[x] = ScopeEntry(sekDeferredLiteral, literal)`.
- Otherwise → `scope[x] = ScopeEntry(sekTyped, argType)` (today's behavior).

**At use `x` in `analyzeVariable`:**
- Load `scope[x]`.
- If `sekTyped` → use as today.
- If `sekDeferredLiteral` → re-run `analyzeBareLiteral(literal, expected)`
  where `expected` is the use site's context. Same three-branch dispatch
  (concrete adopt / generic default / no-context default). Returns an
  `AnalyzedLiteralInitializer`.

`analyzeExpression`'s `rekVariable` arm needs the `expected` parameter
that's already being threaded post-Approach C — it currently just doesn't
consume it. That plumbing is already there.

**At end of function scope:** any `sekDeferredLiteral` never used with an
expected context falls back to the default (i32/f32/String), matching
Approach C's `expected = none` branch. Guarantees every variable is
typed by the time codegen sees it.

## Design decisions to resolve

### D1 — Pinning behavior across multiple uses

`x = 10; foo_u8(x); bar_u32(x)` — how does x behave?

- **Independent per use** (Haskell model): each use monomorphizes
  separately. `x` embeds as u8 in the foo call, u32 in the bar call.
  Two constants in codegen from one source var. Most flexible; matches
  polymorphic-numeric-literal precedent.
- **Pinned at first use**: first use sets `x`'s type in scope (rewrite
  `sekDeferredLiteral` → `sekTyped`); later uses check against it.
  Simpler mental model; first-use position matters (fragile if you
  reorder code).
- **Error on conflict**: pin at first use, error if later use disagrees
  in a way that can't be trivially resolved.

Independent-per-use is the most powerful; pinned-at-first-use is the
easiest to explain.

### D2 — Case-block scope clones

`analyzeCaseBlock` calls `scope.clone()` to create a case-local scope.
If `x` is deferred in the outer scope and case 0 uses it as u8 while
case 1 uses it as u32:

- Under **independent per use**: no interaction — each case body's
  reference to x resolves independently. Outer scope's `x` untouched.
- Under **pinned at first use**: the pin needs to happen in the CLONE,
  not the outer scope, or else case-declaration ordering leaks. Every
  case walks a *copy* of the outer scope entry, so pins stay local.

### D3 — Deferred literal used at a generic arg position

`x = 10; f[T](x)` where T is generic. `analyzeArgumentList` passes
`expected = some(generic T)`. Re-analyzing the deferred literal defaults
to i32, binds T=i32 for the call. Falls out of the existing rule.

### D4 — Deferred literal as match subject

`match x: case 0: ... case 1: ...` — the match subject needs a concrete
type to drive case-pattern typing and impl-map for case-block scope.

- Add a "match on deferred literal" path that infers the subject type
  from case patterns (each `case <IntLit>:` implies integer kind →
  default to i32; each `case <Variable>:` binds the variable to the
  subject's type).
- OR require the user to write `x = i32 10` explicitly when the value
  will be matched — rejecting deferred-subject match altogether.

The second is much simpler and avoids a bidirectional-inference pass
just for one case.

### D5 — When does the deferred-literal state materialize?

Two integration points:
- **Lazy**: only materialize on first read. Fine if uses are frequent.
- **Eager at scope exit**: at the end of every scope block, materialize
  any un-used deferred entries via the default fallback. Guarantees a
  bounded phase for finalization.

Eager at scope exit is easier to reason about — no "surprise typing"
after the fact.

## What this would unblock

Historically-cited: the **Q9 concern in `plan_try_operator.md`** — that
lifting literals into synthetic assignments would break Approach C.
That concern is now moot because the ANF expansion that shipped does
NOT lift literals (see `validations.md §4.10`), so no scope-entry
rework was needed to keep Approach C working.

What deferred typing would still buy, if picked up later:

- **Ergonomic improvement for hand-written code**. `x = 10; foo(x)`
  where `foo(a: u8)` would work — today users must write `x = u8 10`.
- **Would enable literal-lifting on the ANF path** if we ever wanted a
  stricter invariant (value positions are strictly `Variable`, not
  `Variable` OR `Literal`).
- **Would generalize the polymorphic-literal mental model** — a
  precedent for the anonymous-struct extension described below.

## Cost

- New `ScopeEntry` variant (or `Option`-wrapping argType at variable-use
  time). Every scope-consumer becomes aware.
- `analyzeVariable` needs the `expected` parameter threaded (currently
  doesn't consume it, though the plumbing is present).
- Case-block clone semantics need to be clarified for D2's pinning
  behavior.
- Match-subject case (D4) needs a decision — either infer or reject.
- Testing: 6-8 new tests to cover deferred behavior across all use
  positions.

Rough scope: 4-6 commits in the same shape as Approach C's landing.

---

## Extension — Anonymous struct/union initializers

Same principle, bigger scale. `x = { a: 10, b: 20 }` (no module prefix)
binds x as a *deferred struct value* with fields `a=10, b=20`. At each
use with a struct-typed expected context, resolve the shape against the
target struct (name-matched fields, compatible types) and monomorphize.

Two aspects parallel the bare-literal case:

- **Scope entry**: `sekDeferredStruct` holding the kwarg list.
- **At use**: shape-check against expected → adopt if compatible.

Key differences from bare literals:

- **No default fallback.** There's no "canonical struct shape" to fall
  back to when no use context is available. Anonymous struct with no
  use → error, whereas bare literal with no use → i32 default.
- **Shape-match rule.** Anonymous `{ a: 10, b: 20 }` matches nominal
  `Pair { a: u8, b: u8 }` if field names match exactly and each field
  value can be adopted for its declared type.
- **Nested composition works recursively**: `{ point: { x: 10, y: 20 }, color: 5 }`
  → outer resolves against Box; inner recursively against Point.

### Anonymous unions

Harder because unions have variants. `x = Ok { value: 10 }` — which
union does Ok belong to? Resolvable only at use, when the expected type
is a nominal union with an Ok variant. Narrower than structs (only one
variant per anonymous value), but same mechanic.

### Design tension — nominal vs structural

ASL is nominal today: `Point { x: u32, y: u32 }` and `Vector { x: u32, y: u32 }`
are distinct types despite identical shape. Anonymous structs introduce
structural typing in the initializer position, which could erode the
Point-vs-Vector distinction.

Two variants:

- **Conservative**: require the anonymous shape to have *exactly one*
  candidate nominal struct in scope. Ambiguity errors. Prevents
  accidental duck typing.
- **Permissive**: any shape-compatible nominal type works. Encourages
  the pattern but blurs nominal distinctions.

Conservative is the safer default. Permissive is the "more powerful"
option; hard to walk back once shipped.

### Why to defer this even after deferred bare literals ship

Anonymous structs are a bigger step: they need shape-matching, multi-
candidate ambiguity handling, and a language-design decision about
duck typing. Bare literals are a small polymorphism; anonymous structs
are a full structural-typing feature.

Sequencing: ship deferred bare literals first (validate the mental
model), then anonymous structs as a well-precedented extension. That
way the deferred-entry infrastructure is proven before scaling up to
shape-matching.

---

## When to revisit

- When user code accumulates cases where bare-literal-in-assignment
  ergonomics feel awkward (`x = u8 10` pattern showing up frequently).
- When the analyzer's scope/variable-analysis pass is being reworked
  for another reason — deferred typing rides along cheaply.
- When there's appetite to tighten the ANF value-position invariant
  from "`Variable` OR `Literal`" to strictly `Variable` (would require
  literal lifting to work without breaking Approach C — deferred
  typing enables that).

Until then, Approach C is sufficient for the current test suite and
example fixtures.
