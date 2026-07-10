## Import resolution. ResolvedImportedType captures the (name,
## binding, target parser Type) triple for a single imported
## name; ResolvedImport bundles the target file with the seq of
## resolved imported names. Both are used by the file scope built in
## decls.nim.

import options, results

import ./parser

# ResolvedImportedType
type ResolvedImportedType* = ref object
  parsed: ImportedType
  typ: Type

proc newResolvedImportedType*(parsed: ImportedType, typ: Type): ResolvedImportedType =
  ResolvedImportedType(parsed: parsed, typ: typ)

proc parsed*(t: ResolvedImportedType): ImportedType = t.parsed
proc name*(t: ResolvedImportedType): Identifier = t.parsed.name
proc binding*(t: ResolvedImportedType): Identifier = t.parsed.binding
proc loc*(t: ResolvedImportedType): Location = t.parsed.binding.loc
proc typ*(t: ResolvedImportedType): Type = t.typ

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
    for typ in impFile.publicTypes:
      let synthesized = newImportedType(typ.name, none(Identifier), imp.loc)
      resolvedImportedTypes.add(newResolvedImportedType(synthesized, typ))
  ok(newResolvedImport(imp, impFileId, impFile, resolvedImportedTypes))
