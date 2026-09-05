import strformat, sequtils, strutils, tables, results

import ../tokenizer/index
import ./error

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

# ============================================================
# ArgumentDef (name: ArgumentType)
# ============================================================

type ArgumentDef* = ref object
  name: Identifier
  argType: ArgumentType
  loc: Location

proc newArgumentDef*(name: Identifier, argType: ArgumentType): ArgumentDef =
  ArgumentDef(name: name, argType: argType)

proc loc*(argDef: ArgumentDef): Location = argDef.name.loc
proc name*(argDef: ArgumentDef): Identifier = argDef.name
proc argType*(argDef: ArgumentDef): ArgumentType = argDef.argType

proc asl*(argDef: ArgumentDef): string =
  fmt"{argDef.name.asl}: {argDef.argType.asl}"

# ============================================================
# ArgumentDefList ((name: T, name: T, ...))
# ============================================================

type ArgumentDefList* = ref object
  argDefs: seq[ArgumentDef]
  argNameIndex: Table[Identifier, int]
  loc: Location

proc buildArgumentNameIndex(argDefs: seq[ArgumentDef]): Result[Table[Identifier, int], ParserError] =
  var argNameIndex: Table[Identifier, int]
  for index, argDef in argDefs:
    if argDef.name in argNameIndex:
      let prev = argDefs[argNameIndex[argDef.name]]
      let msg = fmt"duplicate argument encountered, see previous declaration at {prev.loc}"
      return err(newParserError(msg, argDef.loc))
    argNameIndex[argDef.name] = index
  ok(argNameIndex)

proc newArgumentDefList*(argDefs: seq[ArgumentDef],
    loc: Location): Result[ArgumentDefList, ParserError] =
  let argNameIndex = ? buildArgumentNameIndex(argDefs)
  ok(ArgumentDefList(argDefs: argDefs, argNameIndex: argNameIndex, loc: loc))

proc argDefs*(argDefList: ArgumentDefList): seq[ArgumentDef] = argDefList.argDefs
proc arity*(argDefList: ArgumentDefList): int = argDefList.argDefs.len

proc asl*(argDefList: ArgumentDefList): string =
  let content = argDefList.argDefs.mapIt(asl(it)).join(", ")
  return fmt"({content})"
