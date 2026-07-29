import strformat, strutils, sequtils

import ./tokenizer

import ./identifiers
import ./argtype

# ----------------- StructRef -----------------
# One shape: the receiver module identifier plus a (possibly empty)
# impls list. Empty impls === the user wrote `Module { ... }`; non-empty
# impls === the user wrote `Module[Impl, ...] { ... }`. The parser no
# longer discriminates between the two surface forms — downstream layers
# initialise their GenericImplMap from the impls seq directly (empty
# seq → empty map, non-empty → pre-populated).
type StructRef* = ref object
  argType: ArgumentType

proc newStructRef*(argType: ArgumentType): StructRef =
  StructRef(argType: argType)

proc module*(s: StructRef): Identifier = s.argType.root
proc impls*(s: StructRef): seq[ArgumentType] = s.argType.impls
proc argType*(s: StructRef): ArgumentType = s.argType
proc loc*(s: StructRef): Location = s.argType.loc
proc asl*(s: StructRef): string =
  if s.impls.len == 0:
    asl(s.module)
  else:
    let inner = s.impls.mapIt(asl(it)).join(", ")
    fmt"{asl(s.module)}[{inner}]"
