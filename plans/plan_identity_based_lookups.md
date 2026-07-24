# Identity-based lookups — migrate scope tables from `Identifier` keys to `parser.Type` / `parser.Module` keys

## Context

`Identifier` in this codebase hashes by string value (`identifier.value`).
That's correct at the parser layer where the same name string canonically
means "the user typed this name". But downstream layers use `Identifier`-
keyed tables to look up types the resolver has *already* mapped to a
specific `parser.Module` or `parser.Generic`. In those downstream cases
the lookup should key on parser-level identity (hash-by-loc, via
`parser.Module.hash`), not on the string name.

The mismatch surfaced concretely as the alias-lookup bug fixed in W8 of
`plan_analyzer_two_pass.md`: when a user writes `import { u8 as Byte }`,
`fileScope` is keyed by the binding (`Byte`), but a
`ResolvedModuleArgumentType`'s `.name` reports the underlying module
name (`u8`). Looking up "u8" in a fileScope keyed by "Byte" fails —
even though u8 is imported. The W8 fix added a fallback that iterates
fileScope values comparing `parser.Module` identity. That works but
patches the symptom; the design flaw is that fileScope shouldn't be
name-keyed for post-resolution lookups in the first place.

More instances of the same pattern exist across the codebase. Every one
is a latent bug waiting for the right rename / alias / same-name-across-
files scenario to trigger.

## Categorization

**Legitimate name-based lookups** (must stay `Identifier`-keyed):

1. `parser/files.nim` — `File.typeIndex: Table[Identifier, int]`. Maps
   the user-typed name in source → position in this file's local
   `types` seq. Entry point for name resolution; keying by string is
   correct because the parser hasn't derived any identity yet.
2. `parser/imports.nim` — the parsed-import name resolution machinery.
   `ImportedType.binding` (the alias if present, else the original
   name) is the key.
3. `resolver/filescope.nim` — `FileScope = Table[Identifier, parser.Type]`.
   The name→identity bridge: takes an aliased binding like "Byte" and
   yields the underlying parser.Type. This is the ONE table where
   both keying schemes are needed together.
4. `parser/modules.nim`, `parser/generics.nim` — `funcDefArityIndex:
   Table[Identifier, Table[int, seq[int]]]`. Overload lookup by
   function name + arity. Legit — users call functions by name.
5. `parser/structdef.nim`, `parser/variantdef.nim`, `parser/uniondef.nim`
   — `fieldIndex: Table[Identifier, int]`, `variantIndex: Table[Identifier, int]`.
   Fields and variants are named by the user; name is the identity.
6. `analyzer/funcscope.nim` — `FunctionScope = Table[Identifier, Location]`.
   Variable name scope inside a function body. Variables have no
   identity beyond their name.
7. `analyzer/statement.nim` — `AnalyzedFunctionScope = Table[Identifier,
   AnalyzedArgumentType]`. Same rationale.

**Illegitimate name-based lookups** (should migrate to identity-keyed):

A. `analyzer/filescope.nim` — `ResolvedFileScope = Table[Identifier,
   ResolvedType]`. Currently duplicates the resolver's own FileScope
   (same shape, same keying) for the analyzer's use. Post-resolution
   lookups here miss aliases (the bug we hit). Should be keyed by
   `parser.Type` identity.

B. `analyzer/definedtype.nim` — `AnalyzedDefinedTypeScope = Table[
   Identifier, AnalyzedDefinedType]`. Phase-A per-file scope. Same
   pattern, same alias vulnerability.

**Places using shim to work around the name-vs-identity gap**:

- `analyzer.nim:findArgTypeModule` — the fallback loop iterating
  fileScope values comparing parser.Module identity. Only needed
  because fileScope is name-keyed. Would disappear with the migration.
- `analyzer.nim:findModuleDef(argType, loc)` — reads
  `argType.module.module` directly (bypasses fileScope). Not a bug, but
  hides the "we can't use fileScope for this lookup" fact.

## Root cause in the code

```nim
# src/analyzer/resolver/parser/identifiers.nim
proc hash*(id: Identifier): Hash = hash(id.value)
proc `==`*(id: Identifier, other: Identifier): bool = hash(id) == hash(other)

# src/analyzer/resolver/parser/modules.nim
proc hash*(m: Module): Hash = m.loc.hash
proc `==`*(a, b: Module): bool = a.hash == b.hash
```

Two different name-shaped keys with fundamentally different equality
semantics. Confusing to reason about; easy to grab the wrong one.

## Migration strategy — three options

### Option 1 (recommended): rename + add

Rename current `Identifier`-keyed table type. Add an identity-keyed
sibling. Both stay populated during scope construction; each caller
picks the one that matches its intent.

Concretely for `analyzer/filescope.nim`:
```nim
# Before:
type ResolvedFileScope* = Table[Identifier, ResolvedType]

# After:
type ResolvedNameScope* = Table[Identifier, ResolvedType]      # for initial name lookups
type ResolvedTypeScope* = Table[parser.Type, ResolvedType]     # for post-resolution identity lookups

# Constructor:
proc newResolvedFileScope(...): (ResolvedNameScope, ResolvedTypeScope) =
  # populate both in one pass
```

Body walkers taking `fileScope: ResolvedFileScope` become explicit:
`nameScope: ResolvedNameScope` vs `typeScope: ResolvedTypeScope`.
Callers that need both take both.

**Pros**: forces the intent into the type. No accidental misuse. Grep
tells you exactly which sites do name vs identity lookup.

**Cons**: ripple through 20+ signatures. Some procs need both scopes
threaded, growing param lists.

### Option 2: additive-only

Keep `ResolvedFileScope` as-is. Add a `resolvedByType: Table[parser.Type,
ResolvedType]` alongside it (produced by the same constructor).
Callers migrate case-by-case; no forced rewrite.

**Pros**: much smaller commit footprint. Each site migrates when it
happens to be touched. Zero-ripple.

**Cons**: the pattern stays a smell. New code can accidentally use the
name-keyed variant when it should use the identity-keyed one. The
tension the plan is meant to resolve stays open.

### Option 3: swap key type entirely

Change `ResolvedFileScope = Table[parser.Type, ResolvedType]` outright.
Every initial name lookup must go through a separate name→parser.Type
translator (which lives on the resolver side already — `File.typeIndex`
+ import binding index).

**Pros**: smallest final surface. One right way.

**Cons**: forces the analyzer to acquire parser.Type before hitting
fileScope. Practical concern: some sites (like `defaultLiteralArgType`)
have an Identifier ("i32") and need to look up the parser.Type for it —
those must reach through the parser layer's `File.findType(name)`
first. Adds one extra hop per initial lookup.

**Recommendation**: Option 1. Middle ground — explicit type separation,
forced signature clarity, but keeps the initial-name-lookup path
convenient.

## Work items (Option 1)

Each ships as its own commit, all three gates green at every step
(327/327 unit + 33/35 integration + `sample.asl [SUCCESS]`).

### W0 — Baseline + plan doc

Commit this plan file. Baseline snapshot.

### W1 — Add `ResolvedTypeScope` alongside `ResolvedFileScope`

- New type: `ResolvedTypeScope* = Table[parser.Type, ResolvedType]`
  in `analyzer/filescope.nim`.
- `newResolvedFileScope` returns a tuple `(ResolvedFileScope,
  ResolvedTypeScope)` — populate both in one pass over imports +
  local types. `parser.Type` for the local types is the local `Type`
  itself; for imports, it's the imported `ResolvedImportedType.typ`
  (which IS a parser.Type wrap).

Wait — actually `impType.typ` is `ResolvedType` (the resolver-side
enriched type). To get the underlying `parser.Type`, you need
`impType.typ.parsed` or similar. Verify at implementation time.

- Callers of `newResolvedFileScope` receive both and pass whichever
  is needed. First commit doesn't migrate any consumers — the new
  scope is populated but unused.

### W2 — Migrate `findArgTypeModule` to use `ResolvedTypeScope`

- Change signature: `findArgTypeModule(file, typeScope, argType)`
  where `typeScope: ResolvedTypeScope`.
- Body: replace the two lookups + the identity-fallback with one
  direct `typeScope[newParserType(argType.module)]` lookup.
- The fallback loop disappears.
- Callers pass `typeScope` where they currently pass `fileScope`.

### W3 — Migrate `analyzeAppDefinition.definedTypeIndex` to be primary

Already keyed by `ResolvedType` (identity) — no change to shape.
Verify all consumers going through `appDef.findDefinedType` — that's
already the intended path. This W might be a no-op verification
commit or fold into W4.

### W4 — Migrate phase-A `AnalyzedDefinedTypeScope`

- New type: `AnalyzedDefinedTypeByIdentity = Table[parser.Type,
  AnalyzedDefinedType]`.
- Populate in `AnalyzedFileDefinition` constructor alongside the
  existing name-keyed `definedTypeIndex`.
- Any downstream consumer that has a parser.Type in hand switches to
  the identity table.

### W5 — Retire the name-keyed `ResolvedFileScope` (rename or delete)

Only after every non-legit consumer of the name-keyed scope has
migrated. Rename `ResolvedFileScope` → `ResolvedNameScope` to make
its remaining role (name-to-type bridge for initial lookups) explicit.
Delete if no legit consumers exist (unlikely — `defaultLiteralArgType`
uses it for "i32" → type lookup, which is legit).

### W6 — Docs sync

- `overview.md`: analyzer scope description updated to reflect the
  two-scope split.
- This plan doc marked complete.

## Non-goals

- Do NOT migrate variable scopes (`FunctionScope`,
  `AnalyzedFunctionScope`). Variables have no identity beyond their
  name; those tables are correctly keyed.
- Do NOT migrate parser-level indexes (`typeIndex`, `fieldIndex`,
  `variantIndex`, `funcDefArityIndex`). Parser lookups by user-typed
  name are the correct semantics.
- Do NOT migrate the resolver's own `FileScope`. That's the
  name-to-parser.Type bridge — legit name-keyed.

## Cost estimate

- W0: 15 min (plan commit).
- W1-W5: 30-90 min each depending on ripple. Total 3-5 hours of
  focused work.
- W6: 30 min.

**Realistic total**: 4-6 hours across 2-3 sessions. Not as heavy as
the analyzer two-pass recovery, but non-trivial due to the ripple
through body-walker signatures.

## Blocking preconditions

- Two-pass analyzer recovery (`plan_analyzer_two_pass.md`) must be
  complete. **Status**: complete as of `main-recovery` branch, 15
  commits landed.
- Working tree clean. No mid-refactor state.
