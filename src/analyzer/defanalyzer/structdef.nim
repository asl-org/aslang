## Phase-A `AnalyzedStructDef` — a resolved struct + its fully-analyzed
## field defs. Delegates `genericTypeIndex` to the resolver's
## already-computed table; `concrete*(impls)` substitutes the impls
## through each field via `AnalyzedArgumentDef.concrete`.

import results, strformat, tables

import ./resolver
import ./argtype
import ./argdef

type AnalyzedStructDef* = ref object
  resolved: ResolvedStructDef
  fields: seq[AnalyzedArgumentDef]
  fieldIndex: Table[Identifier, int]

proc newAnalyzedStructDef*(resolved: ResolvedStructDef,
    fields: seq[AnalyzedArgumentDef]): AnalyzedStructDef =
  var fieldIndex: Table[Identifier, int]
  for id, field in fields:
    assert(field.name notin fieldIndex,
      "UNREACHABLE: duplicate field name must have been caught by resolver")
    fieldIndex[field.name] = id
  AnalyzedStructDef(resolved: resolved, fields: fields, fieldIndex: fieldIndex)

proc resolved*(s: AnalyzedStructDef): ResolvedStructDef = s.resolved
proc loc*(s: AnalyzedStructDef): Location = s.resolved.loc
proc fields*(s: AnalyzedStructDef): seq[AnalyzedArgumentDef] = s.fields
proc genericTypeIndex(s: AnalyzedStructDef): Table[ResolvedGenericArgumentType, int] = s.resolved.genericTypeIndex

proc findField*(s: AnalyzedStructDef, name: Identifier): Result[AnalyzedArgumentDef, string] =
  if name in s.fieldIndex: ok(s.fields[s.fieldIndex[name]])
  else: err(fmt"{name.loc} field `{name.asl}` does not exist")

proc concrete*(struct: AnalyzedStructDef, impls: seq[AnalyzedArgumentType]): AnalyzedStructDef =
  var concreteFields: seq[AnalyzedArgumentDef]
  for field in struct.fields:
    concreteFields.add(field.concrete(impls, struct.resolved.genericTypeIndex))
  newAnalyzedStructDef(struct.resolved, concreteFields)
