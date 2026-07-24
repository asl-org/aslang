## Phase-A `AnalyzedVariant` — a resolved union variant + its
## fully-analyzed field defs. `concrete*` takes the enclosing
## union's `genericTypeIndex` explicitly (unions share one across
## variants — per resolver's inference walk).

import results, strformat, tables

import ./resolver
import ./argtype
import ./argdef

type AnalyzedVariant* = ref object
  resolved: ResolvedVariant
  fields: seq[AnalyzedArgumentDefinition]
  fieldIndex: Table[Identifier, int]

proc newAnalyzedVariant*(resolved: ResolvedVariant,
    fields: seq[AnalyzedArgumentDefinition]): AnalyzedVariant =
  var fieldIndex: Table[Identifier, int]
  for id, field in fields:
    assert(field.name notin fieldIndex,
      "UNREACHABLE: duplicate field name must have been caught by resolver")
    fieldIndex[field.name] = id
  AnalyzedVariant(resolved: resolved, fields: fields, fieldIndex: fieldIndex)

proc resolved*(v: AnalyzedVariant): ResolvedVariant = v.resolved
proc name*(v: AnalyzedVariant): Identifier = v.resolved.name
proc fields*(v: AnalyzedVariant): seq[AnalyzedArgumentDefinition] = v.fields

proc findField*(v: AnalyzedVariant, name: Identifier): Result[AnalyzedArgumentDefinition, string] =
  if name in v.fieldIndex: ok(v.fields[v.fieldIndex[name]])
  else: err(fmt"{name.loc} field `{name.asl}` does not exist")

proc concrete*(variant: AnalyzedVariant,
    impls: seq[AnalyzedArgumentType],
    genericTypeIndex: Table[ResolvedGenericArgumentType, int]): AnalyzedVariant =
  var concreteFields: seq[AnalyzedArgumentDefinition]
  for field in variant.fields:
    concreteFields.add(field.concrete(impls, genericTypeIndex))
  newAnalyzedVariant(variant.resolved, concreteFields)
