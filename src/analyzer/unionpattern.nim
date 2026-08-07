## AnalyzedUnionPattern — a resolved union-variant pattern together
## with the bindings its fields introduce into scope. Independent of
## the outer AnalyzedCasePattern union — a union pattern is one of the
## three shapes the case pattern can take.

import ./defanalyzer
import binding

type AnalyzedUnionPattern* = ref object
  resolved: UnionPattern
  variant: AnalyzedVariantDef
  bindings: seq[AnalyzedBinding]

proc newAnalyzedUnionPattern*(resolved: UnionPattern, variant: AnalyzedVariantDef, bindings: seq[AnalyzedBinding]): AnalyzedUnionPattern =
  AnalyzedUnionPattern(resolved: resolved, variant: variant, bindings: bindings)

proc bindings*(pattern: AnalyzedUnionPattern): seq[AnalyzedBinding] = pattern.bindings
