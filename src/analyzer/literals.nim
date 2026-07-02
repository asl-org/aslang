## Analyzed literal block — currently just wraps the resolved literal
## type; future analyzer work may attach inferred-type / coercion data.

import resolver

type AnalyzedLiteralDef* = ref object
  resolved: ResolvedLiteralDef

proc newAnalyzedLiteralDef*(resolved: ResolvedLiteralDef): AnalyzedLiteralDef =
  AnalyzedLiteralDef(resolved: resolved)

proc resolved*(b: AnalyzedLiteralDef): ResolvedLiteralDef = b.resolved
