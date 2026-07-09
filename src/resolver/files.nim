## Type / File / App + the public resolve* entry point.

import results, strformat, tables

import ./parser
import argtypes, modules
import imports

# ResolvedFile
type ResolvedFile* = ref object
  id: int
  parsed: parser.File
  imports: seq[ResolvedImport]
  types: seq[ResolvedType]
  typeIndex: Table[Identifier, int]

proc newResolvedFile*(id: int, parsed: parser.File, imports: seq[ResolvedImport], types: seq[ResolvedType]): ResolvedFile =
  var typeIndex: Table[Identifier, int]
  for id, definedType in types:
    typeIndex[definedType.name] = id
  ResolvedFile(id: id, parsed: parsed, imports: imports, types: types, typeIndex: typeIndex)

proc path*(file: ResolvedFile): string = file.parsed.path
proc parsed*(file: ResolvedFile): parser.File = file.parsed
proc imports*(file: ResolvedFile): seq[ResolvedImport] = file.imports
proc types*(file: ResolvedFile): seq[ResolvedType] = file.types

proc findType*(file: ResolvedFile, name: Identifier): Result[ResolvedType, string] =
  if name notin file.typeIndex:
    err(fmt"{name.loc} type `{name.asl}` does not exist in the file scope")
  else:
    ok(file.types[file.typeIndex[name]])

proc findModule*(file: ResolvedFile, name: Identifier): Result[ResolvedModule, string] =
  let definedType = ? file.findType(name)
  case definedType.kind:
  of rdtkModule: ok(definedType.module)
  of rdtkGeneric: err(fmt"{name.loc} expected type `{name.asl}` to be a module but found generic")

proc findGeneric*(file: ResolvedFile, name: Identifier): Result[ResolvedGeneric, string] =
  let definedType = ? file.findType(name)
  case definedType.kind:
  of rdtkGeneric: ok(definedType.generic)
  of rdtkModule: err(fmt"{name.loc} expected type `{name.asl}` to be a generic but found module")

proc validateNoDuplicateBindings(resolvedImports: seq[ResolvedImport], file: parser.File): Result[void, string] =
  ## Catches collisions involving shorthand-expanded names: shorthand
  ## vs locally-defined type, shorthand vs explicit, and shorthand vs
  ## shorthand. Explicit-vs-explicit and explicit-vs-local already
  ## fire in `newFile` at parser time; this check re-runs them on the
  ## resolved view so the error format stays uniform.
  var seen: Table[Identifier, Location]
  for resolvedImport in resolvedImports:
    for impType in resolvedImport.importedTypes:
      if impType.binding in seen:
        return err(fmt"{impType.loc} duplicate type declaration encountered, see previous declaration at {seen[impType.binding]}")
      seen[impType.binding] = impType.loc
  for definedType in file.types:
    if definedType.name in seen:
      return err(fmt"{definedType.loc} duplicate type declaration encountered, see previous declaration at {seen[definedType.name]}")
    seen[definedType.name] = definedType.loc
  ok()

proc resolveFile*(app: App, id: int, file: parser.File): Result[ResolvedFile, string] =
  var resolvedImports: seq[ResolvedImport]
  var fileScope: FileScope
  case file.kind:
  of fkAsl:
    for imp in file.imports:
      let resolvedImport = ? resolveImport(app, file, imp)
      resolvedImports.add(resolvedImport)
      for impType in resolvedImport.importedTypes:
        fileScope[impType.binding] = impType.definedType
  of fkAslr: discard

  ? validateNoDuplicateBindings(resolvedImports, file)

  var resolvedTypes: seq[ResolvedType]
  for id, definedType in file.types:
    let resolvedType = ? resolveType(app, file, fileScope, id, definedType)
    resolvedTypes.add(resolvedType)

  ok(newResolvedFile(id, file, resolvedImports, resolvedTypes))
