## ResolvedUnionDef — a union definition, indexed by variant name and
## by required impl set.

import results, sets, strformat, tables

import ./parser
import argtype  # ResolvedGenericArgumentType lives here
import variantdef

proc buildGenericTypeIndex(generics: seq[ResolvedGenericArgumentType]): Table[ResolvedGenericArgumentType, int] =
  var genericTypeIndex: Table[ResolvedGenericArgumentType, int]
  for id, generic in generics:
    genericTypeIndex[generic] = id
  return genericTypeIndex

proc buildVariantIndex(variants: seq[ResolvedVariant]): Table[Identifier, int] =
  var variantIndex: Table[Identifier, int]
  for id, variant in variants:
    assert(variant.name notin variantIndex, "UNREACHABLE: duplicate variant — should have been caught in parser")
    variantIndex[variant.name] = id
  return variantIndex

proc buildGenerics(variants: seq[ResolvedVariant]): seq[ResolvedGenericArgumentType] =
  var genericSet: HashSet[ResolvedGenericArgumentType]
  var generics: seq[ResolvedGenericArgumentType]
  for variant in variants:
    for generic in variant.requires:
      if generic notin genericSet:
        generics.add(generic)
        genericSet.incl(generic)
  return generics

type ResolvedUnionDef* = ref object
  parsed: UnionDef
  generics: seq[ResolvedGenericArgumentType]
  variants: seq[ResolvedVariant]
  variantIndex: Table[Identifier, int]

proc newResolvedUnionDef*(parsed: UnionDef, variants: seq[ResolvedVariant]): ResolvedUnionDef =
  let variantIndex = buildVariantIndex(variants)
  let generics = buildGenerics(variants)
  ResolvedUnionDef(parsed: parsed, variants: variants, generics: generics, variantIndex: variantIndex)

proc loc*(union: ResolvedUnionDef): Location = union.parsed.loc
proc parsed*(union: ResolvedUnionDef): UnionDef = union.parsed
proc variants*(union: ResolvedUnionDef): seq[ResolvedVariant] = union.variants
proc requires*(union: ResolvedUnionDef): seq[ResolvedGenericArgumentType] = union.generics
proc variantIndex*(union: ResolvedUnionDef): Table[Identifier, int] = union.variantIndex
proc genericTypeIndex*(union: ResolvedUnionDef): Table[ResolvedGenericArgumentType, int] = buildGenericTypeIndex(union.generics)

proc findVariant*(union: ResolvedUnionDef, variant: Identifier): Result[ResolvedVariant, string] =
  if variant in union.variantIndex: ok(union.variants[union.variantIndex[variant]])
  else: err(fmt"{variant.loc} union does not contain variant `{variant.asl}`")

