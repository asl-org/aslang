## Phase-A `AnalyzedLiteralDef` — thin wrapper around a
## `ResolvedLiteralDef`. Literal blocks carry no field types, so
## analysis is a no-op — the wrapper exists so `AnalyzedData` can
## discriminate uniformly over literal / struct / union.

import ./resolver

type AnalyzedLiteralDef* = ref object
  resolved: ResolvedLiteralDef

proc newAnalyzedLiteralDef*(resolved: ResolvedLiteralDef): AnalyzedLiteralDef =
  AnalyzedLiteralDef(resolved: resolved)

proc resolved*(b: AnalyzedLiteralDef): ResolvedLiteralDef = b.resolved
