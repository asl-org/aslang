# Drop `fileScope` threading from analyze* signatures

## Context

Scrutinizing after `plan_alias_lookup_cleanup.md` completed: `fileScope:
ResolvedFileScope` is a parameter on ~30 analyze* procs across the
analyzer facade, but only 2 leaves actually read it:

- `analyzeFunctionCall:695` — `fileScope.findType(fncall.parsed.root, ...)`.
  Resolves the user-typed module name at a function call site.
- `defaultLiteralArgType:978,980` — `notin fileScope` + `fileScope[ident]`.
  Looks up the synthesized `i32`/`f32`/`String` names for bare
  literal defaults.

Every other proc in the chain takes `fileScope` and forwards it to
subordinate calls. Zero reads.

The current 4-param phase-A shape is `(app, file, fileScope, module|generic)`.
The 6-param phase-B shape is `(appDef, app, file, fileScope, module,
funcScope)`. Drop `fileScope` from both → phase-A goes to 3 params,
phase-B goes to 5.

## Design

**Phase-A procs (no fileScope readers after W2 of prior plan)**: drop
the param entirely. Callers stop passing it. No leaf lookup needed.

**Phase-B procs**: drop the param from the non-leaf procs. The 2
leaves look up fileScope at entry via the app-level index:

```nim
let fileDef = ? appDef.findFileDef(file.path)
let fileScope = fileDef.scope
```

`appDef.findFileDef` is O(1) (`fileDefIndex: Table[string, int]`), and
`appDef` is already threaded to every phase-B analyze* proc. `file:
ResolvedFile` is also already threaded. So the leaf lookup is
zero-new-plumbing.

**Facade `findType(fileScope, name, loc)`**: currently used by
`analyzeFunctionCall`. After migration, the leaf inlines the lookup
via `let fileScope = ? appDef.findFileDef(file.path).map(f => f.scope)`
and then calls `fileScope.findType(...)`. Keep the helper — it's now
called at one place but the helper still adds error-message
consistency.

**`newResolvedFileScope` return type**: unchanged — still returns
`Result[ResolvedFileScope, string]`. Still called at file-def
construction time to populate `AnalyzedFileDefinition.scope`.

## Sites to touch

Phase-A procs (drop `fileScope` from signature + all call sites):
1. `analyzeGenericArgumentType` (module-context overload)
2. `analyzeArgumentType` (module-context, generic-context)
3. `analyzeModuleArgumentType` (module-context, generic-context)
4. `analyzeArgumentDefinition` (module-context, generic-context)
5. `analyzeFunctionDefinition` (module-context, generic-context)
6. `analyzeStruct`, `analyzeVariant`, `analyzeUnion`, `analyzeData`
7. `analyzeModuleDefinition`, `analyzeGeneric`, `analyzeDefinedType`

Phase-B procs (drop `fileScope`, leaves look up at entry):
1. `analyzeUnionCasePattern`, `analyzeCasePattern` (2 overloads)
2. `analyzeGetter`, `analyzeLiteralInitializer`, `analyzeBareLiteral`
3. `analyzeExpression`, `analyzeStatement`
4. `analyzeValueTypeAgainstDefType` (4 overloads)
5. `analyzeArgumentList` (2 overloads)
6. `analyzeCaseBlock` (2 overloads), `analyzeCases` (2 overloads)
7. `analyzeMatchExpression`, `analyzeKeywordArgument`
8. `analyzeUnionRef`, `analyzeUnionInitializer`
9. `analyzeStructRef`, `analyzeStructInitializer`
10. `analyzeFunctionCall` ← LEAF, adds a lookup at entry
11. `defaultLiteralArgType` ← LEAF, adds `appDef`+`file` params + lookup at entry

`analyzeAppDefinition` / `analyzeFile` / `analyzeApp` — the top-level
orchestrators still construct fileScope inline (via
`newResolvedFileScope`) so they can pass it into
`newAnalyzedFileDefinition`. Just stop passing it downstream.

## Work items

Each ships as its own commit, all three gates green
(nimble test / ./test.sh / `asl build examples/sample.asl`).

### W0 — Plan doc

Commit this file.

### W1 — Drop `fileScope` from phase-A signatures

Delete the param from every phase-A proc listed above. Update every
call site to stop passing `fileScope`. Purely mechanical — no leaf
reads the param in phase A.

### W2 — Drop `fileScope` from phase-B threading procs; leaves lookup

Delete the param from every phase-B proc except the 2 leaves. Update
call sites. In the 2 leaves (`analyzeFunctionCall`,
`defaultLiteralArgType`) add a lookup at entry:

```nim
let fileDef = ? appDef.findFileDef(file.path)
let fileScope = fileDef.scope
```

`defaultLiteralArgType` gains `appDef` and `file` params (currently
takes only `fileScope`). Its caller (`analyzeBareLiteral`) already has
both in scope post-W2.

### W3 — Mark plan complete

Status block prepended.

## Non-goals

- Do NOT rename `ResolvedFileScope`. Separate concern.
- Do NOT drop `file: ResolvedFile` from signatures. Still used widely
  (`file.findGeneric`, `file.path`, `file.findModule`, etc.).
- Do NOT drop `app: ResolvedApp`. Same reason (`app.findType`,
  `app.findModule`, `app.findFile`).
- Do NOT restructure the fileScope storage. Keep it built at
  `analyzeFileDefinition` time and stored on `AnalyzedFileDefinition`.

## Risk

Mechanical but wide. ~30 signatures × ~2-4 call sites each =
100-150 diff lines. Test coverage is high (327 unit, 33 integration,
`sample.asl` end-to-end) — regressions surface immediately.

## Cost estimate

- W0: 15 min.
- W1: 45-60 min (phase-A ripple).
- W2: 60-90 min (phase-B ripple + 2 leaf lookups).
- W3: 5 min.

**Realistic total**: 2-3 hours.
