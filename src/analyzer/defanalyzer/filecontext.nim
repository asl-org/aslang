## ResolvedFileContext — per-file identity-keyed lookup (parser.LocalType
## -> ResolvedLocalType), spanning imports + local defined types. Keys
## hash by source location, so the same type imported under two
## bindings (`import { Solver as First }` + `{ Solver as Second }`)
## lands on one key and aliased imports can never miss.
##
## Name resolution (user-typed name -> parser.LocalType) happens at
## resolve time against the resolver's name-keyed FileContext — by the
## time the analyzer runs, every reference already carries its
## parser.LocalType identity. Binding-name collisions are also caught
## there; construction here only rejects a genuinely different
## entry under an existing key (see `update`).

import strformat, tables

import ./resolver
import ./importdef
import ./importedtypedef

type ResolvedFileContext* = Table[parser.LocalType, ResolvedLocalType]

proc update(fileCtx: var ResolvedFileContext, parsed: parser.LocalType, resolved: ResolvedLocalType) =
  ## Same-identity re-insert (the same type imported under a second
  ## binding) is idempotent — keys hash by source location, so both
  ## bindings land here with an equal ResolvedLocalType. A genuinely
  ## different entry under an existing key is a compiler bug — the
  ## resolver's name-keyed FileContext already rejected duplicate
  ## declarations.
  assert(parsed notin fileCtx or fileCtx[parsed] == resolved, fmt"[BUG] - {parsed.loc} conflicting entries for type `{parsed.name.asl}` in the file context")
  fileCtx[parsed] = resolved

proc newResolvedFileContext*(imports: seq[AnalyzedDefImport], types: seq[ResolvedLocalType]): ResolvedFileContext =
  var fileCtx: ResolvedFileContext
  for imp in imports:
    for impType in imp.importedTypes:
      fileCtx.update(impType.typ.parsed, impType.typ)
  for typ in types:
    fileCtx.update(typ.parsed, typ)
  return fileCtx

# Identity lookups — the resolver bound every key it hands us in this
# same file's scope, so a miss (or a kind mismatch) is a compiler
# bug, never a user error. The asserts own that invariant here so
# call sites don't have to.
proc findType*(fileCtx: ResolvedFileContext, parsed: parser.LocalType): ResolvedLocalType =
  assert(parsed in fileCtx, fmt"[BUG] - {parsed.loc} type `{parsed.name.asl}` missing from the file context")
  fileCtx[parsed]

proc findModule*(fileCtx: ResolvedFileContext, module: Module): ResolvedModule =
  let typ = fileCtx.findType(newLocalType(module))
  assert(typ.kind == rltkModule, fmt"[BUG] - {module.loc} `{module.name.asl}` was bound as a module by the resolver")
  typ.module

proc findGeneric*(fileCtx: ResolvedFileContext, generic: Generic): ResolvedGeneric =
  let typ = fileCtx.findType(newLocalType(generic))
  assert(typ.kind == rltkGeneric, fmt"[BUG] - {generic.loc} `{generic.name.asl}` was bound as a generic by the resolver")
  typ.generic
