## Phase-A `AnalyzedVariantDef` — a resolved union variant + its
## fully-analyzed field defs. `concrete*` takes the enclosing
## union's `genericTypeIndex` explicitly (unions share one across
## variants — per resolver's inference walk).

import results, strformat, tables

import ./resolver
import ./argtype
import ./argdef

type AnalyzedVariantDef* = ref object
  resolved: ResolvedVariantDef
  fields: seq[AnalyzedArgumentDefinition]
  fieldIndex: Table[Identifier, int]

proc newAnalyzedVariantDef*(resolved: ResolvedVariantDef,
    fields: seq[AnalyzedArgumentDefinition]): AnalyzedVariantDef =
  var fieldIndex: Table[Identifier, int]
  for id, field in fields:
    assert(field.name notin fieldIndex,
      "UNREACHABLE: duplicate field name must have been caught by resolver")
    fieldIndex[field.name] = id
  AnalyzedVariantDef(resolved: resolved, fields: fields, fieldIndex: fieldIndex)

proc resolved*(v: AnalyzedVariantDef): ResolvedVariantDef = v.resolved
proc name*(v: AnalyzedVariantDef): Identifier = v.resolved.name
proc fields*(v: AnalyzedVariantDef): seq[AnalyzedArgumentDefinition] = v.fields

proc findField*(v: AnalyzedVariantDef, name: Identifier): Result[AnalyzedArgumentDefinition, string] =
  if name in v.fieldIndex: ok(v.fields[v.fieldIndex[name]])
  else: err(fmt"{name.loc} field `{name.asl}` does not exist")

proc concrete*(variant: AnalyzedVariantDef,
    impls: seq[AnalyzedArgumentType],
    genericTypeIndex: Table[ResolvedGenericArgumentType, int]): AnalyzedVariantDef =
  var concreteFields: seq[AnalyzedArgumentDefinition]
  for field in variant.fields:
    concreteFields.add(field.concrete(impls, genericTypeIndex))
  newAnalyzedVariantDef(variant.resolved, concreteFields)
