## Import resolution. ResolvedImportedType captures the (name,
## binding, target parser DefinedType) triple for a single imported
## name; ResolvedImport bundles the target file with the seq of
## resolved imported names. Both are used by the file scope built in
## decls.nim.

import results

import parser

# ResolvedImportedType
type ResolvedImportedType* = ref object
  module: int
  name: Identifier
  binding: Identifier
  aslType: DefinedType

proc newResolvedImportedType*(module: int, name, binding: Identifier, aslType: DefinedType): ResolvedImportedType =
  ResolvedImportedType(module: module, name: name, binding: binding, aslType: aslType)

proc binding*(t: ResolvedImportedType): Identifier = t.binding
proc aslType*(t: ResolvedImportedType): DefinedType = t.aslType

proc resolveImportedType(impFile: parser.File, impType: ImportedType): Result[
    ResolvedImportedType, string] =
  let importedAslTypeId = ? impFile.findExportedTypeId(impType.name)
  let importedAslType = ? impFile.findExportedType(impType.name)
  ok(newResolvedImportedType(importedAslTypeId, impType.name, impType.binding, importedAslType))

# ResolvedImport
type ResolvedImport* = ref object
  file: int
  source: parser.File
  importedTypes: seq[ResolvedImportedType]

proc newResolvedImport*(file: int, source: parser.File,
    importedTypes: seq[ResolvedImportedType]): ResolvedImport =
  ResolvedImport(file: file, source: source, importedTypes: importedTypes)

proc importedTypes*(i: ResolvedImport): seq[ResolvedImportedType] =
  i.importedTypes

proc resolveImport*(app: App, file: parser.File,
    imp: Import): Result[ResolvedImport, string] =
  let impFileId = ? app.findFileId(imp.path)
  let impFile = ? app.findFile(imp.path)
  var resolvedImportedTypes: seq[ResolvedImportedType]
  for impType in imp.names:
    let resolvedImportedType = ? resolveImportedType(impFile, impType)
    resolvedImportedTypes.add(resolvedImportedType)
  ok(newResolvedImport(impFileId, impFile, resolvedImportedTypes))
