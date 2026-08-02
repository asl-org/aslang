## ResolvedFileContext — per-file identity-keyed lookup (parser.Type
## -> ResolvedType), spanning imports + local defined types. Keys
## hash by source location, so the same type imported under two
## bindings (`import { Solver as First }` + `{ Solver as Second }`)
## lands on one key and aliased imports can never miss.
##
## Name resolution (user-typed name -> parser.Type) happens at
## resolve time against the resolver's name-keyed FileContext — by the
## time the analyzer runs, every reference already carries its
## parser.Type identity. Binding-name collisions are also caught
## there; construction here only rejects a genuinely different
## entry under an existing key (see `update`).

import results, strformat, tables

import ./resolver
import ./importdef
import ./importedtypedef

type ResolvedFileContext* = Table[parser.Type, ResolvedType]

proc update(fileCtx: var ResolvedFileContext, parsed: parser.Type, resolved: ResolvedType, loc: Location): Result[ResolvedFileContext, string] =
  ## Same-identity re-insert (the same type imported under a second
  ## binding) is idempotent — keys hash by source location, so both
  ## bindings land here with an equal ResolvedType. Only a genuinely
  ## different entry under an existing key is a conflict.
  if parsed in fileCtx and fileCtx[parsed] != resolved:
    let prevDefLoc = fileCtx[parsed].loc
    return err(fmt"{loc} encountered duplicated type declaration, see previous declaration at {prevDefLoc}")
  fileCtx[parsed] = resolved
  ok(fileCtx)

proc newResolvedFileContext*(imports: seq[AnalyzedDefImport], types: seq[ResolvedType]): Result[ResolvedFileContext, string] =
  var fileCtx: ResolvedFileContext
  for imp in imports:
    for impType in imp.importedTypes:
      fileCtx = ? fileCtx.update(impType.typ.parsed, impType.typ, impType.loc)

  for typ in types:
    fileCtx = ? fileCtx.update(typ.parsed, typ, typ.loc)

  ok(fileCtx)

proc findType*(fileCtx: ResolvedFileContext, parsed: parser.Type, loc: Location): Result[ResolvedType, string] =
  if parsed notin fileCtx:
    err(fmt"{loc} type `{parsed.name.asl}` does not exist in file")
  else:
    ok(fileCtx[parsed])

proc findModule*(fileCtx: ResolvedFileContext, module: Module, loc: Location): Result[ResolvedModule, string] =
  let typ = ? fileCtx.findType(newType(module), loc)
  case typ.kind:
  of rtkGeneric: err(fmt"{module.loc} module `{module.name.asl}` does not exist in file")
  of rtkModule: ok(typ.module)

proc findGeneric*(fileCtx: ResolvedFileContext, generic: Generic, loc: Location): Result[ResolvedGeneric, string] =
  let typ = ? fileCtx.findType(newType(generic), loc)
  case typ.kind:
  of rtkGeneric: ok(typ.generic)
  of rtkModule: err(fmt"{generic.loc} generic `{generic.name.asl}` does not exist in file")
