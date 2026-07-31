## Phase-A `AnalyzedUnionDef` — a resolved union + its fully-analyzed
## variants. Delegates `genericTypeIndex` to the resolver's already-
## computed table (Rust-style dedup across variants happens in the
## resolver); `concrete*(impls)` distributes the impls to every
## variant via each variant's own `concrete`.

import results, strformat, tables

import ./resolver
import ./argtype
import ./variantdef

type AnalyzedUnionDef* = ref object
  resolved: ResolvedUnionDef
  variants: seq[AnalyzedVariantDef]
  variantIndex: Table[Identifier, int]

proc newAnalyzedUnionDef*(resolved: ResolvedUnionDef, variants: seq[AnalyzedVariantDef]): AnalyzedUnionDef =
  var variantIndex: Table[Identifier, int]
  for id, variant in variants:
    assert(variant.name notin variantIndex,
      "UNREACHABLE: duplicate variant name must have been caught by resolver")
    variantIndex[variant.name] = id
  AnalyzedUnionDef(resolved: resolved, variants: variants, variantIndex: variantIndex)

proc resolved*(u: AnalyzedUnionDef): ResolvedUnionDef = u.resolved
proc variants*(u: AnalyzedUnionDef): seq[AnalyzedVariantDef] = u.variants
proc genericTypeIndex*(u: AnalyzedUnionDef): Table[ResolvedGenericArgumentType, int] =
  u.resolved.genericTypeIndex

proc findVariant*(union: AnalyzedUnionDef, name: Identifier): Result[AnalyzedVariantDef, string] =
  if name in union.variantIndex: ok(union.variants[union.variantIndex[name]])
  else: err(fmt"{name.loc} union does not contain variant `{name.asl}`")

proc concrete*(union: AnalyzedUnionDef,
    impls: seq[AnalyzedArgumentType]): AnalyzedUnionDef =
  var concreteVariants: seq[AnalyzedVariantDef]
  for variant in union.variants:
    concreteVariants.add(variant.concrete(impls, union.resolved.genericTypeIndex))
  newAnalyzedUnionDef(union.resolved, concreteVariants)
