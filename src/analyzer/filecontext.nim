## AnalyzedFileContext — per-file identity-keyed lookup (ResolvedType
## -> AnalyzedType), spanning imports + local defined types. Keys
## hash by source location, so the same type imported under two
## bindings (`import { Solver as First }` + `{ Solver as Second }`)
## lands on one key and aliased imports can never miss.
##
## Name resolution (user-typed name -> ResolvedType) happens at
## resolve time against the resolver's name-keyed FileContext — by the
## time the analyzer runs, every reference already carries its
## ResolvedType identity. Binding-name collisions are also caught
## there; construction here only rejects a genuinely different
## entry under an existing key (see `update`).

import results, strformat, tables

import ./defanalyzer
import ./importedtype
import ./imports

type AnalyzedFileContext* = Table[ResolvedType, AnalyzedType]

proc update(fileCtx: var AnalyzedFileContext, resolved: ResolvedType, analyzed: AnalyzedType, loc: Location): Result[AnalyzedFileContext, string] =
  ## Same-identity re-insert (the same type imported under a second
  ## binding) is idempotent — keys hash by source location, so both
  ## bindings land here with an equal AnalyzedType. Only a genuinely
  ## different entry under an existing key is a conflict.
  if resolved in fileCtx and fileCtx[resolved] != analyzed:
    let prevDefLoc = fileCtx[resolved].loc
    return err(fmt"{loc} encountered duplicated type declaration, see previous declaration at {prevDefLoc}")
  fileCtx[resolved] = analyzed
  ok(fileCtx)

proc newAnalyzedFileContext*(imports: seq[AnalyzedImport], types: seq[AnalyzedType]): Result[AnalyzedFileContext, string] =
  var fileCtx: AnalyzedFileContext
  for imp in imports:
    for impType in imp.importedTypes:
      fileCtx = ? fileCtx.update(impType.typ.resolved, impType.typ, impType.loc)

  for typ in types:
    fileCtx = ? fileCtx.update(typ.resolved, typ, typ.loc)

  ok(fileCtx)

proc findType*(fileCtx: AnalyzedFileContext, resolved: ResolvedType, loc: Location): Result[AnalyzedType, string] =
  if resolved notin fileCtx:
    err(fmt"{loc} type `{resolved.name.asl}` does not exist in file")
  else:
    ok(fileCtx[resolved])

proc findModule*(fileCtx: AnalyzedFileContext, module: ResolvedModule, loc: Location): Result[AnalyzedDefModule, string] =
  let typ = ? fileCtx.findType(newResolvedType(module), loc)
  case typ.kind:
  of atkGeneric: err(fmt"{module.loc} module `{module.name.asl}` does not exist in file")
  of atkModule: ok(typ.module)

proc findGeneric*(fileCtx: AnalyzedFileContext, generic: ResolvedGeneric, loc: Location): Result[AnalyzedGeneric, string] =
  let typ = ? fileCtx.findType(newResolvedType(generic), loc)
  case typ.kind:
  of atkGeneric: ok(typ.generic)
  of atkModule: err(fmt"{generic.loc} generic `{generic.name.asl}` does not exist in file")
