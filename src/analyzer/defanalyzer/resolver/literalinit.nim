## ResolvedLiteralInitializer — a primitive literal typed against a
## resolved argument type (e.g. `u32 42`). Leaf node.

import ./parser
import argtype

type ResolvedLiteralInitializer* = ref object
  parsed: LiteralInitializer
  argType: ResolvedModuleArgumentType
  def: LiteralDef

proc newResolvedLiteralInitializer*(parsed: LiteralInitializer, argType: ResolvedModuleArgumentType, def: LiteralDef): ResolvedLiteralInitializer =
  ResolvedLiteralInitializer(parsed: parsed, argType: argType, def: def)

proc loc*(init: ResolvedLiteralInitializer): Location = init.parsed.loc
proc literal*(init: ResolvedLiteralInitializer): Literal = init.parsed.value
proc argType*(init: ResolvedLiteralInitializer): ResolvedModuleArgumentType = init.argType
