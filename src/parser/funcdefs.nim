import strformat, results

import tokenizer
import combinators
import helpers
import identifiers
import argtypes

# ============================================================
# FunctionDefinition (signature only, no body)
# ============================================================

type FunctionDefinition* = ref object
  public: bool
  name: Identifier
  argDefList: ArgumentDefinitionList
  returns: ArgumentType
  loc: Location

proc public*(fd: FunctionDefinition): bool = fd.public
proc name*(fd: FunctionDefinition): Identifier = fd.name
proc args*(fd: FunctionDefinition): seq[
    ArgumentDefinition] = fd.argDefList.argDefs
proc returns*(fd: FunctionDefinition): ArgumentType = fd.returns
proc loc*(fd: FunctionDefinition): Location = fd.loc
proc arity*(fd: FunctionDefinition): int = fd.argDefList.arity

proc newFunctionDefinition*(public: bool, name: Identifier,
    argDefList: ArgumentDefinitionList, returns: ArgumentType,
    loc: Location): FunctionDefinition =
  FunctionDefinition(public: public, name: name, argDefList: argDefList,
      returns: returns, loc: loc)

proc asl*(funcDef: FunctionDefinition): string =
  let prefix = if funcDef.public: "public func" else: "func"
  fmt"{prefix} {asl(funcDef.name)}{asl(funcDef.argDefList)}: {asl(funcDef.returns)}"

let functionDefinitionSpec* = Spec[FunctionDefinition](
  name: "function_definition",
  parseFn: proc(parser: Parser): Result[FunctionDefinition, ParserError] =
  let maybePublic = parser.run(keywordSpec("public"))
  if maybePublic.isOk: discard ? parser.run(atLeastOne(spaceSpec))
  let public = maybePublic.isOk

  let funcLoc = ? parser.run(keywordSpec("func"))
  discard ? parser.run(atLeastOne(spaceSpec))
  let funcName = ? parser.run(identifierSpec)
  discard parser.run(any(spaceSpec))
  let argDefList = ? parser.run(argumentDefinitionListSpec)
  discard ? parser.run(colonWithSpacesSpec)
  let returnType = ? parser.run(argumentTypeSpec)
  ok(newFunctionDefinition(public, funcName, argDefList, returnType, funcLoc))
)

# Function definition line: indentation + function signature + newline
# Used by genericSpec via functionDefinitionListSpec.
let functionDefinitionLineSpec* = Spec[FunctionDefinition](
  name: "function_definition_line",
  parseFn: proc(parser: Parser): Result[FunctionDefinition, ParserError] =
  discard ? parser.run(indentationSpec)
  let funcDef = ? parser.run(functionDefinitionSpec)
  discard ? parser.run(ignorableLineSpec)
  ok(funcDef)
)

let functionDefinitionListSpec* = atLeastOne(functionDefinitionLineSpec)
