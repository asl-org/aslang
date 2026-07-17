import strformat, sequtils, strutils

import ./tokenizer

import ./identifiers

# ============================================================
# ArgumentType (self-recursive: List[Map[String, Int]])
# ============================================================

type ArgumentType* = ref object
  root: Identifier
  impls: seq[ArgumentType]

proc newArgumentType*(root: Identifier): ArgumentType =
  ArgumentType(root: root)

proc newArgumentType*(root: Identifier, impls: seq[ArgumentType]): ArgumentType =
  ArgumentType(root: root, impls: impls)

proc loc*(a: ArgumentType): Location = a.root.loc
proc root*(a: ArgumentType): Identifier = a.root
proc impls*(a: ArgumentType): seq[ArgumentType] = a.impls

proc asl*(argType: ArgumentType): string =
  var content = argType.root.asl
  let impls = argType.impls.mapIt(asl(it)).join(", ")
  if impls != "": content.add(fmt"[{impls}]")
  return content