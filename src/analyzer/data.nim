## Analyzed data blocks: struct / variant / union / data umbrella.

import results, tables, strformat

import tokenizer
import parser
import resolver
import literals
import argtypes
import funcdefs

proc accumulateGenericPosition(genericTypeIndex: var Table[AnalyzedGenericArgumentType, int], field: AnalyzedArgumentDefinition) =
  ## Mirror of the resolver-side accumulator. Same name across
  ## multiple fields keeps its first position — conflicts surface at
  ## the init site via GenericImplMap.merge(), not here.
  case field.argType.kind:
  of aatkImported:
    assert(false, "todo: walk imported field type to collect nested generics")
  of aatkDefined:
    case field.argType.definedType.kind:
    of adatkModule: discard
    of adatkGeneric:
      let genericType = field.argType.definedType.generic
      if genericType notin genericTypeIndex:
        genericTypeIndex[genericType] = genericTypeIndex.len

# AnalyzedStruct
type AnalyzedStruct* = ref object
  resolved: ResolvedStruct
  fields: seq[AnalyzedArgumentDefinition]
  fieldIndex: Table[Identifier, int]
  genericTypeIndex: Table[AnalyzedGenericArgumentType, int]

proc newAnalyzedStruct*(resolved: ResolvedStruct, fields: seq[AnalyzedArgumentDefinition], genericTypeIndex: Table[AnalyzedGenericArgumentType, int]): AnalyzedStruct =
  var fieldIndex: Table[Identifier, int]
  for id, field in fields:
    assert(field.name notin fieldIndex, "UNREACHABLE: duplicate field name must have been caught by resolver")
    fieldIndex[field.name] = id
  AnalyzedStruct(resolved: resolved, fields: fields, fieldIndex: fieldIndex, genericTypeIndex: genericTypeIndex)

proc resolved*(s: AnalyzedStruct): ResolvedStruct = s.resolved
proc loc*(s: AnalyzedStruct): Location = s.resolved.loc
proc fields*(s: AnalyzedStruct): seq[AnalyzedArgumentDefinition] = s.fields
proc findField*(s: AnalyzedStruct, name: Identifier): Result[AnalyzedArgumentDefinition, string] =
  if name in s.fieldIndex: ok(s.fields[s.fieldIndex[name]])
  else: err(fmt"{name.loc} field `{name.asl}` does not exist")

proc concrete*(struct: AnalyzedStruct, impls: seq[AnalyzedArgumentType]): AnalyzedStruct =
  var concreteFields: seq[AnalyzedArgumentDefinition]
  for field in struct.fields:
    let concreteField = field.concrete(impls, struct.genericTypeIndex)
    concreteFields.add(concreteField)
  newAnalyzedStruct(struct.resolved, concreteFields, struct.genericTypeIndex)

proc analyzeStruct*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, struct: ResolvedStruct): Result[AnalyzedStruct, string] =
  var analyzedFields: seq[AnalyzedArgumentDefinition]
  var genericTypeIndex: Table[AnalyzedGenericArgumentType, int]
  for field in struct.fields:
    let analyzedField = ? analyzeArgumentDefinition(app, file, fileScope, module, field)
    genericTypeIndex.accumulateGenericPosition(analyzedField)
    analyzedFields.add(analyzedField)
  ok(newAnalyzedStruct(struct, analyzedFields, genericTypeIndex))

# AnalyzedVariant
type AnalyzedVariant* = ref object
  resolved: ResolvedVariant
  fields: seq[AnalyzedArgumentDefinition]
  fieldIndex: Table[Identifier, int]

proc newAnalyzedVariant*(resolved: ResolvedVariant, fields: seq[AnalyzedArgumentDefinition]): AnalyzedVariant =
  var fieldIndex: Table[Identifier, int]
  for id, field in fields:
    assert(field.name notin fieldIndex, "UNREACHABLE: duplicate field name must have been caught by resolver")
    fieldIndex[field.name] = id
  AnalyzedVariant(resolved: resolved, fields: fields, fieldIndex: fieldIndex)

proc name*(v: AnalyzedVariant): Identifier = v.resolved.name
proc resolved*(v: AnalyzedVariant): ResolvedVariant = v.resolved
proc fields*(v: AnalyzedVariant): seq[AnalyzedArgumentDefinition] = v.fields

proc concrete*(variant: AnalyzedVariant, impls: seq[AnalyzedArgumentType], genericTypeIndex: Table[AnalyzedGenericArgumentType, int]): AnalyzedVariant =
  var concreteFields: seq[AnalyzedArgumentDefinition]
  for field in variant.fields:
    let concreteField = field.concrete(impls, genericTypeIndex)
    concreteFields.add(concreteField)
  newAnalyzedVariant(variant.resolved, concreteFields)

proc findField*(v: AnalyzedVariant, name: Identifier): Result[AnalyzedArgumentDefinition, string] =
  if name in v.fieldIndex: ok(v.fields[v.fieldIndex[name]])
  else: err(fmt"{name.loc} field `{name.asl}` does not exist")

proc analyzeVariant(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, variant: ResolvedVariant, genericTypeIndex: var Table[AnalyzedGenericArgumentType, int]): Result[AnalyzedVariant, string] =
  var analyzedFields: seq[AnalyzedArgumentDefinition]
  for field in variant.fields:
    let analyzedField = ? analyzeArgumentDefinition(app, file, fileScope, module, field)
    genericTypeIndex.accumulateGenericPosition(analyzedField)
    analyzedFields.add(analyzedField)
  ok(newAnalyzedVariant(variant, analyzedFields))

# AnalyzedUnion
type AnalyzedUnion* = ref object
  resolved: ResolvedUnion
  variants: seq[AnalyzedVariant]
  variantIndex: Table[Identifier, int]
  genericTypeIndex: Table[AnalyzedGenericArgumentType, int]

proc newAnalyzedUnion*(resolved: ResolvedUnion, variants: seq[AnalyzedVariant], genericTypeIndex: Table[AnalyzedGenericArgumentType, int]): AnalyzedUnion =
  var variantIndex: Table[Identifier, int]
  for id, variant in variants:
    assert(variant.name notin variantIndex, "UNREACHABLE: this should have been caught in resolution")
    variantIndex[variant.name] = id
  AnalyzedUnion(resolved: resolved, variants: variants, variantIndex: variantIndex, genericTypeIndex: genericTypeIndex)

proc resolved*(u: AnalyzedUnion): ResolvedUnion = u.resolved
proc variants*(u: AnalyzedUnion): seq[AnalyzedVariant] = u.variants
proc genericTypeIndex*(u: AnalyzedUnion): Table[AnalyzedGenericArgumentType, int] = u.genericTypeIndex
proc concrete*(union: AnalyzedUnion, impls: seq[AnalyzedArgumentType]): AnalyzedUnion =
  var concreteVariants: seq[AnalyzedVariant]
  for variant in union.variants:
    let concreteVariant = variant.concrete(impls, union.genericTypeIndex)
    concreteVariants.add(concreteVariant)
  newAnalyzedUnion(union.resolved, concreteVariants, union.genericTypeIndex)

proc findVariant*(union: AnalyzedUnion, variant: Identifier): Result[AnalyzedVariant, string] =
  if variant in union.variantIndex: ok(union.variants[union.variantIndex[variant]])
  else: err(fmt"{variant.loc} union does not contain variant `{variant.asl}`")

proc analyzeUnion*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, union: ResolvedUnion): Result[AnalyzedUnion, string] =
  var analyzedVariants: seq[AnalyzedVariant]
  var genericTypeIndex: Table[AnalyzedGenericArgumentType, int]
  for variant in union.variants:
    let analyzedVariant = ? analyzeVariant(app, file, fileScope, module, variant, genericTypeIndex)
    analyzedVariants.add(analyzedVariant)
  ok(newAnalyzedUnion(union, analyzedVariants, genericTypeIndex))

# AnalyzedData
type
  AnalyzedDataKind* = enum
    adkLiteral, adkStruct, adkUnion
  AnalyzedData* = ref object
    case kind: AnalyzedDataKind
    of adkLiteral: literal: AnalyzedLiteralBlock
    of adkStruct: struct: AnalyzedStruct
    of adkUnion: union: AnalyzedUnion

proc newAnalyzedData*(literal: AnalyzedLiteralBlock): AnalyzedData =
  AnalyzedData(kind: adkLiteral, literal: literal)

proc newAnalyzedData*(struct: AnalyzedStruct): AnalyzedData =
  AnalyzedData(kind: adkStruct, struct: struct)

proc newAnalyzedData*(union: AnalyzedUnion): AnalyzedData =
  AnalyzedData(kind: adkUnion, union: union)

proc kind*(d: AnalyzedData): AnalyzedDataKind = d.kind
proc literal*(d: AnalyzedData): AnalyzedLiteralBlock =
  assert d.kind == adkLiteral,
    fmt"AnalyzedData.literal accessed but kind is {d.kind}"
  d.literal
proc struct*(d: AnalyzedData): AnalyzedStruct =
  assert d.kind == adkStruct,
    fmt"AnalyzedData.struct accessed but kind is {d.kind}"
  d.struct
proc union*(d: AnalyzedData): AnalyzedUnion =
  assert d.kind == adkUnion,
    fmt"AnalyzedData.union accessed but kind is {d.kind}"
  d.union

proc analyzeData*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, data: ResolvedData): Result[AnalyzedData, string] =
  case data.kind:
  of rdkLiteral:
    ok(newAnalyzedData(newAnalyzedLiteralBlock(data.literal)))
  of rdkStruct:
    let analyzedStruct = ? analyzeStruct(app, file, fileScope, module, data.struct)
    ok(newAnalyzedData(analyzedStruct))
  of rdkUnion:
    let analyzedUnion = ? analyzeUnion(app, file, fileScope, module, data.union)
    ok(newAnalyzedData(analyzedUnion))
