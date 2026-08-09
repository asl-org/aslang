## Resolution contexts — `FileContext` (per-file name→scope-entry table
## threaded through every scope-consuming `resolve*` proc) and
## `TypeContext` (the enclosing definition context — module | generic —
## carried so visibility and constraint satisfaction can be decided at
## the site that needs them).

import results, strformat, hashes, tables

import parser
import imports
import argtype
import types

# ============================================================
# FileContext
# ============================================================
# The name -> scope-entry table populated by resolver/imports.nim. The
# entry type `Type` is the Local | Imported union: a name resolves
# either to a type declared in this file or to the LINKED import
# binding, which carries the source file's LocalType.

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
  of tkImported: t.imported.typ

proc loc*(t: Type): Location = t.localType.loc
proc hash*(t: Type): Hash = t.localType.hash
proc `==`*(a, b: Type): bool = a.localType == b.localType

type FileContext* = ref object
  parsed: parser.File
  imports: seq[ResolvedImport]
  localTypes: seq[ResolvedLocalType]
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
  ok(fileCtx)

proc add*(fileCtx: FileContext, localType: ResolvedLocalType): Result[FileContext, string] =
  fileCtx.localTypes.add(localType)
  ok(fileCtx)

proc findType*(fileCtx: FileContext, name: Identifier): Result[Type, string] =
  if name in fileCtx.typeIndex: ok(fileCtx.typeIndex[name])
  else: err(fmt"{name.loc} type `{name.asl}` does not exist in the scope")

proc findModule*(fileCtx: FileContext, name: Identifier): Result[Module, string] =
  let initType = (? fileCtx.findType(name)).localType
  case initType.kind:
  of ltkGeneric: err(fmt"{name.loc} type `{name.asl}` is a generic and not a module")
  of ltkModule: ok(initType.module)

proc findGeneric*(fileCtx: FileContext, name: Identifier): Result[Generic, string] =
  let initType = (? fileCtx.findType(name)).localType
  case initType.kind:
  of ltkModule: err(fmt"{name.loc} type `{name.asl}` is a module but expected generic")
  of ltkGeneric: ok(initType.generic)

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
