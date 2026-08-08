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
  AnalyzedStructDef(resolved: resolved, fields: fields, fieldIndex: fields.indexByName())

proc genericTypeIndex(s: AnalyzedStructDef): Table[ResolvedGenericArgumentType, int] = s.resolved.genericTypeIndex

proc findField*(s: AnalyzedStructDef, name: Identifier): Result[AnalyzedArgumentDef, string] =
  if name in s.fieldIndex: ok(s.fields[s.fieldIndex[name]])
  else: err(fmt"{name.loc} field `{name.asl}` does not exist")

