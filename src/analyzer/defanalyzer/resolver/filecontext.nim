## FileContext — the imported-name -> imported LocalType table populated by
## resolver/imports.nim and threaded through every scope-consuming
## `resolve*` proc downstream. Pure type alias; no procs of its own.

import results, sequtils, sets, strformat, tables

import ./parser
import ./imports

type FileContext* = Table[Identifier, LocalType]

proc insert(fileCtx: var FileContext, name: Identifier, typ: LocalType): Result[FileContext, string] =
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
      fileCtx = ? fileCtx.insert(impType.binding, impType.typ)
  for typ in types:
    fileCtx = ? fileCtx.insert(typ.name, typ)
  ok(fileCtx)

proc findType*(fileCtx: FileContext, name: Identifier): Result[LocalType, string] =
  if name in fileCtx: ok(fileCtx[name])
  else: err(fmt"{name.loc} type `{name.asl}` does not exist in the scope")

proc findModule*(fileCtx: FileContext, name: Identifier): Result[Module, string] =
  let initType = ? fileCtx.findType(name)
  case initType.kind:
  of ltkGeneric: err(fmt"{name.loc} type `{name.asl}` is a generic and not a module")
  of ltkModule: ok(initType.module)

proc findGeneric*(fileCtx: FileContext, name: Identifier): Result[Generic, string] =
  let initType = ? fileCtx.findType(name)
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
    let definedFieldType = ? fileCtx.findType(field.argType.root)
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
