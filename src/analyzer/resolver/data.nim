## Data-block cluster — ResolvedStructDef, ResolvedVariant,
## ResolvedUnionDef, ResolvedData. Reads ResolvedArgumentDef +
## ResolvedGenericArgumentType from earlier layers.

import results, strformat, tables, hashes, sequtils

import ./parser
import argtypes
import funcdefs
import literals  # ResolvedLiteralDef

type
  ResolvedStructDef* = ref object
    parsed: StructDef
    fields: seq[ResolvedArgumentDef]
    fieldIndex: Table[Identifier, int]
    genericTypeIndex: Table[ResolvedGenericArgumentType, int]

  ResolvedVariant* = ref object
    parsed: VariantDef
    fields: seq[ResolvedArgumentDef]
    fieldIndex: Table[Identifier, int]

  ResolvedUnionDef* = ref object
    parsed: UnionDef
    variants: seq[ResolvedVariant]
    variantIndex: Table[Identifier, int]
    genericTypeIndex: Table[ResolvedGenericArgumentType, int]

  ResolvedDataKind* = enum
    rdkLiteral, rdkStruct, rdkUnion

  ResolvedData* = ref object
    case kind: ResolvedDataKind
    of rdkLiteral: literal: ResolvedLiteralDef
    of rdkStruct: struct: ResolvedStructDef
    of rdkUnion: union: ResolvedUnionDef

# =====================================================================
# Data-block cluster
# (ResolvedStructDef, ResolvedVariant, ResolvedUnionDef, ResolvedData)
# =====================================================================

proc accumulateGenericPosition(genericTypeIndex: var Table[ResolvedGenericArgumentType, int], field: ResolvedArgumentDef) =
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

# ---- ResolvedStructDef ----

proc newResolvedStructDef*(parsed: StructDef,
    fields: seq[ResolvedArgumentDef],
    genericTypeIndex: Table[ResolvedGenericArgumentType, int]): ResolvedStructDef =
  var fieldIndex: Table[Identifier, int]
  for id, field in fields:
    assert(field.name notin fieldIndex, "UNREACHABLE: duplicate field name — should have been caught in parser")
    fieldIndex[field.name] = id
  ResolvedStructDef(parsed: parsed, fields: fields, fieldIndex: fieldIndex, genericTypeIndex: genericTypeIndex)

proc parsed*(struct: ResolvedStructDef): StructDef = struct.parsed
proc fields*(struct: ResolvedStructDef): seq[ResolvedArgumentDef] = struct.fields
proc genericTypeIndex*(struct: ResolvedStructDef): Table[ResolvedGenericArgumentType, int] = struct.genericTypeIndex
proc fieldIndex*(struct: ResolvedStructDef): Table[Identifier, int] = struct.fieldIndex
proc loc*(struct: ResolvedStructDef): Location = struct.parsed.loc

proc findField*(struct: ResolvedStructDef, name: Identifier): Result[ResolvedArgumentDef, string] =
  if name in struct.fieldIndex: ok(struct.fields[struct.fieldIndex[name]])
  else: err(fmt"{name.loc} field `{name.asl}` does not exist")

proc requires*(struct: ResolvedStructDef): seq[ResolvedGenericArgumentType] =
  var requires = newSeq[ResolvedGenericArgumentType](struct.genericTypeIndex.len)
  for genericType, index in struct.genericTypeIndex:
    requires[index] = genericType
  return requires

proc resolveStructDef*(app: App, file: parser.File, fileScope: FileScope, module: Module, struct: StructDef): Result[ResolvedStructDef, string] =
  var resolvedFields: seq[ResolvedArgumentDef]
  var genericTypeIndex: Table[ResolvedGenericArgumentType, int]
  for field in struct.fields:
    let resolvedField = ? resolveArgumentDef(app, file, fileScope, module, field)
    genericTypeIndex.accumulateGenericPosition(resolvedField)
    resolvedFields.add(resolvedField)
  ok(newResolvedStructDef(struct, resolvedFields, genericTypeIndex))

# ---- ResolvedVariant ----

proc newResolvedVariant*(parsed: VariantDef,
    fields: seq[ResolvedArgumentDef]): ResolvedVariant =
  var fieldIndex: Table[Identifier, int]
  for id, field in fields:
    assert(field.name notin fieldIndex, "UNREACHABLE: duplicate field name — should have been caught in parser")
    fieldIndex[field.name] = id
  ResolvedVariant(parsed: parsed, fields: fields, fieldIndex: fieldIndex)

proc parsed*(variant: ResolvedVariant): VariantDef = variant.parsed
proc fields*(variant: ResolvedVariant): seq[ResolvedArgumentDef] = variant.fields
proc fieldIndex*(variant: ResolvedVariant): Table[Identifier, int] = variant.fieldIndex
proc loc*(variant: ResolvedVariant): Location = variant.parsed.loc
proc name*(variant: ResolvedVariant): Identifier = variant.parsed.name

proc findField*(variant: ResolvedVariant, name: Identifier): Result[ResolvedArgumentDef, string] =
  if name in variant.fieldIndex: ok(variant.fields[variant.fieldIndex[name]])
  else: err(fmt"{name.loc} field `{name.asl}` does not exist")

# NOTE: `genericTypeIndex` is the union's shared position table — mutated
# in place as each variant's fields contribute new generics (in
# declaration order); not returned because the union accumulates it.
proc resolveVariant(app: App, file: parser.File, fileScope: FileScope, module: Module, variant: VariantDef, genericTypeIndex: var Table[ResolvedGenericArgumentType, int]): Result[ResolvedVariant, string] =
  var resolvedFields: seq[ResolvedArgumentDef]
  for field in variant.fields:
    let resolvedField = ? resolveArgumentDef(app, file, fileScope, module, field)
    genericTypeIndex.accumulateGenericPosition(resolvedField)
    resolvedFields.add(resolvedField)
  ok(newResolvedVariant(variant, resolvedFields))

# ---- ResolvedUnionDef ----

proc newResolvedUnionDef*(parsed: UnionDef, variants: seq[ResolvedVariant],
    genericTypeIndex: Table[ResolvedGenericArgumentType, int]): ResolvedUnionDef =
  var variantIndex: Table[Identifier, int]
  for id, variant in variants:
    assert(variant.parsed.name notin variantIndex, "UNREACHABLE: duplicate variant — should have been caught in parser")
    variantIndex[variant.parsed.name] = id
  ResolvedUnionDef(parsed: parsed, variants: variants, variantIndex: variantIndex, genericTypeIndex: genericTypeIndex)

proc parsed*(union: ResolvedUnionDef): UnionDef = union.parsed
proc variants*(union: ResolvedUnionDef): seq[ResolvedVariant] = union.variants
proc genericTypeIndex*(union: ResolvedUnionDef): Table[ResolvedGenericArgumentType, int] = union.genericTypeIndex
proc variantIndex*(union: ResolvedUnionDef): Table[Identifier, int] = union.variantIndex
proc loc*(union: ResolvedUnionDef): Location = union.parsed.loc

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

# ---- ResolvedData ----

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

proc resolveDataDef*(app: App, file: parser.File,
    fileScope: FileScope, module: Module, data: DataDef): Result[ResolvedData, string] =
  case data.kind:
  of ddkLiteral:
    let resolvedLiteralType = ? resolveLiteralDef(file, data.literal)
    ok(newResolvedData(resolvedLiteralType))
  of ddkStruct:
    let resolvedStruct = ? resolveStructDef(app, file, fileScope, module,
      data.struct)
    ok(newResolvedData(resolvedStruct))
  of ddkUnion:
    let resolvedUnion = ? resolveUnionDef(app, file, fileScope, module, data.union)
    ok(newResolvedData(resolvedUnion))

