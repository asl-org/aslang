## Analyzed literal block — currently just wraps the resolved literal
## type; future analyzer work may attach inferred-type / coercion data.

import resolver

type AnalyzedLiteralBlock* = ref object
  literal: ResolvedLiteralType

proc newAnalyzedLiteralBlock*(literal: ResolvedLiteralType): AnalyzedLiteralBlock =
  AnalyzedLiteralBlock(literal: literal)

proc literal*(b: AnalyzedLiteralBlock): ResolvedLiteralType = b.literal
