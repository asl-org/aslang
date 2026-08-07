## ResolvedArgumentDef — a named argument whose type has been resolved.
## Independent of the funcdef/extern layer; both re-use it.

import strformat, hashes

import ./parser
import argtype

type ResolvedArgumentDef* = ref object
  parsed: ArgumentDef
  argType: ResolvedArgumentType

proc newResolvedArgumentDef*(parsed: ArgumentDef,
    argType: ResolvedArgumentType): ResolvedArgumentDef =
  ResolvedArgumentDef(parsed: parsed, argType: argType)

proc name*(d: ResolvedArgumentDef): Identifier = d.parsed.name
proc argType*(d: ResolvedArgumentDef): ResolvedArgumentType = d.argType
proc loc*(d: ResolvedArgumentDef): Location = d.argType.loc
proc hash*(d: ResolvedArgumentDef): Hash = d.argType.hash
proc `==`*(a, b: ResolvedArgumentDef): bool = a.hash == b.hash
proc asl*(argDef: ResolvedArgumentDef): string =
  fmt"{argDef.name.asl}: {argDef.argType.asl}"

proc concrete*(argDef: ResolvedArgumentDef, concrete: ResolvedArgumentType, generic: Generic): ResolvedArgumentDef =
  let concreteArgType = argDef.argType.concrete(concrete, generic)
  newResolvedArgumentDef(argDef.parsed, concreteArgType)
