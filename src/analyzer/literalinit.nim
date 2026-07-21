## AnalyzedLiteralInitializer — a literal token together with the
## concrete argument type it takes on (via expected-context adoption or
## the bare-literal default in `analyzeBareLiteral`). Independent of
## the mutually-recursive expression/statement cluster.

import ./resolver
import argtype

type AnalyzedLiteralInitializer* = ref object
  literal: Literal
  argType: AnalyzedArgumentType

proc newAnalyzedLiteralInitializer*(literal: Literal, argType: AnalyzedArgumentType): AnalyzedLiteralInitializer =
  AnalyzedLiteralInitializer(literal: literal, argType: argType)

proc loc*(init: AnalyzedLiteralInitializer): Location = init.literal.loc
proc argType*(init: AnalyzedLiteralInitializer): AnalyzedArgumentType = init.argType
