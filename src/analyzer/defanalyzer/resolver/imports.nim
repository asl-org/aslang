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
  localType: ResolvedLocalType

proc newResolvedImportedType*(parsed: ImportedType, localType: ResolvedLocalType): ResolvedImportedType =
  ResolvedImportedType(parsed: parsed, localType: localType)

# TODO: Fix the location mess up for error reporting
proc newResolvedImportedType*(localType: ResolvedLocalType): ResolvedImportedType =
  let parsed = newImportedType(localType.name)
  ResolvedImportedType(parsed: parsed, localType: localType)

proc binding*(t: ResolvedImportedType): Identifier = t.parsed.binding
proc typ*(t: ResolvedImportedType): LocalType = t.localType.parsed
proc localType*(t: ResolvedImportedType): ResolvedLocalType = t.localType

# ResolvedImport
type ResolvedImport* = ref object
  parsed: Import
  file: parser.File
  importedTypes: seq[ResolvedImportedType]

proc newResolvedImport*(parsed: Import, file: parser.File, importedTypes: seq[ResolvedImportedType]): ResolvedImport =
  ResolvedImport(parsed: parsed, file: file, importedTypes: importedTypes)

proc file*(i: ResolvedImport): parser.File = i.file
proc importedTypes*(i: ResolvedImport): seq[ResolvedImportedType] = i.importedTypes
