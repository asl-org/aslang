import strformat, strutils, sequtils

import ./tokenizer

import ./identifiers
import ./argtype

# ----------------- UnionRef -----------------
# The receiver arg-type (module root + possibly-empty impls) plus the
# variant name — the `Type[.Impls].Variant` production. Empty impls
# === the bare surface form; downstream layers initialise their
# GenericImplMap from the impls seq directly.
type UnionRef* = ref object
  argType: ArgumentType
  variant: Identifier

proc newUnionRef*(argType: ArgumentType, variant: Identifier): UnionRef =
  UnionRef(argType: argType, variant: variant)

proc module*(u: UnionRef): Identifier = u.argType.root
proc impls*(u: UnionRef): seq[ArgumentType] = u.argType.impls
proc loc*(u: UnionRef): Location = u.argType.loc
proc argType*(u: UnionRef): ArgumentType = u.argType
proc variant*(u: UnionRef): Identifier = u.variant
proc asl*(u: UnionRef): string =
  if u.impls.len == 0:
    fmt"{asl(u.module)}.{u.variant.asl}"
  else:
    let inner = u.impls.mapIt(asl(it)).join(", ")
    fmt"{asl(u.module)}[{inner}].{u.variant.asl}"
