## ResolvedFileScope — per-file identity-keyed lookup (parser.Type
## -> ResolvedType), spanning imports + local defined types. Keys
## hash by source location, so the same type imported under two
## bindings (`import { Solver as First }` + `{ Solver as Second }`)
## lands on one key and aliased imports can never miss.
##
## Name resolution (user-typed name -> parser.Type) happens at
## resolve time against the resolver's name-keyed FileScope — by the
## time the analyzer runs, every reference already carries its
## parser.Type identity. Binding-name collisions are also caught
## there; construction here only rejects a genuinely different
## entry under an existing key (see `update`).

import results, strformat, tables

import ./resolver
import ./importdef
import ./importedtypedef

type ResolvedFileScope* = Table[parser.Type, ResolvedType]

proc update(fileScope: var ResolvedFileScope, parsed: parser.Type, resolved: ResolvedType, loc: Location): Result[ResolvedFileScope, string] =
  ## Same-identity re-insert (the same type imported under a second
  ## binding) is idempotent — keys hash by source location, so both
  ## bindings land here with an equal ResolvedType. Only a genuinely
  ## different entry under an existing key is a conflict.
  if parsed in fileScope and fileScope[parsed] != resolved:
    let prevDefLoc = fileScope[parsed].loc
    return err(fmt"{loc} encountered duplicated type declaration, see previous declaration at {prevDefLoc}")
  fileScope[parsed] = resolved
  ok(fileScope)

proc newResolvedFileScope*(imports: seq[AnalyzedImportDefinition], types: seq[ResolvedType]): Result[ResolvedFileScope, string] =
  var fileScope: ResolvedFileScope
  for imp in imports:
    for impType in imp.importedTypes:
      fileScope = ? fileScope.update(impType.typ.parsed, impType.typ, impType.loc)

  for typ in types:
    fileScope = ? fileScope.update(typ.parsed, typ, typ.loc)

  ok(fileScope)

proc findType*(fileScope: ResolvedFileScope, parsed: parser.Type, loc: Location): Result[ResolvedType, string] =
  if parsed notin fileScope:
    err(fmt"{loc} type `{parsed.name.asl}` does not exist in file")
  else:
    ok(fileScope[parsed])

proc findModule*(fileScope: ResolvedFileScope, module: Module, loc: Location): Result[ResolvedModule, string] =
  let typ = ? fileScope.findType(newType(module), loc)
  case typ.kind:
  of rtkGeneric: err(fmt"{module.loc} module `{module.name.asl}` does not exist in file")
  of rtkModule: ok(typ.module)

proc findGeneric*(fileScope: ResolvedFileScope, generic: Generic, loc: Location): Result[ResolvedGeneric, string] =
  let typ = ? fileScope.findType(newType(generic), loc)
  case typ.kind:
  of rtkGeneric: ok(typ.generic)
  of rtkModule: err(fmt"{generic.loc} generic `{generic.name.asl}` does not exist in file")
