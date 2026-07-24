# Alias-lookup cleanup — migrate remaining name-keyed sites to identity-based

## Status (as of 2026-07-25) — COMPLETE

All work items landed on `main-recovery`:
- W0 (3602e42) — plan.
- W1 (fb1d4b9) — analyzeUnionRef + analyzeStructRef migrated to
  `app.findModule`; factored the canonical
  `findModule(app, parser.Module, loc)` helper on the facade;
  `findArgTypeModule` collapses to a one-liner delegation.
- W2 (e7c22d7) — analyzeGenericArgumentType fallback migrated to
  `app.findType(newType(genericArgType.parsed))`.
- W3 (ce67a92) — deleted the dead `findModuleDef(fileScope, ...)`
  helper; inlined the case-on-kind unpack at the literal-default
  site. Surviving `findType(fileScope, ...)` docstringed to make
  its legit initial-name-lookup role explicit.
- W4 (90cdd7e) — deleted the `AnalyzedDefinedTypeScope` type alias
  + its three unused helpers on `definedtype.nim`; inlined the
  field type on `AnalyzedFileDefinition`; dropped the unused
  `definedTypeIndex*` accessor. filedef.nim doc rewritten to
  describe the actual per-file-name-only role.
- W5 (2a0cceb) — refreshed the stale doc on `appdef.nim` to
  describe the actual two-index design.

The scrutiny that motivated this plan is fully resolved: every
post-resolution module/generic lookup now goes through the
app-level identity-keyed indices; name-keyed lookups are confined
to legitimate initial-name-lookup paths (fncall roots, default
literal type names) where the user typed a name and the compiler
resolves it against import bindings + local declarations.

## Context

`plan_identity_based_lookups.md` fixed the primary alias-lookup bug in
`findArgTypeModule` by routing through `app.findType(parser.Type)`.
Scrutinizing the rest of resolver + analyzer surfaced four more sites
that use the same name-keyed pattern the identity plan set out to
kill, plus adjacent dead code and stale docs that grew around the
half-migrated state.

All of the remaining name-based sites look up a module or generic by
its `.name` (from the resolver-side type — which reports the underlying
parser name, not the import binding). Every `import { Foo as Bar }`
that touches these paths silently fails, because the scope keys are
the bindings. Dormant in tests because no fixture exercises aliased
imports through these code paths — structural, not observed.

## Findings (from the scrutiny report)

### High — latent alias bugs (3 call sites, 1 dead helper)

**A. `analyzer.nim:195-212 analyzeGenericArgumentType` (module-context overload)**
```nim
elif genericArgType.parsed.name in fileScope:      # ← name-keyed miss on alias
  let typ = fileScope[genericArgType.parsed.name]
```
Fix: `app.findType(newType(genericArgType.parsed))` — direct identity.

**B. Three sites doing `fileScope.findModuleDef(<argType>.module.name, loc)`**
- `analyzer.nim:828` in `analyzeUnionRef` — `unionRef.module.name`.
- `analyzer.nim:916` in `analyzeStructRef` — `structRef.module.name`.
- `analyzer.nim:984` in literal-init path — `ident` (module name literal).

Fix: `app.findType(newType(<argType>.module))` for :828 and :916.
`:984` is different — the `ident` comes from a literal expression;
that's a legit initial name lookup (user typed `SomeName(...)`).
Actually it's still vulnerable: if the user writes `Byte(3)` where
`Byte` is `import { u8 as Byte }`, the literal takes the binding
`"Byte"`. That IS in fileScope (bound to u8). But what if they write
`u8(3)` when `u8` is only visible as `Byte`? That should fail (user
typed a name that's not in scope) — the current behavior is correct.
So :984 stays name-keyed as a legit initial lookup. Only :828 and :916
need migration.

**C. Dead helper: `AnalyzedDefinedTypeScope.findModuleDef(argType, loc)`**
at `analyzer/definedtype.nim:69-85`. No external callers, but ships
the same bug pattern if wired later. Delete.

### Medium — dead code + duplicate lookup surface

- `analyzer.nim:131 findType(fileScope, ...)` — after A/B migrate,
  only the literal-name path at :984 needs it. Keep as
  `findType(fileScope, ...)`; consider inlining.
- `analyzer.nim:137 findModuleDef(fileScope, ...)` — all 3 remaining
  callers are in bucket B. Once they migrate, delete.
- `analyzer/definedtype.nim:56 findType(defScope, ...)`,
  `:62 findModuleDef(defScope, name, loc)`,
  `:69 findModuleDef(defScope, argType, loc)` — no external
  callers. Delete all three plus the `AnalyzedDefinedTypeScope` type
  alias if nothing else consumes it.

### Medium — stale docs

- `analyzer/filedef.nim:6-9` and `analyzer/appdef.nim:4-5` both claim
  phase B "augments defScope with cross-file imports at analyzeFile
  time." No such augmentation exists — every phase-B lookup routes
  through `appDef.findDefinedType` (app-level). Rewrite the comments
  to describe what actually happens.

### Low — signature bloat (deferred, not this plan)

`fileScope` threads through 20+ analyze* signatures. Once bucket A/B
migrate, its only consumer is the literal-default lookup path. Could
be dropped from most signatures. Deferring — the ripple is wide and
the plan should stay focused on the alias bugs.

## Work items

Each ships as its own commit; all three gates green (nimble test /
./test.sh / `asl build examples/sample.asl [SUCCESS]`) at every step.
Same cadence as prior plans — one W per "go ahead".

### W0 — Plan doc

Commit this file.

### W1 — Migrate `analyzeUnionRef` + `analyzeStructRef` to `app.findType`

Two mechanical sites (`analyzer.nim:828`, `:916`). Replace
`fileScope.findModuleDef(<argType>.module.name, loc)` with the
identity lookup:

```nim
let maybe = app.findType(newType(<argType>.module))
if maybe.isNone:
  return err(fmt"{<argType>.loc} module `{<argType>.module.name.asl}` is neither defined nor imported")
let entry = maybe.get
if entry.kind != rdtkModule:
  return err(fmt"{<argType>.loc} UNREACHABLE: expected module but got generic")
let resolvedModule = entry.module
```

Or factor a tiny helper on the facade — `findModuleByIdentity(app, parser.Module)` — if the same 5-line shape shows up elsewhere. Judge at write time.

### W2 — Migrate `analyzeGenericArgumentType` fallback to identity

`analyzer.nim:195-212`. Replace the `fileScope[parsed.name]` lookup
with `app.findType(newType(genericArgType.parsed))`. Preserve the
"generic first via `file.findGeneric`, then app-wide via identity"
ordering — the local-file path errors get better error messages
(scope context), so it stays as the first check.

### W3 — Delete dead `findModuleDef(fileScope, ...)` on the facade

Now that W1 removed the last name-keyed callers, delete
`analyzer.nim:137 findModuleDef(fileScope, name, loc)`. The
`findType(fileScope, ...)` at :131 stays — still used by the literal
path at :984 (legit initial name lookup).

### W4 — Delete dead `AnalyzedDefinedTypeScope` helpers

`analyzer/definedtype.nim:56-85`: delete `findType`,
`findModuleDef(name, loc)`, `findModuleDef(argType, loc)`. The type
alias itself stays if `AnalyzedFileDefinition.definedTypeIndex` still
uses it (it does — filedef.nim:23). If nothing else references the
alias after the helpers go, consider inlining the `Table[Identifier,
AnalyzedDefinedType]` type at the field.

### W5 — Refresh stale docs on `filedef.nim` + `appdef.nim`

Rewrite the leading doc comments to describe the actual design:
per-file `AnalyzedFileDefinition` holds a name-keyed
`definedTypeIndex` for the local `findDefinedType(name)` path;
cross-file / identity-based lookups go through
`AnalyzedAppDefinition.findDefinedType(ResolvedType)`. No
augmentation ever happens.

### W6 — Mark plan complete

Prepend a Status block to this doc summarizing W0-W5 landings.

## Non-goals

- Do NOT drop `fileScope` from analyze* signatures. Deferred to a
  future plan — the ripple is wide and this plan stays focused on
  the alias bugs.
- Do NOT rename `ResolvedFileScope` → `ResolvedNameScope`. Same
  rationale — separate concern.
- Do NOT touch the literal-init name lookup at analyzer.nim:984. Legit
  initial name lookup ("user typed `Foo(3)`").
- Do NOT touch resolver-side FileScope. Legit name→parser bridge.

## Cost estimate

- W0: 15 min (plan commit).
- W1: 30 min (two mechanical sites + verification).
- W2: 15 min.
- W3: 10 min (safe delete after W1).
- W4: 10 min (safe delete — dead code already).
- W5: 15 min (comments only).
- W6: 5 min.

**Realistic total**: 1.5–2 hours across one session.

## Blocking preconditions

- `plan_identity_based_lookups.md` complete — done (commit `c85fd69`).
- Working tree clean at plan start.
