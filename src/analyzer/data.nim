## Analyzed data blocks: struct / variant / union / data umbrella.

import results, tables, strformat

import tokenizer
import parser
import resolver
import literals
import argtypes
import funcdefs

# AnalyzedStruct
type AnalyzedStruct* = ref object
  resolved: ResolvedStruct
  fields: seq[AnalyzedArgumentDefinition]
  fieldIndex: Table[Identifier, int]

# TODO: Ensure that there are no duplicated generic fields
proc newAnalyzedStruct*(resolved: ResolvedStruct, fields: seq[AnalyzedArgumentDefinition]): AnalyzedStruct =
  var fieldIndex: Table[Identifier, int]
  for id, field in fields:
    assert(field.name notin fieldIndex, "UNREACHABLE: duplicate field name must have been caught by resolver")
    fieldIndex[field.name] = id
  AnalyzedStruct(resolved: resolved, fields: fields, fieldIndex: fieldIndex)

proc resolved*(s: AnalyzedStruct): ResolvedStruct = s.resolved
proc loc*(s: AnalyzedStruct): Location = s.resolved.loc
proc fields*(s: AnalyzedStruct): seq[AnalyzedArgumentDefinition] = s.fields
proc findField*(s: AnalyzedStruct, name: Identifier): Result[AnalyzedArgumentDefinition, string] =
  if name in s.fieldIndex: ok(s.fields[s.fieldIndex[name]])
  else: err(fmt"{name.loc} field `{name.asl}` does not exist")

proc analyzeStruct*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, struct: ResolvedStruct): Result[AnalyzedStruct, string] =
  var analyzedFields: seq[AnalyzedArgumentDefinition]
  for field in struct.fields:
    let analyzedField = ? analyzeArgumentDefinition(app, file, fileScope, module, field)
    analyzedFields.add(analyzedField)
  ok(newAnalyzedStruct(struct, analyzedFields))

# AnalyzedVariant
type AnalyzedVariant* = ref object
  resolved: ResolvedVariant
  fields: seq[AnalyzedArgumentDefinition]
  fieldIndex: Table[Identifier, int]

# TODO: Ensure that there are no duplicated generic fields
proc newAnalyzedVariant*(resolved: ResolvedVariant, fields: seq[AnalyzedArgumentDefinition]): AnalyzedVariant =
  var fieldIndex: Table[Identifier, int]
  for id, field in fields:
    assert(field.name notin fieldIndex, "UNREACHABLE: duplicate field name must have been caught by resolver")
    fieldIndex[field.name] = id
  AnalyzedVariant(resolved: resolved, fields: fields, fieldIndex: fieldIndex)

proc name*(v: AnalyzedVariant): Identifier = v.resolved.name
proc resolved*(v: AnalyzedVariant): ResolvedVariant = v.resolved
proc fields*(v: AnalyzedVariant): seq[AnalyzedArgumentDefinition] = v.fields
proc findField*(v: AnalyzedVariant, name: Identifier): Result[AnalyzedArgumentDefinition, string] =
  if name in v.fieldIndex: ok(v.fields[v.fieldIndex[name]])
  else: err(fmt"{name.loc} field `{name.asl}` does not exist")

proc analyzeVariant(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, variant: ResolvedVariant): Result[AnalyzedVariant, string] =
  var analyzedFields: seq[AnalyzedArgumentDefinition]
  for field in variant.fields:
    let analyzedField = ? analyzeArgumentDefinition(app, file, fileScope, module, field)
    analyzedFields.add(analyzedField)
  ok(newAnalyzedVariant(variant, analyzedFields))

# AnalyzedUnion
type AnalyzedUnion* = ref object
  resolved: ResolvedUnion
  variants: seq[AnalyzedVariant]
  variantIndex: Table[Identifier, int]

proc newAnalyzedUnion*(resolved: ResolvedUnion, variants: seq[AnalyzedVariant]): AnalyzedUnion =
  var variantIndex: Table[Identifier, int]
  for id, variant in variants:
    assert(variant.name notin variantIndex, "UNREACHABLE: this should have been caught in resolution")
    variantIndex[variant.name] = id
  AnalyzedUnion(resolved: resolved, variants: variants, variantIndex: variantIndex)

proc resolved*(u: AnalyzedUnion): ResolvedUnion = u.resolved
proc variants*(u: AnalyzedUnion): seq[AnalyzedVariant] = u.variants

proc findVariant*(union: AnalyzedUnion, variant: Identifier): Result[AnalyzedVariant, string] =
  if variant in union.variantIndex: ok(union.variants[union.variantIndex[variant]])
  else: err(fmt"{variant.loc} union does not contain variant `{variant.asl}`")

proc analyzeUnion*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, union: ResolvedUnion): Result[AnalyzedUnion, string] =
  var analyzedVariants: seq[AnalyzedVariant]
  for variant in union.variants:
    let analyzedVariant = ? analyzeVariant(app, file, fileScope, module, variant)
    analyzedVariants.add(analyzedVariant)
  ok(newAnalyzedUnion(union, analyzedVariants))

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

proc analyzeData*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, data: ResolvedData): Result[AnalyzedData, string] =
  case data.kind:
  of rdkLiteral:
    ok(newAnalyzedData(newAnalyzedLiteralBlock(data.literal)))
  of rdkStruct:
    let analyzedStruct = ? analyzeStruct(app, file, fileScope, module, data.struct)
    ok(newAnalyzedData(analyzedStruct))
  of rdkUnion:
    let analyzedUnion = ? analyzeUnion(app, file, fileScope, module, data.union)
    ok(newAnalyzedData(analyzedUnion))
