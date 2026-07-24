## FileScope — the imported-name -> imported Type table populated by
## resolver/imports.nim and threaded through every scope-consuming
## `resolve*` proc downstream. Pure type alias; no procs of its own.

import results, strformat, tables

import ./parser
import ./imports

type FileScope* = Table[Identifier, Type]

proc insert(fileScope: var FileScope, name: Identifier, typ: Type): Result[FileScope, string] =
  if name in fileScope:
    let loc = fileScope[name].loc
    err(fmt"{name.loc} duplicate type declaration encountered, see previous declaration at {loc}")
  else:
    fileScope[name] = typ
    ok(fileScope)

proc newFileScope*(imports: seq[ResolvedImport], types: seq[Type]): Result[FileScope, string] =
  var fileScope: FileScope
  for imp in imports:
    for impType in imp.importedTypes:
      fileScope = ? fileScope.insert(impType.binding, impType.typ)
  for typ in types:
    fileScope = ? fileScope.insert(typ.name, typ)
  ok(fileScope)

proc findType*(fileScope: FileScope, name: Identifier): Result[Type, string] =
  if name in fileScope: ok(fileScope[name])
  else: err(fmt"{name.loc} type `{name.asl}` does not exist in the scope")

proc findModule*(fileScope: FileScope, name: Identifier): Result[Module, string] =
  let initType = ? fileScope.findType(name)
  case initType.kind:
  of tkGeneric: err(fmt"{name.loc} type `{name.asl}` is a generic and not a module")
  of tkModule: ok(initType.module)

proc findGeneric*(fileScope: FileScope, name: Identifier): Result[Generic, string] =
  let initType = ? fileScope.findType(name)
  case initType.kind:
  of tkModule: err(fmt"{name.loc} type `{name.asl}` is a module but expected generic")
  of tkGeneric: ok(initType.generic)

proc requiredGenerics(fileScope: FileScope, struct: StructDef): Result[seq[Generic], string] =
  var requiredGenerics: seq[Generic]
  for generic in struct.header.requires:
    let foundGeneric = ? fileScope.findGeneric(generic)
    requiredGenerics.add(foundGeneric)
  ok(requiredGenerics)

proc inferGenerics(fileScope: FileScope, fields: seq[ArgumentDef]): Result[seq[Generic], string] =
  var requiredImpls: seq[Generic]
  for field in fields:
    let definedFieldType = ? fileScope.findType(field.argType.root)
    case definedFieldType.kind:
    of tkModule: discard
    of tkGeneric: requiredImpls.add(definedFieldType.generic)
  ok(requiredImpls)

proc inferGenerics*(fileScope: FileScope, struct: StructDef): Result[seq[Generic], string] =
  let requiredGenerics = ? fileScope.requiredGenerics(struct)
  if requiredGenerics.len > 0: ok(requiredGenerics)
  else: fileScope.inferGenerics(struct.fields)

proc inferGenerics*(fileScope: FileScope, union: UnionDef): Result[seq[Generic], string] =
  var genericMapping: Table[Generic, int]
  for variant in union.variants:
    let inferredGenerics = ? fileScope.inferGenerics(variant.fields)
    for generic in inferredGenerics:
      if generic notin genericMapping: genericMapping[generic] = genericMapping.len

  var inferredGenerics = newSeq[Generic](genericMapping.len)
  for generic, index in genericMapping:
    inferredGenerics[index] = generic
  ok(inferredGenerics)

proc inferGenerics*(fileScope: FileScope, dataDef: DataDef): Result[seq[Generic], string] =
  case dataDef.kind:
  of ddkLiteral: ok(newSeq[Generic]())
  of ddkStruct: fileScope.inferGenerics(dataDef.struct)
  of ddkUnion: fileScope.inferGenerics(dataDef.union)
