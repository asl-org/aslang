## ResolvedVariantDef — one branch of a resolved union: the parser
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

type ResolvedVariantDef* = ref object
  parsed: VariantDef
  fields: seq[ResolvedArgumentDef]
  generics: seq[ResolvedGenericArgumentType]
  fieldIndex: Table[Identifier, int]

proc newResolvedVariantDef*(parsed: VariantDef, fields: seq[ResolvedArgumentDef]): ResolvedVariantDef =
  let fieldIndex = buildFieldIndex(fields)
  let generics = buildGenerics(fields)
  ResolvedVariantDef(parsed: parsed, fields: fields, generics: generics, fieldIndex: fieldIndex)

proc name*(variant: ResolvedVariantDef): Identifier = variant.parsed.name
proc fields*(variant: ResolvedVariantDef): seq[ResolvedArgumentDef] = variant.fields
proc requires*(variant: ResolvedVariantDef): seq[ResolvedGenericArgumentType] = variant.generics

proc findField*(variant: ResolvedVariantDef, name: Identifier): Result[ResolvedArgumentDef, string] =
  if name in variant.fieldIndex: ok(variant.fields[variant.fieldIndex[name]])
  else: err(fmt"{name.loc} field `{name.asl}` does not exist")
