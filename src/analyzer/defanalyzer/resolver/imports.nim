## Import resolution. ResolvedImportedType is the LINKED binding for
## a single imported name: the (name, binding) pair plus the source
## file's resolved twin, captured at link time — topo order (BFS
## leaves-first) guarantees the source file resolved before its
## importer. The target parser LocalType is derived from the twin
## (`resolvedType.parsed`), never stored separately. ResolvedImport
## bundles the target file with the seq of resolved imported names.
## Both are used by the file scope built in decls.nim.

import parser
import types

# ResolvedImportedType
type ResolvedImportedType* = ref object
  parsed: ImportedType
  resolvedType: ResolvedLocalType

proc newResolvedImportedType*(parsed: ImportedType, resolvedType: ResolvedLocalType): ResolvedImportedType =
  ResolvedImportedType(parsed: parsed, resolvedType: resolvedType)

# TODO: Fix the location mess up for error reporting
proc newResolvedImportedType*(resolvedType: ResolvedLocalType): ResolvedImportedType =
  let parsed = newImportedType(resolvedType.name)
  ResolvedImportedType(parsed: parsed, resolvedType: resolvedType)

proc binding*(t: ResolvedImportedType): Identifier = t.parsed.binding
proc typ*(t: ResolvedImportedType): LocalType = t.resolvedType.parsed
proc resolvedType*(t: ResolvedImportedType): ResolvedLocalType = t.resolvedType

# ResolvedImport
type ResolvedImport* = ref object
  parsed: Import
  impFile: parser.File
  importedTypes: seq[ResolvedImportedType]

proc newResolvedImport*(parsed: Import, impFile: parser.File, importedTypes: seq[ResolvedImportedType]): ResolvedImport =
  ResolvedImport(parsed: parsed, impFile: impFile, importedTypes: importedTypes)

proc impFile*(i: ResolvedImport): parser.File = i.impFile
proc importedTypes*(i: ResolvedImport): seq[ResolvedImportedType] = i.importedTypes
