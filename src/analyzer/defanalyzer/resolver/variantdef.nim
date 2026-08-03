## ResolvedVariant — one branch of a resolved union: the parser
## VariantDef together with its resolved fields.

import results, sets, strformat, tables

import ./parser
import argtype
import argdef

proc buildFieldIndex(fields: seq[ResolvedArgumentDef]): Table[Identifier, int] =
  var fieldIndex: Table[Identifier, int]
  for id, field in fields:
    assert(field.name notin fieldIndex, "[BUG] - Parser rejects duplicate field names")
    fieldIndex[field.name] = id
  return fieldIndex

proc buildGenerics(fields: seq[ResolvedArgumentDef]): seq[ResolvedGenericArgumentType] =
  var genericSet: HashSet[ResolvedGenericArgumentType]
  var generics: seq[ResolvedGenericArgumentType]
  for field in fields:
    case field.argType.kind:
    of ratkModule: discard
    of ratkGeneric:
      let generic = field.argType.generic
      if generic notin genericSet:
        generics.add(generic)
        genericSet.incl(generic)
  return generics

type ResolvedVariant* = ref object
  parsed: VariantDef
  fields: seq[ResolvedArgumentDef]
  generics: seq[ResolvedGenericArgumentType]
  fieldIndex: Table[Identifier, int]

proc newResolvedVariantDef*(parsed: VariantDef, fields: seq[ResolvedArgumentDef]): ResolvedVariant =
  let fieldIndex = buildFieldIndex(fields)
  let generics = buildGenerics(fields)
  ResolvedVariant(parsed: parsed, fields: fields, generics: generics, fieldIndex: fieldIndex)

proc loc*(variant: ResolvedVariant): Location = variant.parsed.loc
proc name*(variant: ResolvedVariant): Identifier = variant.parsed.name
proc parsed*(variant: ResolvedVariant): VariantDef = variant.parsed
proc fields*(variant: ResolvedVariant): seq[ResolvedArgumentDef] = variant.fields
proc requires*(variant: ResolvedVariant): seq[ResolvedGenericArgumentType] = variant.generics
proc fieldIndex*(variant: ResolvedVariant): Table[Identifier, int] = variant.fieldIndex

proc findField*(variant: ResolvedVariant, name: Identifier): Result[ResolvedArgumentDef, string] =
  if name in variant.fieldIndex: ok(variant.fields[variant.fieldIndex[name]])
  else: err(fmt"{name.loc} field `{name.asl}` does not exist")
