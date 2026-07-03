## DefinedType / File / App + the public resolve* entry point.

import results, strformat, tables

import tokenizer
import parser
import domain
import imports

# ResolvedFile
type ResolvedFile* = ref object
  id: int
  parsed: parser.File
  imports: seq[ResolvedImport]
  definedTypes: seq[ResolvedDefinedType]
  definedTypeIndex: Table[Identifier, int]

proc newResolvedFile*(id: int, parsed: parser.File, imports: seq[ResolvedImport], definedTypes: seq[ResolvedDefinedType]): ResolvedFile =
  var definedTypeIndex: Table[Identifier, int]
  for id, definedType in definedTypes:
    definedTypeIndex[definedType.name] = id
  ResolvedFile(id: id, parsed: parsed, imports: imports, definedTypes: definedTypes, definedTypeIndex: definedTypeIndex)

proc path*(file: ResolvedFile): string = file.parsed.path
proc parsed*(file: ResolvedFile): parser.File = file.parsed
proc imports*(file: ResolvedFile): seq[ResolvedImport] = file.imports
proc definedTypes*(file: ResolvedFile): seq[ResolvedDefinedType] = file.definedTypes

proc findDefinedType*(file: ResolvedFile, name: Identifier): Result[ResolvedDefinedType, string] =
  if name notin file.definedTypeIndex:
    err(fmt"{name.loc} type `{name.asl}` does not exist in the file scope")
  else:
    ok(file.definedTypes[file.definedTypeIndex[name]])

proc findModule*(file: ResolvedFile, name: Identifier): Result[ResolvedModule, string] =
  let definedType = ? file.findDefinedType(name)
  case definedType.kind:
  of rdtkModule: ok(definedType.module)
  of rdtkGeneric: err(fmt"{name.loc} expected type `{name.asl}` to be a module but found generic")

proc findGeneric*(file: ResolvedFile, name: Identifier): Result[ResolvedGeneric, string] =
  let definedType = ? file.findDefinedType(name)
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
  for definedType in file.definedTypes:
    if definedType.name in seen:
      return err(fmt"{definedType.loc} duplicate type declaration encountered, see previous declaration at {seen[definedType.name]}")
    seen[definedType.name] = definedType.loc
  ok()

proc resolveFile*(app: App, shells: ResolvedModuleShells, id: int, file: parser.File): Result[ResolvedFile, string] =
  var resolvedImports: seq[ResolvedImport]
  var fileScope: FileScope
  if file.kind == fkAsl:
    for imp in file.imports:
      let resolvedImport = ? resolveImport(app, file, imp)
      resolvedImports.add(resolvedImport)
      for impType in resolvedImport.importedTypes:
        fileScope[impType.binding] = impType.definedType

  ? validateNoDuplicateBindings(resolvedImports, file)

  var resolvedDefinedTypes: seq[ResolvedDefinedType]
  for id, definedType in file.definedTypes:
    let resolvedDefinedType = ? resolveDefinedType(app, shells, file, fileScope, id, definedType)
    resolvedDefinedTypes.add(resolvedDefinedType)

  ok(newResolvedFile(id, file, resolvedImports, resolvedDefinedTypes))
