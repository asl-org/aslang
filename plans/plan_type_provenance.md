# Type provenance: `*LocalType` + the `*Type` scope-entry union

## Problem

Scope contexts erase provenance. `newFileContext` /
`newResolvedFileContext` insert an imported name's *underlying* type
directly, so downstream layers cannot distinguish "defined here" from
"imported from B" — even though the import bindings
(`ResolvedImportedType.typ`, `AnalyzedDefImportedType.typ`) carry the
underlying all along. Consequences today:

- `inferGenerics` derives an imported module's require slots by name
  in the *using* file's scope → the constraint-generic import rule
  ("import `Comparable` alongside `Container`") and the
  nested_generics.asl failure (`type Map does not exist` — a field
  root of an imported struct's def, not user-written).
- The defanalyzer's contract lookup (`fileCtx.findGeneric`) is
  use-site-scoped for the same reason.

The fix: what a name resolves to becomes a union — Local | Imported —
with the Imported variant keeping the underlying (and later, source
capability). Declarations stay local (`File.types: seq[LocalType]`);
the union is a *scope-entry* concept.

Transitive case (A imports Container from B; B imports Comparable
from C): rung-1 hops terminate at the underlying parser object (defs
live on the parser Generic — one hop suffices). Rung-2 needs C's
ResolvedGeneric — the chain-vs-identity-index fork (P3, undecided).

App context is needed exactly once per rung, at import-LINK time
(context construction); never at hop time. Rung 2 already has it
(analyzeDefImport takes ResolvedApp); rung 1 would need resolve() to
thread its accumulated ResolvedFiles IF rung-1 entries ever capture
resolved sources (P3 question; P1/P2 don't).

## Phases

Rule: MECHANICAL and BEHAVIORAL changes land in separate commits.

### P1 — vocabulary rename [MECHANICAL — zero semantic diff]

grammar.md first (per its own doctrine), full target vocabulary:

```
LocalType: Module | Generic              # was Type
Type: LocalType | ImportedType           # scope entry — what a name resolves to
```
plus design notes: (a) the union member ImportedType is the LINKED
binding (carries the source's LocalType), not the parse-time
declaration; (b) the union hashes/compares by its localType so
aliased imports keep landing on one identity key; (c) declaration
lists never unionize.

Code renames (whole-identifier, word-boundary regex — NEVER naive
substring: `TypeContext`, `ResolvedTypeContext`, `ImportedType`,
`findType`, `TypeKind` must not be clipped; rename `*TypeKind` tokens
before `*Type` tokens):

| rung | type | kind enum | values | ctor |
|---|---|---|---|---|
| parser | `Type` → `LocalType` | `TypeKind` → `LocalTypeKind` | `tkModule/tkGeneric` → `ltkModule/ltkGeneric` | `newType` → `newLocalType` |
| resolver | `ResolvedType` → `ResolvedLocalType` | `ResolvedTypeKind` → `ResolvedLocalTypeKind` | `rtkModule/rtkGeneric` → `rltkModule/rltkGeneric` | `newResolvedType` → `newResolvedLocalType` |
| defanalyzer | `AnalyzedType` → `AnalyzedLocalType` | `AnalyzedTypeKind` → `AnalyzedLocalTypeKind` | `atkModule/atkGeneric` → `altkModule/altkGeneric` | `newAnalyzedType` → `newAnalyzedLocalType` |

Surface: ~149 tk sites, 27 rtk, 84 atk, 15 `parser.Type` qualifiers,
17 ctor calls, plus every `: Type` / `seq[Type]` / table signature,
tests, and doc mentions (overview.md ladder table). Proc names
(findType, resolveType, analyzeDefType) KEEP their names — they
operate on declarations, which are local by definition; renaming
them is optional polish, not P1.

Critical property: after P1, the bare names `Type` / `ResolvedType` /
`AnalyzedType` do not exist anywhere. P2 reintroduces them — any
stale reference from P1 becomes a compile error instead of a silent
mis-bind. The compiler enforces the phase boundary.

Gates: identical counts (348 / 33-35 / SUCCESS), zero test-expectation
edits.

### P2 — the unions + `localType` [STRUCTURAL — observable behavior neutral]

New code, but no program compiles differently; every test expectation
stays byte-identical. Not tagged mechanical (new types/logic), not
behavioral (no semantic change) — its own commit.

Rung 1 — `Type` reborn in resolver/filecontext.nim (cohesion: it is
FileContext's value type; imports ./parser + ./imports only, no
cycles):

```nim
TypeKind = tkLocal, tkImported
Type = tkLocal(local: LocalType) | tkImported(imported: ResolvedImportedType)
localType(t): LocalType   # tkLocal → local; tkImported → imported.typ
hash/==(t) = t.localType.hash   # alias immunity — NON-NEGOTIABLE
name/loc delegate to localType
```
- `newFileContext`: local types insert `tkLocal`; import bindings
  insert `tkImported` (keeping the ResolvedImportedType instead of
  flattening to .typ).
- `findType` returns the union (decision: union, not auto-unwrap —
  its callers are few and P3's provenance consumers use the same
  entry). Callers add `.localType`: resolveArgumentType,
  resolveFunctionCall, and FileContext's own findModule/findGeneric
  (which keep returning Module/Generic — their ~dozen callers
  unchanged).
- inferGenerics untouched (consumes unwrapped values; learns to hop
  only in P3).

Rung 2 — `ResolvedType` reborn in defanalyzer/filecontext.nim:

```nim
ResolvedTypeKind = rtkLocal, rtkImported
ResolvedType = rtkLocal(local: ResolvedLocalType) | rtkImported(imported: AnalyzedDefImportedType)
localType / hash-by-localType / delegates — same shape
```
- keys stay `parser.LocalType` identity; construction wraps
  analyzedImports as rtkImported, local ResolvedLocalTypes as
  rtkLocal.
- rung-2 findType returns the union; `.localType` at:
  analyzeDefFunctionCall (AnalyzedDefFunctionCall.typ field stays
  ResolvedLocalType), analyzer.nim's call-receiver site
  (fileDef.scope.findType → .localType before the module compare and
  the AnalyzedFileContext probe).

Rung 3 (AnalyzedFileContext): NO union in P2 — P1 rename only.
Whether it ever needs one depends on the P3 fork.

Gates: identical counts, zero expectation edits — that is the
neutrality proof.

### P3 — provenance consumers [BEHAVIORAL — programs newly compile]

Sub-phases, each its own commit; P3a is the decision gate:

- P3a [DECISION]: rung-2 enrichment route for the transitive case —
  (i) chain: entries capture source capability; rung-2 context build
  threads the fileDef accumulator (file-philosophy pure, more
  machinery), vs (ii) app-wide identity index
  (Table[parser.LocalType, ResolvedLocalType] built once in
  analyzeDefApp — identity is app-unique by construction; less
  machinery, app-flavored). UNDECIDED — user call.
- P3b [BEHAVIORAL]: inferGenerics + shallow satisfies derive requires
  against the DEFINING file (via the Imported entry's source
  capability at rung 1; needs resolve() to thread accumulated
  ResolvedFiles OR capture source FileContext at link time). The
  constraint-generic import rule DIES here. Flagship test:
  `Container[u8]` without importing Comparable compiles.
  nested_generics.asl expected to flip (test.sh baseline → 34/35?).
  documentation.md "Constraint generics must be in scope at use
  sites" section deleted.
- P3c [BEHAVIORAL]: defanalyzer contract lookup follows provenance
  (per P3a route); the phase-A findGeneric-on-using-scope disappears.
- P3d [MECHANICAL]: docs sweep + test migrations + memory.

Interaction notes: the publicity rule (public modules require public
generics, newResolvedModule) guarantees every contract P3 carries
across files is public. Option-C's check-relocation questions
(resolver focus, constructor ownership of count+satisfies) become
independent code-organization decisions once the data is fixed —
they are NOT part of this plan.

## Commit discipline

P1: one commit, tagged mechanical. P2: one commit, structural /
behavior-neutral (neutrality evidenced by untouched test
expectations). P3b/P3c: separate behavioral commits, each with the
newly-accepted/rejected program classes named in the message. Never
mix rungs of this ladder in one commit with unrelated work.
