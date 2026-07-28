## AnalyzedFileScope — per-file identity-keyed lookup (ResolvedType
## -> AnalyzedType), spanning imports + local defined types. Keys
## hash by source location, so the same type imported under two
## bindings (`import { Solver as First }` + `{ Solver as Second }`)
## lands on one key and aliased imports can never miss.
##
## Name resolution (user-typed name -> ResolvedType) happens at
## resolve time against the resolver's name-keyed FileScope — by the
## time the analyzer runs, every reference already carries its
## ResolvedType identity. Binding-name collisions are also caught
## there; construction here only rejects a genuinely different
## entry under an existing key (see `update`).

import results, strformat, tables

import ./defanalyzer
import ./importedtype
import ./imports

type AnalyzedFileScope* = Table[ResolvedType, AnalyzedType]

proc update(fileScope: var AnalyzedFileScope, resolved: ResolvedType, analyzed: AnalyzedType, loc: Location): Result[AnalyzedFileScope, string] =
  ## Same-identity re-insert (the same type imported under a second
  ## binding) is idempotent — keys hash by source location, so both
  ## bindings land here with an equal AnalyzedType. Only a genuinely
  ## different entry under an existing key is a conflict.
  if resolved in fileScope and fileScope[resolved] != analyzed:
    let prevDefLoc = fileScope[resolved].loc
    return err(fmt"{loc} encountered duplicated type declaration, see previous declaration at {prevDefLoc}")
  fileScope[resolved] = analyzed
  ok(fileScope)

proc newAnalyzedFileScope*(imports: seq[AnalyzedImport], types: seq[AnalyzedType]): Result[AnalyzedFileScope, string] =
  var fileScope: AnalyzedFileScope
  for imp in imports:
    for impType in imp.importedTypes:
      fileScope = ? fileScope.update(impType.typ.resolved, impType.typ, impType.loc)

  for typ in types:
    fileScope = ? fileScope.update(typ.resolved, typ, typ.loc)

  ok(fileScope)

proc findType*(fileScope: AnalyzedFileScope, resolved: ResolvedType, loc: Location): Result[AnalyzedType, string] =
  if resolved notin fileScope:
    err(fmt"{loc} type `{resolved.name.asl}` does not exist in file")
  else:
    ok(fileScope[resolved])

proc findModule*(fileScope: AnalyzedFileScope, module: ResolvedModule, loc: Location): Result[AnalyzedDefModule, string] =
  let typ = ? fileScope.findType(newResolvedType(module), loc)
  case typ.kind:
  of atkGeneric: err(fmt"{module.loc} module `{module.name.asl}` does not exist in file")
  of atkModule: ok(typ.module)

proc findGeneric*(fileScope: AnalyzedFileScope, generic: ResolvedGeneric, loc: Location): Result[AnalyzedGeneric, string] =
  let typ = ? fileScope.findType(newResolvedType(generic), loc)
  case typ.kind:
  of atkGeneric: ok(typ.generic)
  of atkModule: err(fmt"{generic.loc} generic `{generic.name.asl}` does not exist in file")
