## Import resolution. ResolvedImportedType captures the (name,
## binding, target parser DefinedType) triple for a single imported
## name; ResolvedImport bundles the target file with the seq of
## resolved imported names. Both are used by the file scope built in
## decls.nim.

import results

import tokenizer
import parser

# ResolvedImportedType
type ResolvedImportedType* = ref object
  module: int
  name: Identifier
  binding: Identifier
  definedType: DefinedType

proc newResolvedImportedType*(module: int, name, binding: Identifier, definedType: DefinedType): ResolvedImportedType =
  ResolvedImportedType(module: module, name: name, binding: binding, definedType: definedType)

proc loc*(t: ResolvedImportedType): Location = t.binding.loc
proc binding*(t: ResolvedImportedType): Identifier = t.binding
proc definedType*(t: ResolvedImportedType): DefinedType = t.definedType

proc resolveImportedType(impFile: parser.File, impType: ImportedType): Result[
    ResolvedImportedType, string] =
  let importedAslTypeId = ? impFile.findExportedTypeId(impType.name)
  let importedAslType = ? impFile.findExportedType(impType.name)
  ok(newResolvedImportedType(importedAslTypeId, impType.name, impType.binding, importedAslType))

# ResolvedImport
type ResolvedImport* = ref object
  file: int
  parsed: parser.File
  importedTypes: seq[ResolvedImportedType]
  loc: Location

proc newResolvedImport*(file: int, parsed: parser.File, importedTypes: seq[ResolvedImportedType], loc: Location): ResolvedImport =
  ResolvedImport(file: file, parsed: parsed, importedTypes: importedTypes, loc: loc)

proc parsed*(i: ResolvedImport): parser.File = i.parsed
proc importedTypes*(i: ResolvedImport): seq[ResolvedImportedType] = i.importedTypes
proc loc*(i: ResolvedImport): Location = i.loc

proc resolveImport*(app: App, file: parser.File,
    imp: Import): Result[ResolvedImport, string] =
  let impFileId = ? app.findFileId(imp.path)
  let impFile = ? app.findFile(imp.path)
  var resolvedImportedTypes: seq[ResolvedImportedType]
  for impType in imp.names:
    let resolvedImportedType = ? resolveImportedType(impFile, impType)
    resolvedImportedTypes.add(resolvedImportedType)
  ok(newResolvedImport(impFileId, impFile, resolvedImportedTypes, imp.loc))
