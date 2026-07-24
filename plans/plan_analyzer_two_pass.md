# Analyzer two-pass recovery — reintroduce phase A over the current DDD layout

## Status (as of 2026-07-24) — RECOVERY COMPLETE

All 12 work items W0-W11 landed on `main-recovery` branch. Two-phase
analyzer is fully recovered: phase A (definition analysis) runs first,
phase B (body analysis) consumes phase A's output directly through the
`AnalyzedAppDefinition` lookups. Every commit preserved 327/327 unit +
33/35 integration + `sample.asl [SUCCESS]`.

Landed:
- W0 (6b52bfd) — baseline snapshot + plan doc + oldanalyzer.nim as porting reference.
- W1 (b0835ea) — `AnalyzedArgumentDefinition`.
- W2 (4ef63d5) — `AnalyzedFunctionDefinition` + facade procs.
- W3 (7ae527a) — `AnalyzedLiteralBlock` / `Struct` / `Variant` / `Union` / `Data`.
- W4 (d7ae366) — `AnalyzedModuleDefinition` + `AnalyzedGeneric`.
- W5 (9fa398b) — `AnalyzedDefinedType` + `AnalyzedDefinedTypeScope`.
- W6 (8cb51da) — `AnalyzedFileDefinition` + rename `AnalyzedImportDef` → `AnalyzedImportDefinition`.
- W7 (465b47c) — `AnalyzedAppDefinition`.
- W8 (42b8994) — **Wire two-pass orchestration + fix alias-lookup bug in `findArgTypeModule`.**
- W8b (03ada2a) — **Thread appDef through 24 phase-B body walkers; `analyzeArgumentList` reads pre-analyzed args via `appDef.findFunctionDef`.**
- W8c (3687eac) — **Overload resolution end-to-end on AnalyzedFunctionDefinition: `analyzeFunctionCall` uses `appDef.findDefinedType(typ).findFunctionDefs(...)`; return type from `matchingFuncDef.returns` (no re-analysis); added `ResolvedType.hash/==` + `AnalyzedAppDefinition.definedTypeIndex`.**
- W9 (641890b) — Retire unused `fileScope` param from 4 shim overloads (`findModuleDef(argType)`, `extractDataDef` × 2, `extractStructFor`, `extractUnionFor`). Signature honesty — the param was never consumed.
- W10 (this commit) — Delete `oldanalyzer.nim` from repo root. Port complete; git history preserves it.
- W11 (this commit) — Docs sync (overview.md analyzer phase description + this final status update).

Alias-lookup fix landed as part of W8: `findArgTypeModule` falls
back to iterating fileScope values comparing `parser.Module` identity
when the name-key lookup misses. Handles the `import { u8 as Byte }`
case that phase A exposed on activation.

## Deliverables

**14 phase-A files** in `src/analyzer/`: argdef, funcdef, moduledef,
generic, literaldef, structdef, variantdef, uniondef, datadef,
definedtype, filedef, appdef (+ the pre-existing importdef with
renamed type).

**11 phase-A analyzer procs** on the facade (`src/analyzer.nim`):
analyzeArgumentDefinition (2), analyzeFunctionDefinition (2),
analyzeStruct, analyzeVariant, analyzeUnion, analyzeData,
analyzeModuleDefinition, analyzeGeneric, analyzeDefinedType,
analyzeFileDefinition, analyzeAppDefinition.

**Phase-B body walker migration** — 24 body walkers thread
`appDef: AnalyzedAppDefinition` as their first parameter and use it
to consume phase-A output at the two overload-resolution sites and
the return-type site.

**Perf**: `analyzeArgumentList` no longer re-analyzes candidate
funcDef arg types per call — reads from `appDef.findFunctionDef`.
`analyzeFunctionCall` no longer re-analyzes the return type — reads
from `matchingFuncDef.returns` (only substitutes via `.concrete`).

## Follow-ups not part of this recovery

- Migrate `extractStruct` / `extractUnion` / `extractDataDef` return
  types from `ResolvedStructDef` / `ResolvedUnionDef` / `ResolvedData`
  to their analyzer equivalents (`AnalyzedStruct` / `AnalyzedUnion` /
  `AnalyzedData`) so consumers like `analyzeGetter` no longer
  re-analyze property arg types. Requires downstream signature
  changes (e.g. `newAnalyzedGetter.property` from `ResolvedArgumentDef`
  → `AnalyzedArgumentDefinition`).
- Equality-vs-unification for `AnalyzedArgumentType==` (owned by
  `plans/plan_deferred_typing.md`).
- Retire the `analyzeArgumentType` re-analysis in `analyzeGetter`,
  `analyzeLiteralInitializer`, `analyzeBareLiteral` where callers
  have `appDef` in scope.

None of these block correctness — they're perf / cohesion cleanup.

## Context

An earlier refactor collapsed the analyzer's two-phase structure into
a single per-file walk. The old analyzer is preserved verbatim in
`oldanalyzer.nim` at the repo root (with a batch of pre-applied
resolver-name renames — see § Renames already applied). This plan
reintroduces the phase A capability into the current DDD folder layout
under `src/analyzer/` **without** wholesale-reverting to the monolith.

**Working state before this plan starts**: 327/327 unit tests green,
33/35 integration. The current single-pass analyzer works for
in-file, in-topo-order call sites; it just re-analyzes signatures at
every call site instead of once at definition time, and skips
def-time constraint verification that the old phase A performed
eagerly. This plan is additive — the current per-body procs stay,
gaining `AnalyzedFileDefinition` context arguments.

## What phase A did (from `oldanalyzer.nim`)

**Phase A** (`analyzeAppDefinition`, line 950): walks every file,
every module + generic, every struct/union/literal, every funcDef —
produces `AnalyzedAppDefinition`. Guarantees:
- Every module's `requires` clause has been checked (via
  `analyzeGenericArgumentType` at the module's own definition site).
- Every module's data block has been analyzed (via `analyzeData`).
- Every funcDef signature has been analyzed once with concretized
  `AnalyzedArgumentType` arg + return types (via
  `analyzeFunctionDefinition`).
- Per-file `definedTypeIndex: AnalyzedDefinedTypeScope` maps local
  names → `AnalyzedDefinedType`.
- Per-app `fileDefIndex: Table[string, int]` allows path-based lookup.

**Phase B** (`analyze`, line 2331): runs phase A first; then walks
each fileDef's function bodies via `analyzeFile(appDef, fileDef)`.
Bodies consume `AnalyzedModuleDefinition` / `AnalyzedFileDefinition`
context for overload resolution — no signature re-analysis.

## Types to reintroduce (14)

Grouped by cluster; each becomes one file under `src/analyzer/`.
Constructor + accessors + `analyze*Definition` proc per file, matching
the parser/resolver DDD convention.

| # | Type | New file | Contains |
|---|---|---|---|
| 1 | `AnalyzedArgumentDefinition` | `src/analyzer/argdef.nim` | argType + name + concrete overloads |
| 2 | `AnalyzedFunctionDefinition` | `src/analyzer/funcdef.nim` | resolved + args + returns |
| 3 | `AnalyzedLiteralBlock` | `src/analyzer/literaldef.nim` | resolved LiteralDef wrapper |
| 4 | `AnalyzedStruct` | `src/analyzer/structdef.nim` | resolved + fields (analyzed) + fieldIndex |
| 5 | `AnalyzedVariant` | `src/analyzer/variantdef.nim` | resolved + fields (analyzed) + fieldIndex |
| 6 | `AnalyzedUnion` | `src/analyzer/uniondef.nim` | resolved + variants + variantIndex |
| 7 | `AnalyzedData` | `src/analyzer/datadef.nim` | tagged union over struct/union/literal |
| 8 | `AnalyzedModuleDefinition` | `src/analyzer/moduledef.nim` | resolved + requires + data + funcDefs + funcDefIndex + funcNameArityIndex + findFunctionDef + findFunctionDefs |
| 9 | `AnalyzedGeneric` | `src/analyzer/generic.nim` | resolved + funcDefs + funcNameArityIndex + findFunctionDefs |
| 10 | `AnalyzedDefinedType` | `src/analyzer/definedtype.nim` | tagged union over module/generic |
| 11 | `AnalyzedDefinedTypeScope` | reuse `src/analyzer/definedtype.nim` | `Table[Identifier, AnalyzedDefinedType]` |
| 12 | `AnalyzedImportDefinition` | reuse existing `importdef.nim` | rename its type from `AnalyzedImportDef` → `AnalyzedImportDefinition` **OR** keep both names OR (cleanest) rename the current type to `AnalyzedImportDefinition` and let phase-B consume the same type |
| 13 | `AnalyzedFileDefinition` | `src/analyzer/filedef.nim` | resolved + imports + definedTypes + scope + definedTypeIndex + findDefinedType |
| 14 | `AnalyzedAppDefinition` | `src/analyzer/appdef.nim` | resolved + fileDefs + fileDefIndex + findFileDef |

## Renames already applied to `oldanalyzer.nim`

To reduce manual porting friction, the following resolver-side
renames have already been sed-applied to `oldanalyzer.nim`:

- `ResolvedDefinedType` → `ResolvedType`
- `ResolvedFunctionDefinition` → `ResolvedFunctionDef`
- `ResolvedArgumentDefinition` → `ResolvedArgumentDef`
- `ResolvedLiteralType` → `ResolvedLiteralDef`
- `ResolvedStruct` → `ResolvedStructDef` (partial — some Initializer/Ref cases caught bogusly and re-fixed)
- `ResolvedUnion` → `ResolvedUnionDef` (same partial fix)
- `ResolvedMutation` → `ResolvedSetter`
- `findDefinedType` → `findType`
- `definedTypes` → `types`

Fixed bogus artifacts: `ResolvedStructDefInitializer` → `ResolvedStructInitializer`, same for Union.

**Renames still to figure out during the port** (spot at time of first
compile error; look at the underlying type shape in the current
resolver to find the equivalent):

- `ResolvedDefinedArgumentType` — merged into `ResolvedArgumentType` in the current resolver (the tagged union collapsed one layer).
- `ResolvedFileScope` (resolver-side) — currently the resolver's `FileScope` is `Table[Identifier, Type]` (parser Type, not resolver Type). The old analyzer's `ResolvedFileScope` was `Table[Identifier, ResolvedDefinedType]`. Different shape entirely.
- Any accessor mismatches: e.g. `ResolvedImportedType.definedType` (old) → `.typ` (new).

## Semantic gaps to plug

Beyond mechanical porting, the following behaviors need to be
restored:

1. **Def-time requires validation**. Phase A's
   `analyzeModuleDefinition` walks a module's `requires` clause and
   calls `analyzeGenericArgumentType` on each. If a required generic
   name doesn't resolve or fails constraint check, the error surfaces
   at the module's own declaration site (not at the first user of
   that module). Currently missing.

2. **Concretized signature caching**. Phase A's
   `analyzeFunctionDefinition` produces `AnalyzedFunctionDefinition`
   whose `args` are already `seq[AnalyzedArgumentDefinition]` (with
   `AnalyzedArgumentType`). Phase B looks up funcDefs and reads
   `.args` / `.returns` directly — no re-analysis per call. Current
   analyzer re-runs `analyzeArgumentType` at every call site.

3. **Cross-file signature guarantee**. Phase A completes for the
   whole app before phase B runs any body. Current analyzer runs each
   file end-to-end (defs + bodies) in topo order — same-file
   cross-module calls depend on module declaration order, which
   isn't a stable contract.

4. **`extractDataDef` / `extractStructFor` / `extractUnionFor`**
   currently on the facade — these look up a module's data block via
   the current shallow scope. With phase A in place, they'd read from
   `AnalyzedModuleDefinition.data` directly, which is already
   concretized.

## Work items — commit-sized chunks

Each item ships as its own commit, tests green throughout.

### W0 — Baseline snapshot + drop `oldanalyzer.nim` renames doc

- Commit the current tree state (327/327 baseline).
- Ensure `oldanalyzer.nim` is present at repo root as reference.
- Add a `# PORT: applied renames` comment block at the top of
  `oldanalyzer.nim` listing the renames already applied so a future
  reader knows the file is a partial-port reference, not pristine.
- 327/327 + 33/35 baseline preserved.

### W1 — Introduce `AnalyzedArgumentDefinition` (leaf, no dependencies)

- New file `src/analyzer/argdef.nim`: type + `newAnalyzedArgumentDef*`
  + accessors + `concrete*` overloads + `analyzeArgumentDef*`
  overloads.
- Facade `src/analyzer.nim`: import + export.
- Body-level statement.nim, kwargs, function-call handling still
  work; nothing yet consumes `AnalyzedArgumentDefinition` (added but
  unused).
- 327/327.

### W2 — Introduce `AnalyzedFunctionDefinition`

- New file `src/analyzer/funcdef.nim`: type + constructor + accessors
  + `analyzeFunctionDefinition*` overloads (module context + generic
  context).
- Depends on W1.
- 327/327.

### W3 — Introduce `AnalyzedLiteralBlock` / `AnalyzedStruct` / `AnalyzedVariant` / `AnalyzedUnion` / `AnalyzedData`

- Five new files (or bundled by cluster if there's mutual recursion):
  `literaldef.nim` (add block wrapper alongside existing enum),
  `structdef.nim`, `variantdef.nim`, `uniondef.nim`, `datadef.nim`.
- `analyzeStruct` / `analyzeVariant` / `analyzeUnion` / `analyzeData`
  procs. Each walks its fields via W1's `analyzeArgumentDef`.
- 327/327.

### W4 — Introduce `AnalyzedModuleDefinition` + `AnalyzedGeneric`

- New files `moduledef.nim` and `generic.nim` (the phase-A generic
  type — distinct from the existing body-level generic-arg-type file
  `genericargtype.nim`).
- `analyzeModuleDefinition` — walks requires, data, and each function's
  def. Assembles `AnalyzedModuleDefinition` with the funcDef indices.
- `analyzeGeneric` — walks funcDef signatures, assembles
  `AnalyzedGeneric`.
- `findFunctionDef` / `findFunctionDefs` accessors move onto
  `AnalyzedModuleDefinition` / `AnalyzedGeneric` (currently only exist
  as free-standing procs consuming ResolvedModule).
- 327/327.

### W5 — Introduce `AnalyzedDefinedType` + `AnalyzedDefinedTypeScope`

- New file `definedtype.nim`: tagged union over `AnalyzedModuleDefinition`
  / `AnalyzedGeneric` + `AnalyzedDefinedTypeScope` alias.
- `analyzeDefinedType` proc dispatching to W4 procs.
- 327/327.

### W6 — Introduce `AnalyzedFileDefinition` + rework `AnalyzedImportDef`

Decision: **rename current `AnalyzedImportDef` → `AnalyzedImportDefinition`**
so phase A + B share one type. (Cheaper than maintaining both.) Alternative:
add `AnalyzedImportDefinition` alongside — reject; adds parallel-hierarchy
noise for no gain.

- Rename type + all its accessors + all call sites.
- New file `filedef.nim`: `AnalyzedFileDefinition` + constructor +
  accessors + `findDefinedType` + `analyzeFileDefinition`.
- `analyzeImportedType` / `analyzeImportDefinition` procs read the
  fileScope from the file being imported.
- 327/327.

### W7 — Introduce `AnalyzedAppDefinition`

- New file `appdef.nim`: `AnalyzedAppDefinition` + `fileDefIndex` +
  `findFileDef` + `analyzeAppDefinition*`.
- At this point phase A is fully wired but not yet called by the top
  level. `analyze*` still runs the single-pass version.
- 327/327 (phase A code is compiled but unused).

### W8 — Wire two-pass orchestration

- Rewrite `analyze*(app)` on the facade:
  ```nim
  proc analyze*(app: ResolvedApp): Result[AnalyzedApp, string] =
    let analyzedAppDef = ? analyzeAppDefinition(app)
    var analyzedFiles: seq[AnalyzedFile]
    for fileDef in analyzedAppDef.fileDefs:
      let analyzedFile = ? analyzeFile(analyzedAppDef, fileDef)
      analyzedFiles.add(analyzedFile)
    ok(newAnalyzedApp(analyzedAppDef, analyzedFiles))
  ```
- `analyzeFile(appDef, fileDef)` — augment `defScope` with imports
  (per oldanalyzer:2308-2313), walk each `AnalyzedDefinedType`;
  extern functions build directly from the pre-analyzed `funcDefs`
  (`findFunctionDef` on the moduleDef), user functions call
  `analyzeUserFunction` with `moduleDef` + `defScope` in scope.
- Body-level procs (`analyzeUserFunction`, `analyzeExpression`,
  `analyzeFunctionCall`, etc.) get new signatures: they take
  `AnalyzedModuleDefinition` + `AnalyzedDefinedTypeScope` instead of
  the raw `ResolvedFileScope` / `ResolvedModule`.
- Overload resolution (`analyzeArgumentList`, `analyzeFunctionCall`)
  reads pre-analyzed args + returns from the moduleDef's funcDef
  entries — no re-analysis.
- **This is the largest work item.** Split into sub-commits if the
  ripple is too big:
  - W8a: introduce the new signature threads on all body procs but
    keep them ignored (deprecate-in-place).
  - W8b: switch overload resolution to read from pre-analyzed funcDefs.
  - W8c: retire the shallow lookup paths.
- 327/327 + 33/35 preserved throughout.

### W9 — Retire the shim procs on the facade

- `extractDataDef` / `extractStructFor` / `extractUnionFor` /
  `findModuleDef` etc. on `src/analyzer.nim` currently work off
  `ResolvedFileScope`. Rewrite them to work off
  `AnalyzedFileDefinition` (or delete if callers can go through the
  moduleDef directly).
- 327/327.

### W10 — Delete `oldanalyzer.nim` from the repo root

Only after every phase A capability is reintroduced. The reference
copy in git history stays accessible via `git show <sha>:oldanalyzer.nim`.

### W11 — Docs sync

- `overview.md` — analyzer phase description gets the two-pass
  description back (currently reads as single-pass).
- `overview.md` file-layout tables — add the 14 new phase-A files
  under `src/analyzer/`.
- `documentation.md` — no user-visible change (both phases surface
  as one `analyze*` call), unless the plan gets deeper design docs.

## Verification checkpoints

- **Every W item**: `nimble test` returns 327/327 unit; `./test.sh`
  returns 33/35 integration (2 pre-existing failures allowed).
- **W8 specifically**: the moment overload resolution flips to
  reading pre-analyzed funcDefs, add a regression test that a
  same-file cross-module call (moduleA calls moduleB.method where B
  is declared AFTER A in the file) resolves successfully — this is
  the scenario current single-pass can silently miscompile.

## What NOT to do

- Do not `git checkout` the pre-merge resolver state and try to run
  oldanalyzer on top. The current resolver has valid improvements
  (per-type files, kwarg header refactor, StructDefHeader extraction)
  that shouldn't be lost. Port phase A on top of the current
  resolver.

- Do not maintain both `AnalyzedImportDef` and
  `AnalyzedImportDefinition` in parallel — pick one name (W6 uses
  the `Definition` suffix for consistency with the other phase-A
  types) and migrate all call sites.

- Do not merge phase A into the resolver (again). The reason the
  merge failed the first time is the resolver's cyclic-dependency
  model. Phase A running as a distinct analyzer pass sidesteps this
  because it only needs completed resolver output, not mid-pass
  resolver state.

## Scope boundary

**In scope**: reintroducing phase A + wiring two-pass orchestration.

**Out of scope** (defer to separate plans):
- Equality-vs-unification for `AnalyzedArgumentType==`
  (`plan_deferred_typing.md` covers this).
- Substitution chain collapse in `concrete()`.
- F32/F64/Pointer literal kinds in `analyzeLiteral`.
- Impl-map update from literal positions.
- Nested-impl walk in `findRequiredImplsForFields`.
- Statement-level type-correctness checks (assignment compat,
  match exhaustiveness, setter type equality).

These items are on the analyzer's existing "What's Next" list in
`overview.md` and remain there.

## Estimated cost

W0-W7: mostly additive, each 1-3 hours of focused work + verify.
W8: 4-8 hours (the ripple through body procs is substantial).
W9-W11: 1-2 hours combined.

**Realistic total**: 15-25 hours of focused work spread across
multiple sessions. Do NOT try to compress this into one session —
the last attempt collapsed phase A precisely because the incremental
cost was misjudged.
