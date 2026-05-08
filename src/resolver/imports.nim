## Import resolution. ResolvedImportedType captures the (name,
## binding, target DefinedType) triple for a single imported name;
## ResolvedImport bundles the target file with the seq of resolved
## imported names. Both are used by the file scope built in decls.nim.

import results

import parser

# ResolvedImportedType
type ResolvedImportedType* = ref object
  name: Identifier
  binding: Identifier
  definedType: DefinedType

proc newResolvedImportedType*(name, binding: Identifier,
    definedType: DefinedType): ResolvedImportedType =
  ResolvedImportedType(name: name, binding: binding, definedType: definedType)

proc binding*(t: ResolvedImportedType): Identifier = t.binding
proc definedType*(t: ResolvedImportedType): DefinedType = t.definedType

proc resolveImportedType(impFile: parser.File, impType: ImportedType): Result[
    ResolvedImportedType, string] =
  let importedDefinedType = ? impFile.findExportedType(impType.name)
  ok(newResolvedImportedType(impType.name, impType.binding,
    importedDefinedType))

# ResolvedImport
type ResolvedImport* = ref object
  source: parser.File
  importedTypes: seq[ResolvedImportedType]

proc newResolvedImport*(source: parser.File,
    importedTypes: seq[ResolvedImportedType]): ResolvedImport =
  ResolvedImport(source: source, importedTypes: importedTypes)

proc importedTypes*(i: ResolvedImport): seq[ResolvedImportedType] =
  i.importedTypes

proc resolveImport*(app: App, file: parser.File,
    imp: Import): Result[ResolvedImport, string] =
  let impFile = ? app.findFile(imp.path)
  var resolvedImportedTypes: seq[ResolvedImportedType]
  for impType in imp.names:
    let resolvedImportedType = ? resolveImportedType(impFile, impType)
    resolvedImportedTypes.add(resolvedImportedType)
  ok(newResolvedImport(impFile, resolvedImportedTypes))
