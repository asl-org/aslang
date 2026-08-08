## Phase-A `AnalyzedStructDef` — a resolved struct + its fully-analyzed
## field defs. Delegates `genericTypeIndex` to the resolver's
## already-computed table; `concrete*(impls)` substitutes the impls
## through each field via `AnalyzedArgumentDef.concrete`.

import results, strformat, tables

import ./resolver
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

proc genericTypeIndex(s: AnalyzedStructDef): Table[ResolvedGenericArgumentType, int] = s.resolved.genericTypeIndex

proc findField*(s: AnalyzedStructDef, name: Identifier): Result[AnalyzedArgumentDef, string] =
  if name in s.fieldIndex: ok(s.fields[s.fieldIndex[name]])
  else: err(fmt"{name.loc} field `{name.asl}` does not exist")

