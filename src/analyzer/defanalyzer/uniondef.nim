## Phase-A `AnalyzedUnionDef` — a resolved union + its fully-analyzed
## variants. Delegates `genericTypeIndex` to the resolver's already-
## computed table (Rust-style dedup across variants happens in the
## resolver); `concrete*(impls)` distributes the impls to every
## variant via each variant's own `concrete`.

import tables

import ./resolver
import ./variantdef

type AnalyzedUnionDef* = ref object
  resolved: ResolvedUnionDef
  variants: seq[AnalyzedVariantDef]
  variantIndex: Table[Identifier, int]

proc newAnalyzedUnionDef*(resolved: ResolvedUnionDef, variants: seq[AnalyzedVariantDef]): AnalyzedUnionDef =
  AnalyzedUnionDef(resolved: resolved, variants: variants, variantIndex: variants.indexByName())

proc variants*(u: AnalyzedUnionDef): seq[AnalyzedVariantDef] = u.variants
proc genericTypeIndex*(u: AnalyzedUnionDef): Table[ResolvedGenericArgumentType, int] =
  u.resolved.genericTypeIndex

proc findVariant*(union: AnalyzedUnionDef, name: Identifier): AnalyzedVariantDef =
  assert(name in union.variantIndex, "UNREACHABLE: duplicate variant name must have been caught by resolver")
  union.variants[union.variantIndex[name]]
