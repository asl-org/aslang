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
  of ratkImported:
    assert(false, "todo: walk imported field type to collect nested generics")
  of ratkDefined:
    case field.argType.definedType.kind:
    of rdatkModule: discard
    of rdatkGeneric:
      let genericType = field.argType.definedType.generic
      if genericType notin genericTypeIndex:
        genericTypeIndex[genericType] = genericTypeIndex.len

# ResolvedStruct
type ResolvedStruct* = ref object
  parsed: Struct
  fields: seq[ResolvedArgumentDefinition]
  genericTypeIndex: Table[ResolvedGenericArgumentType, int]

proc newResolvedStruct*(parsed: Struct, fields: seq[ResolvedArgumentDefinition], genericTypeIndex: Table[ResolvedGenericArgumentType, int]): ResolvedStruct =
  ResolvedStruct(parsed: parsed, fields: fields, genericTypeIndex: genericTypeIndex)

proc parsed*(struct: ResolvedStruct): Struct = struct.parsed
proc loc*(struct: ResolvedStruct): Location = struct.parsed.loc
proc fields*(struct: ResolvedStruct): seq[ResolvedArgumentDefinition] = struct.fields

proc requires*(struct: ResolvedStruct): seq[ResolvedGenericArgumentType] =
  var requires = newSeq[ResolvedGenericArgumentType](struct.genericTypeIndex.len)
  for genericType, index in struct.genericTypeIndex:
    requires[index] = genericType
  return requires

proc resolveStruct*(app: App, file: parser.File, fileScope: FileScope, module: Module, struct: Struct): Result[ResolvedStruct, string] =
  var resolvedFields: seq[ResolvedArgumentDefinition]
  var genericTypeIndex: Table[ResolvedGenericArgumentType, int]
  for field in struct.fields:
    let resolvedField = ? resolveArgumentDefinition(app, file, fileScope, module, field)
    genericTypeIndex.accumulateGenericPosition(resolvedField)
    resolvedFields.add(resolvedField)
  ok(newResolvedStruct(struct, resolvedFields, genericTypeIndex))

# ResolvedVariant
type ResolvedVariant* = ref object
  parsed: VariantDefinition
  fields: seq[ResolvedArgumentDefinition]

proc newResolvedVariant*(parsed: VariantDefinition, fields: seq[ResolvedArgumentDefinition]): ResolvedVariant =
  ResolvedVariant(parsed: parsed, fields: fields)

proc loc*(variant: ResolvedVariant): Location = variant.parsed.loc
proc name*(variant: ResolvedVariant): Identifier = variant.parsed.name
proc parsed*(variant: ResolvedVariant): VariantDefinition = variant.parsed
proc fields*(variant: ResolvedVariant): seq[ResolvedArgumentDefinition] = variant.fields

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

# ResolvedUnion
type ResolvedUnion* = ref object
  parsed: Union
  variants: seq[ResolvedVariant]
  genericTypeIndex: Table[ResolvedGenericArgumentType, int]

proc newResolvedUnion*(parsed: Union, variants: seq[ResolvedVariant], genericTypeIndex: Table[ResolvedGenericArgumentType, int]): ResolvedUnion =
  ResolvedUnion(parsed: parsed, variants: variants, genericTypeIndex: genericTypeIndex)

proc loc*(union: ResolvedUnion): Location = union.parsed.loc
proc variants*(union: ResolvedUnion): seq[ResolvedVariant] = union.variants
proc requires*(union: ResolvedUnion): seq[ResolvedGenericArgumentType] =
  ## One union scope: a generic name shared across variants is one
  ## shared type parameter (Rust style), so dedup by underlying Generic
  ## identity. Within-variant duplicates are already impossible
  ## (caught by validateUniqueGenericFields in resolveVariant).
  var requires = newSeq[ResolvedGenericArgumentType](union.genericTypeIndex.len)
  for genericType, index in union.genericTypeIndex:
    requires[index] = genericType
  return requires

proc resolveUnion*(app: App, file: parser.File, fileScope: FileScope,
    module: Module, union: Union): Result[ResolvedUnion, string] =
  var resolvedVariants: seq[ResolvedVariant]
  var genericTypeIndex: Table[ResolvedGenericArgumentType, int]
  for variant in union.variants:
    let resolvedVariant = ? resolveVariant(app, file, fileScope, module, variant, genericTypeIndex)
    resolvedVariants.add(resolvedVariant)
  ok(newResolvedUnion(union, resolvedVariants, genericTypeIndex))

# ResolvedData
type
  ResolvedDataKind* = enum
    rdkLiteral, rdkStruct, rdkUnion
  ResolvedData* = ref object
    case kind: ResolvedDataKind
    of rdkLiteral: literal: ResolvedLiteralType
    of rdkStruct: struct: ResolvedStruct
    of rdkUnion: union: ResolvedUnion

proc newResolvedData*(literal: ResolvedLiteralType): ResolvedData =
  ResolvedData(kind: rdkLiteral, literal: literal)

proc newResolvedData*(struct: ResolvedStruct): ResolvedData =
  ResolvedData(kind: rdkStruct, struct: struct)

proc newResolvedData*(union: ResolvedUnion): ResolvedData =
  ResolvedData(kind: rdkUnion, union: union)

proc kind*(data: ResolvedData): ResolvedDataKind = data.kind
proc literal*(data: ResolvedData): ResolvedLiteralType =
  assert data.kind == rdkLiteral,
    fmt"ResolvedData.literal accessed but kind is {data.kind}"
  data.literal
proc struct*(data: ResolvedData): ResolvedStruct =
  assert data.kind == rdkStruct,
    fmt"ResolvedData.struct accessed but kind is {data.kind}"
  data.struct
proc union*(data: ResolvedData): ResolvedUnion =
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
    let resolvedLiteralType = ? resolveLiteralType(file, data.literal)
    ok(newResolvedData(resolvedLiteralType))
  of dbkStruct:
    let resolvedStruct = ? resolveStruct(app, file, fileScope, module,
      data.struct)
    ok(newResolvedData(resolvedStruct))
  of dbkUnion:
    let resolvedUnion = ? resolveUnion(app, file, fileScope, module, data.union)
    ok(newResolvedData(resolvedUnion))
