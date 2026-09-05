## AnalyzedFileContext — per-file identity-keyed lookup (ResolvedLocalType
## -> AnalyzedLocalType), spanning imports + local defined types. Keys
## hash by source location, so the same type imported under two
## bindings (`import { Solver as First }` + `{ Solver as Second }`)
## lands on one key and aliased imports can never miss.
##
## Name resolution (user-typed name -> ResolvedLocalType) happens at
## resolve time against the resolver's name-keyed ResolvedFile — by the
## time the analyzer runs, every reference already carries its
## ResolvedLocalType identity. Binding-name collisions are also caught
## there; construction here only rejects a genuinely different
## entry under an existing key (see `update`).

import strformat, tables

import ../defanalyzer/index as defanalyzer
import ./imports

type AnalyzedFileContext* = Table[ResolvedLocalType, AnalyzedLocalType]

proc update(fileCtx: var AnalyzedFileContext, resolved: ResolvedLocalType, analyzed: AnalyzedLocalType) =
  ## Same-identity re-insert (the same type imported under a second
  ## binding) is idempotent — keys hash by source location, so both
  ## bindings land here with an equal AnalyzedLocalType. A genuinely
  ## different entry under an existing key is a compiler bug — the
  ## resolver's name-keyed ResolvedFile already rejected duplicate
  ## declarations.
  assert(resolved notin fileCtx or fileCtx[resolved] == analyzed, fmt"[BUG] - {resolved.loc} conflicting entries for type `{resolved.name.asl}` in the file context")
  fileCtx[resolved] = analyzed

proc newAnalyzedFileContext*(imports: seq[AnalyzedImport], types: seq[AnalyzedLocalType]): AnalyzedFileContext =
  for imp in imports:
    for impType in imp.importedTypes:
      result.update(impType.typ.resolved, impType.typ)
  for typ in types:
    result.update(typ.resolved, typ)

# Identity lookups — phase A analyzed every ResolvedLocalType in this
# file, so a miss (or a kind mismatch) is a compiler bug, never a
# user error. The asserts own that invariant here so call sites
# don't have to.
proc findType*(fileCtx: AnalyzedFileContext, resolved: ResolvedLocalType): AnalyzedLocalType =
  assert(resolved in fileCtx, fmt"[BUG] - {resolved.loc} type `{resolved.name.asl}` missing from the file context")
  fileCtx[resolved]

proc findModule*(fileCtx: AnalyzedFileContext, module: ResolvedModule): AnalyzedDefModule =
  let typ = fileCtx.findType(newResolvedLocalType(module))
  assert(typ.kind == altkModule, fmt"[BUG] - {module.loc} `{module.name.asl}` was analyzed as a module in phase A")
  typ.module

proc findGeneric*(fileCtx: AnalyzedFileContext, generic: ResolvedGeneric): AnalyzedGeneric =
  let typ = fileCtx.findType(newResolvedLocalType(generic))
  assert(typ.kind == altkGeneric, fmt"[BUG] - {generic.loc} `{generic.name.asl}` was analyzed as a generic in phase A")
  typ.generic
