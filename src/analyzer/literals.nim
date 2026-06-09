## Analyzed literal block — currently just wraps the resolved literal
## type; future analyzer work may attach inferred-type / coercion data.

import resolver

type AnalyzedLiteralBlock* = ref object
  resolved: ResolvedLiteralType

proc newAnalyzedLiteralBlock*(resolved: ResolvedLiteralType): AnalyzedLiteralBlock =
  AnalyzedLiteralBlock(resolved: resolved)

proc resolved*(b: AnalyzedLiteralBlock): ResolvedLiteralType = b.resolved
