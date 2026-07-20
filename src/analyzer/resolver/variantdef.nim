## ResolvedVariant — one branch of a resolved union: the parser
## VariantDef together with its resolved fields.

import results, strformat, tables

import ./parser
import argdef

type ResolvedVariant* = ref object
  parsed: VariantDef
  fields: seq[ResolvedArgumentDef]
  fieldIndex: Table[Identifier, int]

proc newResolvedVariant*(parsed: VariantDef,
    fields: seq[ResolvedArgumentDef]): ResolvedVariant =
  var fieldIndex: Table[Identifier, int]
  for id, field in fields:
    assert(field.name notin fieldIndex, "UNREACHABLE: duplicate field name — should have been caught in parser")
    fieldIndex[field.name] = id
  ResolvedVariant(parsed: parsed, fields: fields, fieldIndex: fieldIndex)

proc parsed*(variant: ResolvedVariant): VariantDef = variant.parsed
proc fields*(variant: ResolvedVariant): seq[ResolvedArgumentDef] = variant.fields
proc fieldIndex*(variant: ResolvedVariant): Table[Identifier, int] = variant.fieldIndex
proc loc*(variant: ResolvedVariant): Location = variant.parsed.loc
proc name*(variant: ResolvedVariant): Identifier = variant.parsed.name

proc findField*(variant: ResolvedVariant, name: Identifier): Result[ResolvedArgumentDef, string] =
  if name in variant.fieldIndex: ok(variant.fields[variant.fieldIndex[name]])
  else: err(fmt"{name.loc} field `{name.asl}` does not exist")
