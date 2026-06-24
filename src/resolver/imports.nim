## Import resolution. ResolvedImportedType captures the (name,
## binding, target parser DefinedType) triple for a single imported
## name; ResolvedImport bundles the target file with the seq of
## resolved imported names. Both are used by the file scope built in
## decls.nim.

import options, results

import tokenizer
import parser

# ResolvedImportedType
type ResolvedImportedType* = ref object
  parsed: ImportedType
  definedType: DefinedType

proc newResolvedImportedType*(parsed: ImportedType, definedType: DefinedType): ResolvedImportedType =
  ResolvedImportedType(parsed: parsed, definedType: definedType)

proc parsed*(t: ResolvedImportedType): ImportedType = t.parsed
proc name*(t: ResolvedImportedType): Identifier = t.parsed.name
proc binding*(t: ResolvedImportedType): Identifier = t.parsed.binding
proc loc*(t: ResolvedImportedType): Location = t.parsed.binding.loc
proc definedType*(t: ResolvedImportedType): DefinedType = t.definedType

proc resolveImportedType(impFile: parser.File, impType: ImportedType): Result[
    ResolvedImportedType, string] =
  let importedAslType = ? impFile.findExportedType(impType.name)
  ok(newResolvedImportedType(impType, importedAslType))

# ResolvedImport
type ResolvedImport* = ref object
  parsed: Import
  file: int
  impFile: parser.File
  importedTypes: seq[ResolvedImportedType]

proc newResolvedImport*(parsed: Import, file: int, impFile: parser.File, importedTypes: seq[ResolvedImportedType]): ResolvedImport =
  ResolvedImport(parsed: parsed, file: file, impFile: impFile, importedTypes: importedTypes)

proc parsed*(i: ResolvedImport): Import = i.parsed
proc impFile*(i: ResolvedImport): parser.File = i.impFile
proc importedTypes*(i: ResolvedImport): seq[ResolvedImportedType] = i.importedTypes
proc loc*(i: ResolvedImport): Location = i.parsed.loc

proc resolveImport*(app: App, file: parser.File,
    imp: Import): Result[ResolvedImport, string] =
  let impFileId = ? app.findFileId(imp.absPath)
  let impFile = ? app.findFile(imp.absPath)
  var resolvedImportedTypes: seq[ResolvedImportedType]
  case imp.kind:
  of ikExplicit:
    for impType in imp.names:
      let resolvedImportedType = ? resolveImportedType(impFile, impType)
      resolvedImportedTypes.add(resolvedImportedType)
  of ikShorthand:
    # Expand the shorthand into the target file's full public set.
    # The public filter is already applied by `publicTypes()`, so we
    # build the ResolvedImportedType directly without re-running
    # `findExportedType`. Synthesize a parser-side ImportedType per
    # public type so the back-ref invariant on ResolvedImportedType
    # is preserved; the synthesized ImportedType uses the import
    # statement's location for diagnostics.
    for definedType in impFile.publicTypes:
      let synthesized = newImportedType(definedType.name, none(Identifier), imp.loc)
      resolvedImportedTypes.add(newResolvedImportedType(synthesized, definedType))
  ok(newResolvedImport(imp, impFileId, impFile, resolvedImportedTypes))
