## ResolvedFileScope — Identifier (binding name) -> ResolvedType.
##
## Doubles as the defined-type lookup scope for the body walker:
## imports contribute per-binding entries, and the file's local
## defined types are inserted at the analyzer entry point. Pure type
## alias; no procs of its own (`findType` / `findModuleDef` /
## `extractDataDef` / `extractStructFor` / `extractUnionFor` live on
## the analyzer facade because they thread the resolver types too).

import results, strformat, tables

import ./resolver
import ./importdef
import ./importedtype

type ResolvedFileScope* = Table[Identifier, ResolvedType]

proc update(fileScope: var ResolvedFileScope, name: Identifier, typ: ResolvedType): Result[ResolvedFileScope, string] =
  if name in fileScope:
    let loc = fileScope[name].loc
    return err(fmt"{name.loc} encountered duplicated type declaration, see previous declaration at {loc}")
  else:
    fileScope[name] = typ
    ok(fileScope)

proc newResolvedFileScope*(imports: seq[AnalyzedImportDefinition], types: seq[ResolvedType]): Result[ResolvedFileScope, string] =
  var fileScope: ResolvedFileScope
  for imp in imports:
    for impType in imp.importedTypes:
      fileScope = ? fileScope.update(impType.binding, impType.typ)

  for typ in types:
    fileScope = ? fileScope.update(typ.name, typ)

  ok(fileScope)