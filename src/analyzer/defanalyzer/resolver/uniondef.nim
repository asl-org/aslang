## ResolvedUnionDef — a union definition, indexed by variant name and
## by required impl set.

import results, sequtils, sets, strformat, tables

import ./parser
import ./indexing
import argtype  # ResolvedGenericArgumentType lives here
import variantdef

proc buildGenericTypeIndex(generics: seq[ResolvedGenericArgumentType]): Table[ResolvedGenericArgumentType, int] =
  var genericTypeIndex: Table[ResolvedGenericArgumentType, int]
  for id, generic in generics:
    genericTypeIndex[generic] = id
  return genericTypeIndex

proc buildGenerics(variants: seq[ResolvedVariantDef]): seq[ResolvedGenericArgumentType] =
  var generics: OrderedSet[ResolvedGenericArgumentType]
  for variant in variants:
    for generic in variant.requires:
      generics.incl(generic)
  return generics.toSeq

type ResolvedUnionDef* = ref object
  parsed: UnionDef
  generics: seq[ResolvedGenericArgumentType]
  variants: seq[ResolvedVariantDef]
  variantIndex: Table[Identifier, int]

proc newResolvedUnionDef*(parsed: UnionDef, variants: seq[ResolvedVariantDef]): ResolvedUnionDef =
  let variantIndex = variants.indexByName()
  let generics = buildGenerics(variants)
  ResolvedUnionDef(parsed: parsed, variants: variants, generics: generics, variantIndex: variantIndex)

proc variants*(union: ResolvedUnionDef): seq[ResolvedVariantDef] = union.variants
proc requires*(union: ResolvedUnionDef): seq[ResolvedGenericArgumentType] = union.generics
proc genericTypeIndex*(union: ResolvedUnionDef): Table[ResolvedGenericArgumentType, int] = buildGenericTypeIndex(union.generics)

proc findVariant*(union: ResolvedUnionDef, variant: Identifier): Result[ResolvedVariantDef, string] =
  if variant in union.variantIndex: ok(union.variants[union.variantIndex[variant]])
  else: err(fmt"{variant.loc} union does not contain variant `{variant.asl}`")

proc findVariant*(union: ResolvedUnionDef, variant: VariantDef): ResolvedVariantDef =
  ## Identity form — the resolver already located this variant on the
  ## parser-side union at ref-resolve time, so the resolved twin
  ## cannot miss.
  assert(variant.name in union.variantIndex, fmt"[BUG] - {variant.loc} variant `{variant.name.asl}` missing from the resolved union")
  union.variants[union.variantIndex[variant.name]]

