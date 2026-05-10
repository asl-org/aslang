import strformat, options, tables, results

import tokenizer
import combinators
import helpers
import identifiers

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
# ArgumentDefinition (name: ArgumentType)
# ============================================================

type ArgumentDefinition* = ref object
  name: Identifier
  argType: ArgumentType
  loc: Location

proc name*(argDef: ArgumentDefinition): Identifier = argDef.name
proc argType*(argDef: ArgumentDefinition): ArgumentType = argDef.argType
proc loc*(argDef: ArgumentDefinition): Location = argDef.loc

proc newArgumentDefinition*(name: Identifier, argType: ArgumentType,
    loc: Location): ArgumentDefinition =
  ArgumentDefinition(name: name, argType: argType, loc: loc)

proc asl*(argDef: ArgumentDefinition): string =
  fmt"{asl(argDef.name)}: {asl(argDef.argType)}"

let argumentDefinitionSpec* = Spec[ArgumentDefinition](
  name: "argument_definition",
  parseFn: proc(parser: Parser): Result[ArgumentDefinition, ParserError] =
  let argName = ? parser.run(identifierSpec)
  discard ? parser.run(colonWithSpacesSpec)
  let argType = ? parser.run(argumentTypeSpec)
  ok(newArgumentDefinition(argName, argType, argName.loc))
)

# ============================================================
# ArgumentDefinitionList ((name: T, name: T, ...))
# ============================================================

type ArgumentDefinitionList* = ref object
  argDefs: seq[ArgumentDefinition]
  argNameIndex: Table[Identifier, int]
  loc: Location

proc newArgumentDefinitionList*(argDefs: seq[ArgumentDefinition],
    loc: Location): Result[ArgumentDefinitionList, ParserError] =
  var argNameIndex: Table[Identifier, int]
  for index, argDef in argDefs:
    if argDef.name in argNameIndex:
      let prev = argDefs[argNameIndex[argDef.name]]
      let msg = fmt"duplicate argument encountered, see previous declaration at {prev.loc}"
      return err(newParserError(msg, argDef.loc))
    argNameIndex[argDef.name] = index
  ok(ArgumentDefinitionList(argDefs: argDefs, argNameIndex: argNameIndex, loc: loc))

proc argDefs*(argDefList: ArgumentDefinitionList): seq[ArgumentDefinition] =
  argDefList.argDefs

proc arity*(argDefList: ArgumentDefinitionList): int =
  argDefList.argDefs.len

proc asl*(argDefList: ArgumentDefinitionList): string =
  result = "("
  for i, argDef in argDefList.argDefs:
    if i > 0: result.add(", ")
    result.add(asl(argDef))
  result.add(")")

let argumentDefinitionListSpec* = Spec[ArgumentDefinitionList](
  name: "argument_definition_list",
  parseFn: proc(parser: Parser): Result[ArgumentDefinitionList, ParserError] =
  let loc = parser.loc
  let argDefs = ? parser.run(contained("argument_definition_list", "(",
    separatedBy(argumentDefinitionSpec, commaWithSpacesSpec), ")"))
  newArgumentDefinitionList(argDefs, loc)
)
