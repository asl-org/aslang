import strformat, strutils, sequtils

import ./tokenizer

import ./identifiers
import ./argtype

# ----------------- UnionRef -----------------
# Mirror of StructRef: same one-shape module+impls layout.
type UnionRef* = ref object
  module: Identifier
  impls: seq[ArgumentType]
  loc: Location

proc newUnionRef*(module: Identifier, impls: seq[ArgumentType],
    loc: Location): UnionRef =
  UnionRef(module: module, impls: impls, loc: loc)

proc module*(u: UnionRef): Identifier = u.module
proc impls*(u: UnionRef): seq[ArgumentType] = u.impls
proc loc*(u: UnionRef): Location = u.loc
proc asl*(u: UnionRef): string =
  if u.impls.len == 0:
    asl(u.module)
  else:
    let inner = u.impls.mapIt(asl(it)).join(", ")
    fmt"{asl(u.module)}[{inner}]"
