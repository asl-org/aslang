## Import resolution. ResolvedImportedType captures the (name,
## binding, target parser Type) triple for a single imported
## name; ResolvedImport bundles the target file with the seq of
## resolved imported names. Both are used by the file scope built in
## decls.nim.

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

# ResolvedImport
type ResolvedImport* = ref object
  parsed: Import
  impFile: parser.File
  importedTypes: seq[ResolvedImportedType]

proc newResolvedImport*(parsed: Import, impFile: parser.File, importedTypes: seq[ResolvedImportedType]): ResolvedImport =
  ResolvedImport(parsed: parsed, impFile: impFile, importedTypes: importedTypes)

proc parsed*(i: ResolvedImport): Import = i.parsed
proc impFile*(i: ResolvedImport): parser.File = i.impFile
proc importedTypes*(i: ResolvedImport): seq[ResolvedImportedType] = i.importedTypes
proc loc*(i: ResolvedImport): Location = i.parsed.loc
