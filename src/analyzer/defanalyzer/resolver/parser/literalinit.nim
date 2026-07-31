import strformat

import ./tokenizer

import ./identifiers
import ./literals
import ./argtype

# ============================================================
# LiteralInitializer
# ============================================================

type LiteralInitializer* = ref object
  argType: ArgumentType
  value: Literal

proc newLiteralInitializer*(argType: ArgumentType, value: Literal): LiteralInitializer =
  LiteralInitializer(argType: argType, value: value)

proc loc*(init: LiteralInitializer): Location = init.argType.loc
proc module*(init: LiteralInitializer): Identifier = init.argType.root
proc argType*(init: LiteralInitializer): ArgumentType = init.argType
proc value*(init: LiteralInitializer): Literal = init.value

proc asl*(init: LiteralInitializer): string =
  fmt"{init.argType.asl} {init.value.asl}"
