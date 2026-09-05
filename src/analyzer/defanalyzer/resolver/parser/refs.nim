import strformat, strutils, sequtils

import ./tokenizer/index

import ./identifiers
import ./argtype

# ----------------- StructRef -----------------
# Wraps the receiver arg-type: module root plus a (possibly empty)
# impls list. Empty impls === the user wrote `Module { ... }`; non-empty
# impls === the user wrote `Module[Impl, ...] { ... }`. The parser no
# longer discriminates between the two surface forms — downstream layers
# initialise their AnalyzedImplMap from the impls seq directly (empty
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

# ----------------- UnionRef -----------------
# The receiver arg-type (module root + possibly-empty impls) plus the
# variant name — the `LocalType[.Impls].Variant` production. Empty impls
# === the bare surface form; downstream layers initialise their
# AnalyzedImplMap from the impls seq directly.
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
