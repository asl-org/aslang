## Resolution contexts — `FileContext` (per-file name→scope-entry table
## threaded through every scope-consuming `resolve*` proc) and
## `TypeContext` (the enclosing definition context — module | generic —
## carried so visibility and constraint satisfaction can be decided at
## the site that needs them).

import results, sequtils, strformat, hashes, tables

import parser
import imports
import types

# ============================================================
# FileContext
# ============================================================
# Per-file resolver scope: the name -> scope-entry table (`Type`, the
# Local | Imported union defined in imports.nim) plus the file's
# resolved imports and local types with an identity index — populated
# by `insert` / `add` as the resolver walks the file. A `Type` entry
# resolves either to a type declared in this file or to a LINKED import
# binding carrying the source file's LocalType. ResolvedFile (app.nim)
# wraps a FileContext and delegates to it.

type FileContext* = ref object
  parsed: parser.File
  imports: seq[ResolvedImport]
  importedTypeIndex: Table[LocalType, ResolvedLocalType]
  localTypes: seq[ResolvedLocalType]
  localTypeIndex: Table[LocalType, int]
  typeIndex: Table[Identifier, Type]

proc insert(fileCtx: FileContext, name: Identifier, typ: Type): Result[FileContext, string] =
  if name in fileCtx.typeIndex:
    let loc = fileCtx.typeIndex[name].loc
    err(fmt"{name.loc} duplicate type declaration encountered, see previous declaration at {loc}")
  else:
    fileCtx.typeIndex[name] = typ
    ok(fileCtx)

proc newFileContext*(parsed: parser.File): Result[FileContext, string] =
  var fileCtx = FileContext(parsed: parsed)
  for typ in parsed.types:
    fileCtx = ? fileCtx.insert(typ.name, newType(typ))
  ok(fileCtx)

proc add*(fileCtx: FileContext, imp: ResolvedImport): Result[FileContext, string] =
  fileCtx.imports.add(imp)
  for impType in imp.importedTypes:
    discard ? fileCtx.insert(impType.binding, newType(impType))
    fileCtx.importedTypeIndex[impType.localType.parsed] = impType.localType
  ok(fileCtx)

proc add*(fileCtx: FileContext, localType: ResolvedLocalType): Result[FileContext, string] =
  fileCtx.localTypeIndex[localType.parsed] = fileCtx.localTypes.len
  fileCtx.localTypes.add(localType)
  ok(fileCtx)

proc findLocalType*(fileCtx: FileContext, name: Identifier): Result[LocalType, string] =
  if name in fileCtx.typeIndex: ok(fileCtx.typeIndex[name].localType)
  else: err(fmt"{name.loc} type `{name.asl}` does not exist in the scope")

proc findModule*(fileCtx: FileContext, name: Identifier): Result[Module, string] =
  let initType = ? fileCtx.findLocalType(name)
  case initType.kind:
  of ltkGeneric: err(fmt"{name.loc} type `{name.asl}` is a generic and not a module")
  of ltkModule: ok(initType.module)

proc findGeneric*(fileCtx: FileContext, name: Identifier): Result[Generic, string] =
  let initType = ? fileCtx.findLocalType(name)
  case initType.kind:
  of ltkModule: err(fmt"{name.loc} type `{name.asl}` is a module but expected generic")
  of ltkGeneric: ok(initType.generic)

proc path*(fileCtx: FileContext): string = fileCtx.parsed.path
proc parsed*(fileCtx: FileContext): parser.File = fileCtx.parsed
proc imports*(fileCtx: FileContext): seq[ResolvedImport] = fileCtx.imports

proc modules*(fileCtx: FileContext): seq[ResolvedModule] =
  fileCtx.localTypes.filterIt(it.kind == rltkModule).mapIt(it.module)
proc exportedTypes*(fileCtx: FileContext): seq[ResolvedImportedType] =
  fileCtx.localTypes.filterIt(it.public).mapIt(newResolvedImportedType(it))
proc localTypes*(fileCtx: FileContext): seq[ResolvedLocalType] = fileCtx.localTypes
proc importedBindings*(fileCtx: FileContext): seq[ResolvedImportedType] =
  for imp in fileCtx.imports:
    result.add(imp.importedTypes)

proc findLocalType*(fileCtx: FileContext, localType: LocalType): ResolvedLocalType =
  assert(localType in fileCtx.localTypeIndex, fmt"[BUG] - {localType.loc} type `{localType.name.asl}` missing from the resolved file")
  fileCtx.localTypes[fileCtx.localTypeIndex[localType]]

proc findModule*(fileCtx: FileContext, typ: Module): ResolvedModule =
  let resolvedLocalType = fileCtx.findLocalType(newLocalType(typ))
  assert(resolvedLocalType.kind == rltkModule, fmt"[BUG] - {typ.loc} `{typ.name.asl}` was bound as a module by the resolver")
  resolvedLocalType.module

proc findGeneric*(fileCtx: FileContext, typ: Generic): ResolvedGeneric =
  let resolvedLocalType = fileCtx.findLocalType(newLocalType(typ))
  assert(resolvedLocalType.kind == rltkGeneric, fmt"[BUG] - {typ.loc} `{typ.name.asl}` was bound as a generic by the resolver")
  resolvedLocalType.generic

proc findExportedType*(fileCtx: FileContext, importedType: ImportedType): Result[ResolvedImportedType, string] =
  let localType = ? fileCtx.parsed.findExportedType(importedType.name)
  let resolvedLocalType = fileCtx.findLocalType(localType)
  ok(newResolvedImportedType(importedType, resolvedLocalType))

proc findGenericInScope*(fileCtx: FileContext, generic: Generic): ResolvedGeneric =
  let localType = newLocalType(generic)
  let resolvedLocalType =
    if localType in fileCtx.localTypeIndex:
      fileCtx.localTypes[fileCtx.localTypeIndex[localType]]
    else:
      fileCtx.importedTypeIndex[localType]

  resolvedLocalType.generic


# ============================================================
# TypeContext
# ============================================================
# The definition context a type reference appears in: the enclosing
# module or generic block. Carried through resolution so visibility can
# be decided at the site that needs it (a non-public function is
# accessible only from inside its own module; generics see public only)
# and so constraint satisfaction can consult it.

type
  TypeContextKind* = enum
    tckModule, tckGeneric

  TypeContext* = ref object
    case kind: TypeContextKind
    of tckModule: module: Module
    of tckGeneric: generic: Generic

proc newTypeContext*(module: Module): TypeContext =
  TypeContext(kind: tckModule, module: module)

proc newTypeContext*(generic: Generic): TypeContext =
  TypeContext(kind: tckGeneric, generic: generic)

proc kind*(typeCtx: TypeContext): TypeContextKind = typeCtx.kind

proc module*(typeCtx: TypeContext): Module =
  assert typeCtx.kind == tckModule,
    "TypeContext.module accessed but kind is tckGeneric"
  typeCtx.module

proc generic*(typeCtx: TypeContext): Generic =
  assert typeCtx.kind == tckGeneric,
    "TypeContext.generic accessed but kind is tckModule"
  typeCtx.generic

proc access*(typeCtx: TypeContext, module: Module): FunctionAccess =
  ## Which functions of `module` this context may see.
  case typeCtx.kind:
  of tckGeneric:
    faPublic
  of tckModule:
    if typeCtx.module == module: faAll else: faPublic
