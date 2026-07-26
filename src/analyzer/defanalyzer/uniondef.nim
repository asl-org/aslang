## Phase-A `AnalyzedUnion` — a resolved union + its fully-analyzed
## variants. Delegates `genericTypeIndex` to the resolver's already-
## computed table (Rust-style dedup across variants happens in the
## resolver); `concrete*(impls)` distributes the impls to every
## variant via each variant's own `concrete`.

import results, strformat, tables

import ./resolver
import ./argtype
import ./variantdef

type AnalyzedUnion* = ref object
  resolved: ResolvedUnionDef
  variants: seq[AnalyzedVariant]
  variantIndex: Table[Identifier, int]

proc newAnalyzedUnion*(resolved: ResolvedUnionDef,
    variants: seq[AnalyzedVariant]): AnalyzedUnion =
  var variantIndex: Table[Identifier, int]
  for id, variant in variants:
    assert(variant.name notin variantIndex,
      "UNREACHABLE: duplicate variant name must have been caught by resolver")
    variantIndex[variant.name] = id
  AnalyzedUnion(resolved: resolved, variants: variants, variantIndex: variantIndex)

proc resolved*(u: AnalyzedUnion): ResolvedUnionDef = u.resolved
proc variants*(u: AnalyzedUnion): seq[AnalyzedVariant] = u.variants
proc genericTypeIndex*(u: AnalyzedUnion): Table[ResolvedGenericArgumentType, int] =
  u.resolved.genericTypeIndex

proc findVariant*(union: AnalyzedUnion, name: Identifier): Result[AnalyzedVariant, string] =
  if name in union.variantIndex: ok(union.variants[union.variantIndex[name]])
  else: err(fmt"{name.loc} union does not contain variant `{name.asl}`")

proc concrete*(union: AnalyzedUnion,
    impls: seq[AnalyzedArgumentType]): AnalyzedUnion =
  var concreteVariants: seq[AnalyzedVariant]
  for variant in union.variants:
    concreteVariants.add(variant.concrete(impls, union.resolved.genericTypeIndex))
  newAnalyzedUnion(union.resolved, concreteVariants)
