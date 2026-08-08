## Phase-A `AnalyzedVariantDef` — a resolved union variant + its
## fully-analyzed field defs. `concrete*` takes the enclosing
## union's `genericTypeIndex` explicitly (unions share one across
## variants — per resolver's inference walk).

import results, strformat, tables

import ./resolver
import ./argdef

type AnalyzedVariantDef* = ref object
  resolved: ResolvedVariantDef
  fields: seq[AnalyzedArgumentDef]
  fieldIndex: Table[Identifier, int]

proc newAnalyzedVariantDef*(resolved: ResolvedVariantDef,
    fields: seq[AnalyzedArgumentDef]): AnalyzedVariantDef =
  AnalyzedVariantDef(resolved: resolved, fields: fields, fieldIndex: fields.indexByName())

proc name*(v: AnalyzedVariantDef): Identifier = v.resolved.name

proc findField*(v: AnalyzedVariantDef, name: Identifier): Result[AnalyzedArgumentDef, string] =
  if name in v.fieldIndex: ok(v.fields[v.fieldIndex[name]])
  else: err(fmt"{name.loc} field `{name.asl}` does not exist")
