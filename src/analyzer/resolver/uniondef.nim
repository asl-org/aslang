## ResolvedUnionDef — a union definition, indexed by variant name and
## by required impl set.

import results, strformat, tables

import ./parser
import argtype  # ResolvedGenericArgumentType lives here
import variantdef

type ResolvedUnionDef* = ref object
  parsed: UnionDef
  variants: seq[ResolvedVariant]
  variantIndex: Table[Identifier, int]
  genericTypeIndex: Table[ResolvedGenericArgumentType, int]

proc newResolvedUnionDef*(parsed: UnionDef, variants: seq[ResolvedVariant],
    genericTypeIndex: Table[ResolvedGenericArgumentType, int]): ResolvedUnionDef =
  var variantIndex: Table[Identifier, int]
  for id, variant in variants:
    assert(variant.parsed.name notin variantIndex, "UNREACHABLE: duplicate variant — should have been caught in parser")
    variantIndex[variant.parsed.name] = id
  ResolvedUnionDef(parsed: parsed, variants: variants, variantIndex: variantIndex, genericTypeIndex: genericTypeIndex)

proc parsed*(union: ResolvedUnionDef): UnionDef = union.parsed
proc variants*(union: ResolvedUnionDef): seq[ResolvedVariant] = union.variants
proc genericTypeIndex*(union: ResolvedUnionDef): Table[ResolvedGenericArgumentType, int] = union.genericTypeIndex
proc variantIndex*(union: ResolvedUnionDef): Table[Identifier, int] = union.variantIndex
proc loc*(union: ResolvedUnionDef): Location = union.parsed.loc

proc findVariant*(union: ResolvedUnionDef, variant: Identifier): Result[ResolvedVariant, string] =
  if variant in union.variantIndex: ok(union.variants[union.variantIndex[variant]])
  else: err(fmt"{variant.loc} union does not contain variant `{variant.asl}`")

proc requires*(union: ResolvedUnionDef): seq[ResolvedGenericArgumentType] =
  ## One union scope: a generic name shared across variants is one
  ## shared type parameter (Rust style), so dedup by underlying Generic
  ## identity. Within-variant duplicates are already impossible
  ## (caught by validateUniqueGenericFields in resolveVariant).
  var requires = newSeq[ResolvedGenericArgumentType](union.genericTypeIndex.len)
  for genericType, index in union.genericTypeIndex:
    requires[index] = genericType
  return requires
