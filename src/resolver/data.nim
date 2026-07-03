## Data-block resolution: struct / variant / union / data umbrella.

import results, strformat, tables

import tokenizer
import parser
import literals
import argtypes
import funcdefs

proc accumulateGenericPosition(genericTypeIndex: var Table[ResolvedGenericArgumentType, int], field: ResolvedArgumentDefinition) =
  ## Assigns the next position to each new generic encountered in
  ## field types. Same name across multiple fields keeps its first
  ## position — the analyzer's GenericImplMap binds one generic to
  ## one concrete type per construction, so duplicate occurrences
  ## are semantically benign (any conflict surfaces at the init site
  ## via merge()). Generic-uniqueness inside an explicit requires()
  ## block is still enforced by validateRequiresConstraints.
  case field.argType.kind:
  of ratkModule: discard
  of ratkGeneric:
    let genericType = field.argType.generic
    if genericType notin genericTypeIndex:
      genericTypeIndex[genericType] = genericTypeIndex.len

# ResolvedStructDef
type ResolvedStructDef* = ref object
  parsed: StructDef
  fields: seq[ResolvedArgumentDefinition]
  fieldIndex: Table[Identifier, int]
  genericTypeIndex: Table[ResolvedGenericArgumentType, int]

proc newResolvedStructDef*(parsed: StructDef, fields: seq[ResolvedArgumentDefinition], genericTypeIndex: Table[ResolvedGenericArgumentType, int]): ResolvedStructDef =
  var fieldIndex: Table[Identifier, int]
  for id, field in fields:
    assert(field.name notin fieldIndex, "UNREACHABLE: duplicate field name — should have been caught in parser")
    fieldIndex[field.name] = id
  ResolvedStructDef(parsed: parsed, fields: fields, fieldIndex: fieldIndex, genericTypeIndex: genericTypeIndex)

proc parsed*(struct: ResolvedStructDef): StructDef = struct.parsed
proc loc*(struct: ResolvedStructDef): Location = struct.parsed.loc
proc fields*(struct: ResolvedStructDef): seq[ResolvedArgumentDefinition] = struct.fields
proc genericTypeIndex*(struct: ResolvedStructDef): Table[ResolvedGenericArgumentType, int] = struct.genericTypeIndex

proc findField*(struct: ResolvedStructDef, name: Identifier): Result[ResolvedArgumentDefinition, string] =
  if name in struct.fieldIndex: ok(struct.fields[struct.fieldIndex[name]])
  else: err(fmt"{name.loc} field `{name.asl}` does not exist")

proc requires*(struct: ResolvedStructDef): seq[ResolvedGenericArgumentType] =
  var requires = newSeq[ResolvedGenericArgumentType](struct.genericTypeIndex.len)
  for genericType, index in struct.genericTypeIndex:
    requires[index] = genericType
  return requires

proc resolveStructDef*(app: App, file: parser.File, fileScope: FileScope, module: Module, struct: StructDef): Result[ResolvedStructDef, string] =
  var resolvedFields: seq[ResolvedArgumentDefinition]
  var genericTypeIndex: Table[ResolvedGenericArgumentType, int]
  for field in struct.fields:
    let resolvedField = ? resolveArgumentDefinition(app, file, fileScope, module, field)
    genericTypeIndex.accumulateGenericPosition(resolvedField)
    resolvedFields.add(resolvedField)
  ok(newResolvedStructDef(struct, resolvedFields, genericTypeIndex))

# ResolvedVariant
type ResolvedVariant* = ref object
  parsed: VariantDefinition
  fields: seq[ResolvedArgumentDefinition]
  fieldIndex: Table[Identifier, int]

proc newResolvedVariant*(parsed: VariantDefinition, fields: seq[ResolvedArgumentDefinition]): ResolvedVariant =
  var fieldIndex: Table[Identifier, int]
  for id, field in fields:
    assert(field.name notin fieldIndex, "UNREACHABLE: duplicate field name — should have been caught in parser")
    fieldIndex[field.name] = id
  ResolvedVariant(parsed: parsed, fields: fields, fieldIndex: fieldIndex)

proc loc*(variant: ResolvedVariant): Location = variant.parsed.loc
proc name*(variant: ResolvedVariant): Identifier = variant.parsed.name
proc parsed*(variant: ResolvedVariant): VariantDefinition = variant.parsed
proc fields*(variant: ResolvedVariant): seq[ResolvedArgumentDefinition] = variant.fields

proc findField*(variant: ResolvedVariant, name: Identifier): Result[ResolvedArgumentDefinition, string] =
  if name in variant.fieldIndex: ok(variant.fields[variant.fieldIndex[name]])
  else: err(fmt"{name.loc} field `{name.asl}` does not exist")

# NOTE: `genericTypeIndex` is the union's shared position table — mutated
# in place as each variant's fields contribute new generics (in
# declaration order); not returned because the union accumulates it.
proc resolveVariant(app: App, file: parser.File, fileScope: FileScope, module: Module, variant: VariantDefinition, genericTypeIndex: var Table[ResolvedGenericArgumentType, int]): Result[ResolvedVariant, string] =
  var resolvedFields: seq[ResolvedArgumentDefinition]
  for field in variant.fields:
    let resolvedField = ? resolveArgumentDefinition(app, file, fileScope, module, field)
    genericTypeIndex.accumulateGenericPosition(resolvedField)
    resolvedFields.add(resolvedField)
  ok(newResolvedVariant(variant, resolvedFields))

# ResolvedUnionDef
type ResolvedUnionDef* = ref object
  parsed: UnionDef
  variants: seq[ResolvedVariant]
  variantIndex: Table[Identifier, int]
  genericTypeIndex: Table[ResolvedGenericArgumentType, int]

proc newResolvedUnionDef*(parsed: UnionDef, variants: seq[ResolvedVariant], genericTypeIndex: Table[ResolvedGenericArgumentType, int]): ResolvedUnionDef =
  var variantIndex: Table[Identifier, int]
  for id, variant in variants:
    assert(variant.name notin variantIndex, "UNREACHABLE: duplicate variant — should have been caught in parser")
    variantIndex[variant.name] = id
  ResolvedUnionDef(parsed: parsed, variants: variants, variantIndex: variantIndex, genericTypeIndex: genericTypeIndex)

proc loc*(union: ResolvedUnionDef): Location = union.parsed.loc
proc variants*(union: ResolvedUnionDef): seq[ResolvedVariant] = union.variants
proc genericTypeIndex*(union: ResolvedUnionDef): Table[ResolvedGenericArgumentType, int] = union.genericTypeIndex

proc findVariant*(union: ResolvedUnionDef, variant: Identifier): Result[ResolvedVariant, string] =
  if variant in union.variantIndex: ok(union.variants[union.variantIndex[variant]])
  else: err(fmt"{variant.loc} union does not contain variant `{variant.asl}`")

proc requires*(union: ResolvedUnionDef): seq[ResolvedGenericArgumentType] =
  ## One union scope: a generic name shared across variants is one
  ## shared type parameter (Rust style), so dedup by underlying Generic
  ## identity. Within-variant duplicates are already impossible
  ## (caught by validateUniqueGenericFields in resolveVariant).
  var requires = newSeq[ResolvedGenericArgumentType](union.genericTypeIndex.len)
  for genericType, index in union.genericTypeIndex:
    requires[index] = genericType
  return requires

proc resolveUnionDef*(app: App, file: parser.File, fileScope: FileScope,
    module: Module, union: UnionDef): Result[ResolvedUnionDef, string] =
  var resolvedVariants: seq[ResolvedVariant]
  var genericTypeIndex: Table[ResolvedGenericArgumentType, int]
  for variant in union.variants:
    let resolvedVariant = ? resolveVariant(app, file, fileScope, module, variant, genericTypeIndex)
    resolvedVariants.add(resolvedVariant)
  ok(newResolvedUnionDef(union, resolvedVariants, genericTypeIndex))

# ResolvedData
type
  ResolvedDataKind* = enum
    rdkLiteral, rdkStruct, rdkUnion
  ResolvedData* = ref object
    case kind: ResolvedDataKind
    of rdkLiteral: literal: ResolvedLiteralDef
    of rdkStruct: struct: ResolvedStructDef
    of rdkUnion: union: ResolvedUnionDef

proc newResolvedData*(literal: ResolvedLiteralDef): ResolvedData =
  ResolvedData(kind: rdkLiteral, literal: literal)

proc newResolvedData*(struct: ResolvedStructDef): ResolvedData =
  ResolvedData(kind: rdkStruct, struct: struct)

proc newResolvedData*(union: ResolvedUnionDef): ResolvedData =
  ResolvedData(kind: rdkUnion, union: union)

proc kind*(data: ResolvedData): ResolvedDataKind = data.kind
proc literal*(data: ResolvedData): ResolvedLiteralDef =
  assert data.kind == rdkLiteral,
    fmt"ResolvedData.literal accessed but kind is {data.kind}"
  data.literal
proc struct*(data: ResolvedData): ResolvedStructDef =
  assert data.kind == rdkStruct,
    fmt"ResolvedData.struct accessed but kind is {data.kind}"
  data.struct
proc union*(data: ResolvedData): ResolvedUnionDef =
  assert data.kind == rdkUnion,
    fmt"ResolvedData.union accessed but kind is {data.kind}"
  data.union
proc requires*(data: ResolvedData): seq[ResolvedGenericArgumentType] =
  case data.kind:
  of rdkLiteral: @[]
  of rdkStruct: data.struct.requires
  of rdkUnion: data.union.requires

proc resolveDataBlock*(app: App, file: parser.File, fileScope: FileScope,
    module: Module, data: DataBlock): Result[ResolvedData, string] =
  case data.kind:
  of dbkLiteral:
    let resolvedLiteralType = ? resolveLiteralDef(file, data.literal)
    ok(newResolvedData(resolvedLiteralType))
  of dbkStruct:
    let resolvedStruct = ? resolveStructDef(app, file, fileScope, module,
      data.struct)
    ok(newResolvedData(resolvedStruct))
  of dbkUnion:
    let resolvedUnion = ? resolveUnionDef(app, file, fileScope, module, data.union)
    ok(newResolvedData(resolvedUnion))
