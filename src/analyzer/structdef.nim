## Phase-A `AnalyzedStruct` — a resolved struct + its fully-analyzed
## field defs. Delegates `genericTypeIndex` to the resolver's
## already-computed table; `concrete*(impls)` substitutes the impls
## through each field via `AnalyzedArgumentDefinition.concrete`.

import results, strformat, tables

import ./resolver
import ./argtype
import ./argdef

type AnalyzedStruct* = ref object
  resolved: ResolvedStructDef
  fields: seq[AnalyzedArgumentDefinition]
  fieldIndex: Table[Identifier, int]

proc newAnalyzedStruct*(resolved: ResolvedStructDef,
    fields: seq[AnalyzedArgumentDefinition]): AnalyzedStruct =
  var fieldIndex: Table[Identifier, int]
  for id, field in fields:
    assert(field.name notin fieldIndex,
      "UNREACHABLE: duplicate field name must have been caught by resolver")
    fieldIndex[field.name] = id
  AnalyzedStruct(resolved: resolved, fields: fields, fieldIndex: fieldIndex)

proc resolved*(s: AnalyzedStruct): ResolvedStructDef = s.resolved
proc loc*(s: AnalyzedStruct): Location = s.resolved.loc
proc fields*(s: AnalyzedStruct): seq[AnalyzedArgumentDefinition] = s.fields
proc genericTypeIndex*(s: AnalyzedStruct): Table[ResolvedGenericArgumentType, int] =
  s.resolved.genericTypeIndex

proc findField*(s: AnalyzedStruct, name: Identifier): Result[AnalyzedArgumentDefinition, string] =
  if name in s.fieldIndex: ok(s.fields[s.fieldIndex[name]])
  else: err(fmt"{name.loc} field `{name.asl}` does not exist")

proc concrete*(struct: AnalyzedStruct,
    impls: seq[AnalyzedArgumentType]): AnalyzedStruct =
  var concreteFields: seq[AnalyzedArgumentDefinition]
  for field in struct.fields:
    concreteFields.add(field.concrete(impls, struct.resolved.genericTypeIndex))
  newAnalyzedStruct(struct.resolved, concreteFields)
