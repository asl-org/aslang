## ResolvedLiteralInitializer — a primitive literal typed against a
## resolved argument type (e.g. `u32 42`). Leaf node.

import ./parser
import argtype

type ResolvedLiteralInitializer* = ref object
  parsed: LiteralInitializer
  argType: ResolvedArgumentType

proc newResolvedLiteralInitializer*(parsed: LiteralInitializer,
    argType: ResolvedArgumentType): ResolvedLiteralInitializer =
  ResolvedLiteralInitializer(parsed: parsed, argType: argType)

proc parsed*(init: ResolvedLiteralInitializer): LiteralInitializer = init.parsed
proc argType*(init: ResolvedLiteralInitializer): ResolvedArgumentType = init.argType
proc value*(init: ResolvedLiteralInitializer): Literal = init.parsed.value
proc loc*(init: ResolvedLiteralInitializer): Location = init.parsed.loc
proc literal*(init: ResolvedLiteralInitializer): Literal = init.parsed.value
