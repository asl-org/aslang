## AnalyzedFileContext — per-file identity-keyed lookup (ResolvedLocalType
## -> AnalyzedLocalType), spanning imports + local defined types. The
## caller hands `newAnalyzedFileContext` one merged `AnalyzedLocalType`
## seq (imported twins ++ this file's defs); there is no separate imported
## form. Keys hash by source location, so the same type imported under two
## bindings (`import { Solver as First }` + `{ Solver as Second }`) lands
## on one key and aliased imports can never miss.
##
## Name resolution (user-typed name -> ResolvedLocalType) happens at
## resolve time against the resolver's name-keyed ResolvedFile — by the
## time the analyzer runs, every reference already carries its
## ResolvedLocalType identity. Binding-name collisions are also caught
## there; construction here only rejects a genuinely different
## entry under an existing key (an idempotent same-identity re-insert
## is allowed — see the assert in newAnalyzedFileContext).

import strformat, tables

import ../parser/main as parser
import ../resolver/main as resolver
import ../defanalyzer/main as defanalyzer

type AnalyzedFileContext* = Table[ResolvedLocalType, AnalyzedLocalType]

proc newAnalyzedFileContext*(types: seq[AnalyzedLocalType]): AnalyzedFileContext =
  var fileCtx: AnalyzedFileContext
  for typ in types:
    assert(typ.resolved notin fileCtx or fileCtx[typ.resolved] == typ, fmt"[BUG] - {typ.resolved.loc} conflicting entries for type `{typ.resolved.name.asl}` in the file context")
    fileCtx[typ.resolved] = typ
  return fileCtx

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
