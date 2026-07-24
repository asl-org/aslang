## Phase-A `AnalyzedLiteralBlock` — thin wrapper around a
## `ResolvedLiteralDef`. Literal blocks carry no field types, so
## analysis is a no-op — the wrapper exists so `AnalyzedData` can
## discriminate uniformly over literal / struct / union.

import ./resolver

type AnalyzedLiteralBlock* = ref object
  resolved: ResolvedLiteralDef

proc newAnalyzedLiteralBlock*(resolved: ResolvedLiteralDef): AnalyzedLiteralBlock =
  AnalyzedLiteralBlock(resolved: resolved)

proc resolved*(b: AnalyzedLiteralBlock): ResolvedLiteralDef = b.resolved
