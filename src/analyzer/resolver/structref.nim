## ResolvedStructRef — a parser StructRef with its (arity- and
## constraint-validated) impl list. Leaf node in the body cluster.
## Reused by ResolvedStructInitializer.

import ./parser
import argtype

type ResolvedStructRef* = ref object
  parsed: StructRef
  argType: ResolvedModuleArgumentType

proc newResolvedStructRef*(parsed: StructRef, argType: ResolvedModuleArgumentType): ResolvedStructRef =
  ResolvedStructRef(parsed: parsed, argType: argType)

proc parsed*(s: ResolvedStructRef): StructRef = s.parsed
proc module*(s: ResolvedStructRef): Module = s.argType.module
proc impls*(s: ResolvedStructRef): seq[ResolvedArgumentType] = s.argType.impls
proc loc*(s: ResolvedStructRef): Location = s.parsed.loc
