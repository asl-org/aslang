## Import resolution + the file-scope entry type. ResolvedImportedType
## is the LINKED binding for a single imported name: the (name, binding)
## pair plus the source file's resolved twin, captured at link time —
## topo order (BFS leaves-first) guarantees the source file resolved
## before its importer. The target parser LocalType is derived from the
## twin (`localType.parsed`), never stored separately. ResolvedImport
## bundles the target file with the seq of resolved imported names. This
## file also owns `Type`, the Local | Imported scope entry the
## ResolvedFile (app.nim) keys its name table on.
import hashes

import ../parser/index as parser
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

type
  TypeKind* = enum
    tkLocal, tkImported
  Type* = ref object
    ## Scope entry — what a name resolves to. Hashes and compares by
    ## the underlying LocalType so aliased imports land on one
    ## identity key; provenance is payload, not identity.
    case kind: TypeKind
    of tkLocal: local: LocalType
    of tkImported: imported: ResolvedImportedType

proc newType*(local: LocalType): Type =
  Type(kind: tkLocal, local: local)

proc newType*(imported: ResolvedImportedType): Type =
  Type(kind: tkImported, imported: imported)

proc kind*(t: Type): TypeKind = t.kind

proc local*(t: Type): LocalType =
  assert t.kind == tkLocal, "Type.local accessed but kind is tkImported"
  t.local

proc imported*(t: Type): ResolvedImportedType =
  assert t.kind == tkImported, "Type.imported accessed but kind is tkLocal"
  t.imported

proc localType*(t: Type): LocalType =
  ## The underlying declared type, regardless of provenance — what
  ## every consumer that only cares about the definition shape reads.
  case t.kind:
  of tkLocal: t.local
  of tkImported: t.imported.localType.parsed

proc loc*(t: Type): Location = t.localType.loc
proc hash*(t: Type): Hash = t.localType.hash
proc `==`*(a, b: Type): bool = a.localType == b.localType

