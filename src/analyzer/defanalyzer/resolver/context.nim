## Resolution contexts — `FileContext` (per-file name→scope-entry table
## threaded through every scope-consuming `resolve*` proc) and
## `TypeContext` (the enclosing definition context — module | generic —
## carried so visibility and constraint satisfaction can be decided at
## the site that needs them).

import results, sequtils, sets, strformat, hashes, tables

import parser
import imports
import argtype

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

type FileContext* = Table[Identifier, Type]

proc insert(fileCtx: var FileContext, name: Identifier, typ: Type): Result[FileContext, string] =
  if name in fileCtx:
    let loc = fileCtx[name].loc
    err(fmt"{name.loc} duplicate type declaration encountered, see previous declaration at {loc}")
  else:
    fileCtx[name] = typ
    ok(fileCtx)

proc newFileContext*(imports: seq[ResolvedImport], types: seq[LocalType]): Result[FileContext, string] =
  var fileCtx: FileContext
  for imp in imports:
    for impType in imp.importedTypes:
      fileCtx = ? fileCtx.insert(impType.binding, newType(impType))
  for typ in types:
    fileCtx = ? fileCtx.insert(typ.name, newType(typ))
  ok(fileCtx)

proc findType*(fileCtx: FileContext, name: Identifier): Result[Type, string] =
  if name in fileCtx: ok(fileCtx[name])
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

proc requiredGenerics(fileCtx: FileContext, struct: StructDef): Result[seq[Generic], string] =
  var requiredGenerics: seq[Generic]
  for generic in struct.header.requires:
    let foundGeneric = ? fileCtx.findGeneric(generic)
    requiredGenerics.add(foundGeneric)
  ok(requiredGenerics)

proc inferGenerics(fileCtx: FileContext, fields: seq[ArgumentDef]): Result[seq[Generic], string] =
  ## First-seen dedup (OrderedSet preserves insertion order): repeated
  ## generic fields claim ONE require slot, matching the resolved side
  ## (`ResolvedStructDef.generics`) and the union overload below —
  ## use sites supply one impl per distinct generic, not per field.
  var generics: OrderedSet[Generic]
  for field in fields:
    let definedFieldType = (? fileCtx.findType(field.argType.root)).localType
    case definedFieldType.kind:
    of ltkModule: discard
    of ltkGeneric: generics.incl(definedFieldType.generic)
  ok(generics.toSeq)

proc inferGenerics(fileCtx: FileContext, struct: StructDef): Result[seq[Generic], string] =
  let requiredGenerics = ? fileCtx.requiredGenerics(struct)
  if requiredGenerics.len > 0: ok(requiredGenerics)
  else: fileCtx.inferGenerics(struct.fields)

proc inferGenerics(fileCtx: FileContext, union: UnionDef): Result[seq[Generic], string] =
  var generics: OrderedSet[Generic]
  for variant in union.variants:
    let inferredGenerics = ? fileCtx.inferGenerics(variant.fields)
    for generic in inferredGenerics:
      generics.incl(generic)
  ok(generics.toSeq)

proc inferGenerics*(fileCtx: FileContext, dataDef: DataDef): Result[seq[Generic], string] =
  case dataDef.kind:
  of ddkLiteral: ok(newSeq[Generic]())
  of ddkStruct: fileCtx.inferGenerics(dataDef.struct)
  of ddkUnion: fileCtx.inferGenerics(dataDef.union)

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

proc satisfies*(typeCtx: TypeContext, base: Generic, argType: ResolvedGenericArgumentType): Result[void, string] =
  for def in base.defs:
    # NOTE: Generic functions are always public so we don't need access parameter
    let maybeFuncDefs = argType.generic.findFunctionDefs(def.name, def.arity)
    if maybeFuncDefs.isErr: return err(fmt"{argType.loc} generic `{argType.name.asl}` does not implement function `{def.name.asl}` to support `{base.name.asl}`")
  ok()

proc satisfies*(typeCtx: TypeContext, base: Generic, impl: ResolvedModuleArgumentType): Result[void, string] =
  ## A private function only counts as implementing `base` when the
  ## lookup context is the impl module itself (`faAll`) — everywhere
  ## else the constraint demands a public function.
  let access = typeCtx.access(impl.module)
  for def in base.defs:
    let maybeFuncDefs = impl.module.findFunctionDefs(def.name, def.arity, access)
    if maybeFuncDefs.isErr: return err(fmt"{impl.loc} module `{impl.name.asl}` does not implement function `{def.name.asl}` to support `{base.name.asl}`")
  ok()

proc satisfies*(typeCtx: TypeContext, base: Generic, impl: ResolvedArgumentType): Result[void, string] =
  case impl.kind:
  of ratkModule: typeCtx.satisfies(base, impl.module)
  of ratkGeneric: typeCtx.satisfies(base, impl.generic)
