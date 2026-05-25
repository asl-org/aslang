## Data-block resolution: struct / variant / union / data umbrella.

import results

import parser
import literals
import argtypes
import funcdefs

# ResolvedStruct
type ResolvedStruct* = ref object
  fields: seq[ResolvedArgumentDefinition]

proc newResolvedStruct*(fields: seq[ResolvedArgumentDefinition]): ResolvedStruct =
  ResolvedStruct(fields: fields)

proc fields*(struct: ResolvedStruct): seq[ResolvedArgumentDefinition] = struct.fields

proc requires*(struct: ResolvedStruct): seq[ResolvedGenericArgumentType] =
  var fields: seq[ResolvedGenericArgumentType]
  for field in struct.fields:
    case field.argType.kind:
    of ratkImported: assert(false, "todo: support imported types for requier list")
    of ratkDefined:
      case field.argType.definedType.kind:
      of rdatkModule: discard
      of rdatkGeneric: fields.add(field.argType.definedType.generic)
  return fields

proc resolveStruct*(app: App, file: parser.File, fileScope: FileScope,
    module: Module, struct: Struct): Result[ResolvedStruct, string] =
  var resolvedFields: seq[ResolvedArgumentDefinition]
  for field in struct.fields:
    let resolvedField = ? resolveArgumentDefinition(app, file, fileScope, module,
      field)
    resolvedFields.add(resolvedField)
  ok(newResolvedStruct(resolvedFields))

# ResolvedVariant
type ResolvedVariant* = ref object
  name: Identifier
  fields: seq[ResolvedArgumentDefinition]

proc newResolvedVariant*(name: Identifier,
    fields: seq[ResolvedArgumentDefinition]): ResolvedVariant =
  ResolvedVariant(name: name, fields: fields)

proc resolveVariant(app: App, file: parser.File, fileScope: FileScope,
    module: Module,
    variant: VariantDefinition): Result[ResolvedVariant, string] =
  var resolvedFields: seq[ResolvedArgumentDefinition]
  for field in variant.fields:
    let resolvedField = ? resolveArgumentDefinition(app, file, fileScope, module,
      field)
    resolvedFields.add(resolvedField)
  ok(newResolvedVariant(variant.name, resolvedFields))

# ResolvedUnion
type ResolvedUnion* = ref object
  variants: seq[ResolvedVariant]

proc newResolvedUnion*(variants: seq[ResolvedVariant]): ResolvedUnion =
  ResolvedUnion(variants: variants)

proc requires*(union: ResolvedUnion): seq[ResolvedGenericArgumentType] =
  var fields: seq[ResolvedGenericArgumentType]
  for variant in union.variants:
    for field in variant.fields:
      case field.argType.kind:
      of ratkImported: assert(false, "todo: support imported types for requier list")
      of ratkDefined:
        case field.argType.definedType.kind:
        of rdatkModule: discard
        of rdatkGeneric: fields.add(field.argType.definedType.generic)
  return fields

proc resolveUnion*(app: App, file: parser.File, fileScope: FileScope,
    module: Module, union: Union): Result[ResolvedUnion, string] =
  var resolvedVariants: seq[ResolvedVariant]
  for variant in union.variants:
    let resolvedVariant = ? resolveVariant(app, file, fileScope, module, variant)
    resolvedVariants.add(resolvedVariant)
  ok(newResolvedUnion(resolvedVariants))

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
proc literal*(data: ResolvedData): ResolvedLiteralType = data.literal
proc struct*(data: ResolvedData): ResolvedStruct = data.struct
proc union*(data: ResolvedData): ResolvedUnion = data.union
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
