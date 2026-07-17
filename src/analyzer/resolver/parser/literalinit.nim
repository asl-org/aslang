import strformat

import ./tokenizer

import ./literals
import ./argtype

# ============================================================
# LiteralInitializer
# ============================================================

type LiteralInitializer* = ref object
  argType: ArgumentType
  value: Literal
  loc: Location

proc newLiteralInitializer*(argType: ArgumentType, value: Literal, loc: Location): LiteralInitializer =
  LiteralInitializer(argType: argType, value: value, loc: loc)

proc loc*(literalInit: LiteralInitializer): Location = literalInit.loc
proc argType*(literalInit: LiteralInitializer): ArgumentType = literalInit.argType
proc value*(literalInit: LiteralInitializer): Literal = literalInit.value

proc asl*(prim: LiteralInitializer): string =
  fmt"{asl(prim.argType)} {asl(prim.value)}"
