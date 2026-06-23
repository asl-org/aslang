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

# TODO(import-shorthand): dispatch on `imp.kind` here once the
# tagged-union Import lands (W2).
#   - ikExplicit: keep the existing loop below.
#   - ikShorthand: walk `impFile.publicTypes()`, synthesize a
#     parser-side ImportedType per public type via
#     `newImportedType(definedType.name, none(Identifier), imp.loc)`,
#     and feed each through the same resolveImportedType path (or
#     newResolvedImportedType directly since the public filter is
#     already applied). See W5.
#
# After expansion finishes for ALL imports in the file, run a
# resolver-stage collision check (likely co-located with file
# resolution in src/resolver/files.nim, since the check spans every
# import + every locally-defined type). Build a Table[Identifier,
# Location] keyed by binding; reject duplicates with "duplicate
# type declaration encountered, see previous declaration at <loc>"
# (mirror today's parser-side error from newFile). See W6.
proc resolveImport*(app: App, file: parser.File,
    imp: Import): Result[ResolvedImport, string] =
  let impFileId = ? app.findFileId(imp.path)
  let impFile = ? app.findFile(imp.path)
  var resolvedImportedTypes: seq[ResolvedImportedType]
  for impType in imp.names:
    let resolvedImportedType = ? resolveImportedType(impFile, impType)
    resolvedImportedTypes.add(resolvedImportedType)
  ok(newResolvedImport(imp, impFileId, impFile, resolvedImportedTypes))
