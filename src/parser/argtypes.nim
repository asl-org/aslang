import strformat, options, tables, results

import ./tokenizer
import ./combinators
import ./identifiers

# ============================================================
# ArgumentType (self-recursive: List[Map[String, Int]])
# ============================================================

type ArgumentType* = ref object
  root: Identifier
  impls: seq[ArgumentType]
  loc: Location

proc root*(a: ArgumentType): Identifier = a.root
proc impls*(a: ArgumentType): seq[ArgumentType] = a.impls
proc loc*(a: ArgumentType): Location = a.loc

proc newArgumentType*(root: Identifier, loc: Location): ArgumentType =
  ArgumentType(root: root, loc: loc)

proc newArgumentType*(root: Identifier, impls: seq[ArgumentType],
    loc: Location): ArgumentType =
  ArgumentType(root: root, loc: loc, impls: impls)

proc asl*(argType: ArgumentType): string =
  result = asl(argType.root)
  if argType.impls.len > 0:
    result.add("[")
    for i, impl in argType.impls:
      if i > 0: result.add(", ")
      result.add(asl(impl))
    result.add("]")

# Forward-declared via newSpec because argumentTypeSpec is self-referential:
# type params like Map[String, List[Int]] contain nested argument types.
# The ref is created first (parseFn: nil), then filled in below so the
# closure can capture the already-existing ref for recursive calls.
let argumentTypeSpec* = newSpec[ArgumentType]("argument_type")
argumentTypeSpec.parseFn = proc(parser: Parser): Result[ArgumentType, ParserError] =
  let rootIdent = ? parser.run(identifierSpec)
  let typeParams = contained("type_params", "[", separatedBy(argumentTypeSpec,
      commaWithSpacesSpec), "]")
  let maybeImpls = ? parser.run(optional(typeParams))
  if maybeImpls.isSome:
    ok(newArgumentType(rootIdent, maybeImpls.get, rootIdent.loc))
  else:
    ok(newArgumentType(rootIdent, rootIdent.loc))

# ============================================================
# ArgumentDef (name: ArgumentType)
# ============================================================

type ArgumentDef* = ref object
  name: Identifier
  argType: ArgumentType
  loc: Location

proc name*(argDef: ArgumentDef): Identifier = argDef.name
proc argType*(argDef: ArgumentDef): ArgumentType = argDef.argType
proc loc*(argDef: ArgumentDef): Location = argDef.loc

proc newArgumentDef*(name: Identifier, argType: ArgumentType,
    loc: Location): ArgumentDef =
  ArgumentDef(name: name, argType: argType, loc: loc)

proc asl*(argDef: ArgumentDef): string =
  fmt"{asl(argDef.name)}: {asl(argDef.argType)}"

let argumentDefSpec* = separated(identifierSpec, colonWithSpacesSpec, argumentTypeSpec).map(
  "argument_definition",
  proc(t: (Identifier, ArgumentType)): ArgumentDef = newArgumentDef(t[0], t[1], t[0].loc))

# ============================================================
# ArgumentDefList ((name: T, name: T, ...))
# ============================================================

type ArgumentDefList* = ref object
  argDefs: seq[ArgumentDef]
  argNameIndex: Table[Identifier, int]
  loc: Location

proc newArgumentDefList*(argDefs: seq[ArgumentDef],
    loc: Location): Result[ArgumentDefList, ParserError] =
  var argNameIndex: Table[Identifier, int]
  for index, argDef in argDefs:
    if argDef.name in argNameIndex:
      let prev = argDefs[argNameIndex[argDef.name]]
      let msg = fmt"duplicate argument encountered, see previous declaration at {prev.loc}"
      return err(newParserError(msg, argDef.loc))
    argNameIndex[argDef.name] = index
  ok(ArgumentDefList(argDefs: argDefs, argNameIndex: argNameIndex, loc: loc))

proc argDefs*(argDefList: ArgumentDefList): seq[ArgumentDef] =
  argDefList.argDefs

proc arity*(argDefList: ArgumentDefList): int =
  argDefList.argDefs.len

proc asl*(argDefList: ArgumentDefList): string =
  result = "("
  for i, argDef in argDefList.argDefs:
    if i > 0: result.add(", ")
    result.add(asl(argDef))
  result.add(")")

let argumentDefListSpec* = Spec[ArgumentDefList](
  name: "argument_definition_list",
  parseFn: proc(parser: Parser): Result[ArgumentDefList, ParserError] =
  let loc = parser.loc
  let argDefs = ? parser.run(contained("argument_definition_list", "(",
    separatedBy(argumentDefSpec, commaWithSpacesSpec), ")"))
  newArgumentDefList(argDefs, loc)
)
