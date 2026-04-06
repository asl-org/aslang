import strformat, strutils, sequtils, results, options

import combinator
import tokenizer

type EmptyLine = ref object
  loc: Location

proc newEmptyLine(loc: Location): EmptyLine =
  EmptyLine(loc: loc)

# proc value(line: EmptyLine): string = "\n"

type
  Comment = ref object
    content: string
    loc: Location

proc newComment(content: string, loc: Location): Comment =
  Comment(content: content, loc: loc)

# proc value(comment: Comment): string = fmt"#{comment.content}\n"

type
  Identifier = ref object
    name: string
    loc: Location

proc newIdentifier(name: string, loc: Location): Identifier =
  Identifier(name: name, loc: loc)

# proc value(identifier: Identifier): string = identifier.name

type Indentation = ref object
  indentation: uint32
  loc: Location

proc newIndentation(indentation: uint32, loc: Location): Indentation =
  Indentation(indentation: indentation, loc: loc)

# proc value(indentation: Indentation): string =
#   " ".repeat(indentation.indentation)

type ArgumentType = ref object
  root: string
  impls: seq[ArgumentType]
  loc: Location

proc newArgumentType(root: string, loc: Location): ArgumentType =
  ArgumentType(root: root, loc: loc)

proc newArgumentType(root: string, impls: seq[ArgumentType],
    loc: Location): ArgumentType =
  ArgumentType(root: root, loc: loc, impls: impls)

proc value(argType: ArgumentType): string =
  if argType.impls.len == 0:
    argType.root
  else:
    var implValues: seq[string]
    for impl in argType.impls: implValues.add(impl.value)
    let implValuesJoined = implValues.join(", ")
    fmt"{argType.root}[{implValuesJoined}]"

type ArgumentDefinition = ref object
  name: string
  argType: ArgumentType
  loc: Location

proc newArgumentDefinition(name: string, argType: ArgumentType,
    loc: Location): ArgumentDefinition =
  ArgumentDefinition(name: name, argType: argType, loc: loc)

# proc value(argDef: ArgumentDefinition): string =
#   fmt"{argDef.name}: {argDef.argType.value}"

type ArgumentDefinitionList = ref object
  argDefs: seq[ArgumentDefinition]
  loc: Location

proc newArgumentDefinitionList(argDefs: seq[ArgumentDefinition],
    loc: Location): ArgumentDefinitionList =
  ArgumentDefinitionList(argDefs: argDefs, loc: loc)

# proc value(argDefList: ArgumentDefinitionList): string =
#   let argDefs = argDefList.argDefs.mapIt(it.value)
#   let argDefsJoined = argDefs.join(", ")
#   fmt"({argDefsJoined})"

type FunctionDefinition = ref object
  name: string
  argDefList: ArgumentDefinitionList
  returns: ArgumentType
  loc: Location

proc newFunctionDefinition(name: string, argDefList: ArgumentDefinitionList,
    returns: ArgumentType, loc: Location): FunctionDefinition =
  FunctionDefinition(name: name, argDefList: argDefList, returns: returns, loc: loc)

# proc value(def: FunctionDefinition): string =
#   fmt"func {def.name}{def.argDefList.value}: {def.returns.value}"

type StringContent = ref object
  content: string
  loc: Location

proc newStringContent(content: string,
    loc: Location): StringContent =
  StringContent(content: content, loc: loc)

# proc value(strContent: StringContent): string =
#   strContent.content

type
  ArgumentList = ref object
    args: seq[Expression]
    loc: Location

  StringLiteral = ref object
    content: string
    loc: Location

  FunctionCall = ref object
    argType: ArgumentType
    name: string
    argList: ArgumentList

  ExpressionKind = enum
    ekFnCall, ekStrLit
  Expression = ref object
    case kind: ExpressionKind
    of ekFnCall: fncall: FunctionCall
    of ekStrLit: strLit: StringLiteral

proc newArgumentList(args: seq[Expression], loc: Location): ArgumentList =
  ArgumentList(args: args, loc: loc)

proc value(expression: Expression): string

proc value(argList: ArgumentList): string =
  let args = argList.args.mapIt(it.value).join(", ")
  fmt"({args})"

proc newStringLiteral(content: string, loc: Location): StringLiteral =
  StringLiteral(content: content, loc: loc)

proc value(strLit: StringLiteral): string =
  strLit.content

proc newFunctionCall(argType: ArgumentType, name: string,
    argList: ArgumentList): FunctionCall =
  FunctionCall(argType: argType, name: name, argList: argList)

# proc loc(fncall: FunctionCall): Location =
#   fncall.argType.loc

proc value(fncall: FunctionCall): string =
  fmt"{fncall.argType.value}.{fncall.name}{fncall.argList.value}"

proc newExpression(strLit: StringLiteral): Expression =
  Expression(kind: ekStrLit, strLit: strLit)

proc newExpression(fncall: FunctionCall): Expression =
  Expression(kind: ekFnCall, fncall: fncall)

# proc loc(expression: Expression): Location =
#   case expression.kind:
#   of ekFnCall: expression.fncall.loc
#   of ekStrLit: expression.strLit.loc

proc value(expression: Expression): string =
  case expression.kind:
  of ekFnCall: expression.fncall.value
  of ekStrLit: expression.strLit.value

type Assignment = ref object
  target: string
  expression: Expression
  loc: Location

proc newAssignment(target: string, expression: Expression,
    loc: Location): Assignment =
  Assignment(target: target, expression: expression, loc: loc)

# proc value(assignment: Assignment): string =
#   fmt"{assignment.target} = {assignment.expression.value}"

type
  StatementKind = enum
    skAssignment, skExpr
  Statement = ref object
    case kind: StatementKind
    of skAssignment: assignment: Assignment
    of skExpr: expression: Expression

proc newStatement(assignment: Assignment): Statement =
  Statement(kind: skAssignment, assignment: assignment)

proc newStatement(expression: Expression): Statement =
  Statement(kind: skExpr, expression: expression)

# proc loc(statement: Statement): Location =
#   case statement.kind:
#   of skAssignment: statement.assignment.loc
#   of skExpr: statement.expression.loc

# proc value(statement: Statement): string =
#   case statement.kind:
#   of skAssignment: statement.assignment.value
#   of skExpr: statement.expression.value

type StatementList = ref object
  statements: seq[Statement]

proc newStatementList(statements: seq[Statement]): StatementList =
  StatementList(statements: statements)

# proc loc(statementList: StatementList): Location =
#   statementList.statements[0].loc

# proc value(statementList: StatementList): string =
#   statementList.statements.mapIt(it.value).join("\n")

type Function = ref object
  def: FunctionDefinition
  statementList: StatementList

proc newFunction(def: FunctionDefinition,
    statementList: StatementList): Function =
  Function(def: def, statementList: statementList)

# proc loc(function: Function): Location =
#   function.def.loc

# proc value(function: Function): string =
#   # TODO: Consider the `parser.indentWidth`
#   let statements = function.statementList.statements.mapIt("  " &
#       it.value).join("\n")
#   [function.def.value, statements].join("\n")

type FunctionList = ref object
  functions: seq[Function]

proc newFunctionList(functions: seq[Function]): FunctionList =
  FunctionList(functions: functions)

# proc loc(funclist: FunctionList): Location =
#   if funclist.functions.len == 0: newLocation()
#   else: funclist.functions[0].loc

# proc value(funclist: FunctionList): string =
#   funclist.functions.mapIt(it.value).join("\n")

type Module = ref object
  name: string
  funcList: FunctionList
  loc: Location

proc newModule(name: string, funcList: FunctionList, loc: Location): Module =
  Module(name: name, funcList: funcList, loc: loc)

# proc value(module: Module): string =
#   # TODO: complete the function
#   fmt"module {module.name}:" & "\n" & module.funcList.functions.mapIt(
#       it.value).join("\n\n")

type File = ref object
  path: string
  modules: seq[Module]

proc newFile(path: string, modules: seq[Module]): File =
  File(path: path, modules: modules)

# proc loc(file: File): Location = newLocation()
# proc value(file: File): string =
#   file.modules.mapIt(it.value).join("\n\n")


type
  AslNodeKind = enum
    ankIdentifier, ankComment, ankEmptyLine, ankIndentation
    ankArgType, ankArgDef, ankArgDefList, ankFuncDef
    ankArgList
    ankStrContent, ankStrLit, ankFuncCall
    ankExpression, ankAssignment, ankStatement, ankStatementList
    ankFunction, ankFunctionList, ankModule, ankFile
  AslNode = ref object
    case kind: AslNodeKind
    of ankEmptyLine: line: EmptyLine
    of ankComment: comment: Comment
    of ankIdentifier: identifier: Identifier
    of ankIndentation: indentation: Indentation
    of ankArgType: argType: ArgumentType
    of ankArgDef: argDef: ArgumentDefinition
    of ankArgDefList: argDefList: ArgumentDefinitionList
    of ankFuncDef: funcDef: FunctionDefinition
    of ankStrContent: strContent: StringContent
    of ankStrLit: strLit: StringLiteral
    of ankArgList: argList: ArgumentList
    of ankFuncCall: fncall: FunctionCall
    of ankExpression: expression: Expression
    of ankAssignment: assignment: Assignment
    of ankStatement: statement: Statement
    of ankStatementList: statementList: StatementList
    of ankFunction: function: Function
    of ankFunctionList: funcList: FunctionList
    of ankModule: module: Module
    of ankFile: file: File

# proc newAslNode(line: EmptyLine): AslNode =
#   AslNode(kind: ankEmptyLine, line: line)

# proc newAslNode(comment: Comment): AslNode =
#   AslNode(kind: ankComment, comment: comment)

# proc newAslNode(identifier: Identifier): AslNode =
#   AslNode(kind: ankIdentifier, identifier: identifier)

# proc newAslNode(indentation: Indentation): AslNode =
#   AslNode(kind: ankIndentation, indentation: indentation)

# proc newAslNode(argType: ArgumentType): AslNode =
#   AslNode(kind: ankArgType, argType: argType)

# proc newAslNode(argDef: ArgumentDefinition): AslNode =
#   AslNode(kind: ankArgDef, argDef: argDef)

# proc newAslNode(argDefList: ArgumentDefinitionList): AslNode =
#   AslNode(kind: ankArgDefList, argDefList: argDefList)

proc newAslNode(funcDef: FunctionDefinition): AslNode =
  AslNode(kind: ankFuncDef, funcDef: funcDef)

# proc newAslNode(strContent: StringContent): AslNode =
#   AslNode(kind: ankStrContent, strContent: strContent)

# proc newAslNode(strLit: StringLiteral): AslNode =
#   AslNode(kind: ankStrLit, strLit: strLit)

# proc newAslNode(argList: ArgumentList): AslNode =
#   AslNode(kind: ankArgList, argList: argList)

# proc newAslNode(fncall: FunctionCall): AslNode =
#   AslNode(kind: ankFuncCall, fncall: fncall)

# proc newAslNode(expression: Expression): AslNode =
#   AslNode(kind: ankExpression, expression: expression)

# proc newAslNode(assignment: Assignment): AslNode =
#   AslNode(kind: ankAssignment, assignment: assignment)

# proc newAslNode(statement: Statement): AslNode =
#   AslNode(kind: ankStatement, statement: statement)

proc newAslNode(statementList: StatementList): AslNode =
  AslNode(kind: ankStatementList, statementList: statementList)

proc newAslNode(function: Function): AslNode =
  AslNode(kind: ankFunction, function: function)

proc newAslNode(funcList: FunctionList): AslNode =
  AslNode(kind: ankFunctionList, funcList: funcList)

proc newAslNode(module: Module): AslNode =
  AslNode(kind: ankModule, module: module)

proc newAslNode(file: File): AslNode =
  AslNode(kind: ankFile, file: file)

# proc loc(node: AslNode): Location =
#   case node.kind:
#   of ankEmptyLine: node.line.loc
#   of ankComment: node.comment.loc
#   of ankIdentifier: node.identifier.loc
#   of ankIndentation: node.indentation.loc
#   of ankArgType: node.argType.loc
#   of ankArgDef: node.argDef.loc
#   of ankArgDefList: node.argDefList.loc
#   of ankFuncDef: node.funcDef.loc
#   of ankStrContent: node.strContent.loc
#   of ankStrLit: node.strLit.loc
#   of ankArgList: node.argList.loc
#   of ankFuncCall: node.fncall.loc
#   of ankExpression: node.expression.loc
#   of ankAssignment: node.assignment.loc
#   of ankStatement: node.statement.loc
#   of ankStatementList: node.statementList.loc
#   of ankFunction: node.function.loc
#   of ankFunctionList: node.funcList.loc
#   of ankModule: node.module.loc
#   of ankFile: node.file.loc

# proc value(node: AslNode): string =
#   case node.kind:
#   of ankEmptyLine: node.line.value
#   of ankComment: node.comment.value
#   of ankIdentifier: node.identifier.value
#   of ankIndentation: node.indentation.value
#   of ankArgType: node.argType.value
#   of ankArgDef: node.argDef.value
#   of ankArgDefList: node.argDefList.value
#   of ankFuncDef: node.funcDef.value
#   of ankStrContent: node.strContent.value
#   of ankStrLit: node.strLit.value
#   of ankArgList: node.argList.value
#   of ankFuncCall: node.fncall.value
#   of ankExpression: node.expression.value
#   of ankAssignment: node.assignment.value
#   of ankStatement: node.statement.value
#   of ankStatementList: node.statementList.value
#   of ankFunction: node.function.value
#   of ankFunctionList: node.funcList.value
#   of ankModule: node.module.value
#   of ankFile: node.file.value

type InlineParserSpec = proc(parser: Parser): Result[AslNode, ParserError]
type BlockParserSpec = proc(parser: Parser, level: uint32): Result[AslNode, ParserError]

proc parse(parser: Parser, spec: InlineParserSpec): Result[AslNode, ParserError] =
  let checkpoint = parser.index
  let maybeSuccess = spec(parser)
  if maybeSuccess.isErr: parser.index = checkpoint
  return maybeSuccess

proc parse(parser: Parser, spec: BlockParserSpec, level: uint32): Result[
    AslNode, ParserError] =
  let checkpoint = parser.index
  let maybeSuccess = spec(parser, level)
  if maybeSuccess.isErr:
    parser.index = checkpoint
  return maybeSuccess


# ============================================================
# Combinator-based specs
# ============================================================

let identifierHeadCharSpec = oneOf("identifier_head", [
  punctuationSpec("_"),
  alphabetSpec,
])

let identifierTailCharSpec = oneOf("identifier_tail", [
  identifierHeadCharSpec,
  digitSpec,
])

let identifierSpec = Spec[Identifier](
  name: "identifier",
  parseFn: proc(parser: Parser): Result[Identifier, ParserError] =
  let head = ? parser.run(identifierHeadCharSpec)
  let tails = ? parser.run(any(identifierTailCharSpec))
  var content = head.value
  for tail in tails: content.add(tail.value)
  ok(newIdentifier(content, head.loc))
)

proc keywordSpec(keyword: string): Spec[Location] =
  Spec[Location](
    name: "'" & keyword & "'",
    parseFn: proc(parser: Parser): Result[Location, ParserError] =
    let ident = ? parser.run(identifierSpec)
    if ident.name != keyword:
      let msg = fmt"expected keyword '{keyword}' but found '{ident.name}'"
      return err(newParserError(msg, ident.loc))
    ok(ident.loc)
  )

let spacesSpec = atLeastOne(spaceSpec)

let emptyLineSpec = Spec[EmptyLine](
  name: "empty_line",
  parseFn: proc(parser: Parser): Result[EmptyLine, ParserError] =
  let loc = parser.loc
  discard ? parser.run(any(spaceSpec))
  discard ? parser.run(newlineSpec)
  ok(newEmptyLine(loc))
)

let commentSpec = Spec[Comment](
  name: "comment",
  parseFn: proc(parser: Parser): Result[Comment, ParserError] =
  let hashtag = ? parser.run(punctuationSpec("#"))
  let chars = ? parser.run(any(anyTokenExceptNewlineSpec("comment character")))
  var content: string
  for ch in chars: content.add(ch.value)
  discard ? parser.run(newlineSpec)
  ok(newComment(content, hashtag.loc))
)

let ignorableLineSpec = oneOf("ignorable_line", [
  emptyLineSpec.map("empty_line_loc", proc(v: EmptyLine): Location = v.loc),
  commentSpec.map("comment_loc", proc(v: Comment): Location = v.loc),
])

proc indentationSpec(level: uint32): Spec[Indentation] =
  Spec[Indentation](
    name: "indentation",
    parseFn: proc(parser: Parser): Result[Indentation, ParserError] =
    let loc = parser.loc
    let spaces = ? parser.run(any(spaceSpec))
    let count = spaces.len.uint32
    let expected = parser.indentWidth * level
    if count != expected:
      let msg = fmt"indentation error expected {expected} but found {count} space(s)"
      err(newParserError(msg, loc))
    else:
      ok(newIndentation(count, loc))
  )

proc escapedCharSpec(character: string): Spec[StringContent] =
  Spec[StringContent](
    name: "'\\" & character & "'",
    parseFn: proc(parser: Parser): Result[StringContent, ParserError] =
    let backslash = ? parser.run(punctuationSpec("\\"))
    discard ? parser.run(punctuationSpec(character))
    let output = "\\" & character
    ok(newStringContent(output, backslash.loc))
  )

proc escapedAlphaSpec(character: string): Spec[StringContent] =
  Spec[StringContent](
    name: "'\\" & character & "'",
    parseFn: proc(parser: Parser): Result[StringContent, ParserError] =
    let backslash = ? parser.run(punctuationSpec("\\"))
    let token = ? parser.run(alphabetSpec)
    if token.value != character:
      return err(newParserError(
        fmt"expected '\\{character}' but found '\\{token.value}'", token.loc))

    let output = "\\" & character
    ok(newStringContent(output, backslash.loc))
  )

let escapedBackslash = escapedCharSpec("\\") # '\\'
let escapedDoubleQuote = escapedCharSpec("\"") # '\"'
let escapedNewline = escapedAlphaSpec("n") # '\n'
let escapedTab = escapedAlphaSpec("t") # '\t'

let escapedStringCharSpec = oneOf("escaped_string_character", [
  escapedBackslash,
  escapedDoubleQuote,
  escapedNewline,
  escapedTab,
])

let unescapedStringCharSpec = Spec[StringContent](
  name: "unescaped_string_character",
  parseFn: proc(parser: Parser): Result[StringContent, ParserError] =
  let token = ? parser.run(anyTokenExceptNewlineSpec("unescaped string character"))
  if token.value == "\"" or token.value == "\\":
    return err(newParserError(
      fmt"expected a valid string character but found '{token.value}'", token.loc))
  ok(newStringContent(token.value, token.loc))
)

let stringContentSpec = oneOf("string_content", [
  escapedStringCharSpec,
  unescapedStringCharSpec,
])

let stringLiteralSpec = Spec[StringLiteral](
  name: "string_literal",
  parseFn: proc(parser: Parser): Result[StringLiteral, ParserError] =
  let openQuote = ? parser.run(punctuationSpec("\""))
  var content = "\""
  let chars = ? parser.run(any(stringContentSpec))
  for ch in chars: content.add(ch.content)
  discard ? parser.run(punctuationSpec("\""))
  content.add("\"")
  ok(newStringLiteral(content, openQuote.loc))
)

proc separatorSpec(sep: string): Spec[Token] =
  Spec[Token](
    name: "'" & sep & "'",
    parseFn: proc(parser: Parser): Result[Token, ParserError] =
    discard ? parser.run(any(spaceSpec))
    let token = ? parser.run(punctuationSpec(sep))
    discard ? parser.run(any(spaceSpec))
    ok(token)
  )

let commaWithSpacesSpec = separatorSpec(",")
let colonWithSpacesSpec = separatorSpec(":")

# Forward-declared via newSpec because argumentTypeSpec is self-referential:
# type params like Map[String, List[Int]] contain nested argument types.
# The ref is created first (parseFn: nil), then filled in below so the
# closure can capture the already-existing ref for recursive calls.
let argumentTypeSpec = newSpec[ArgumentType]("argument_type")
argumentTypeSpec.parseFn = proc(parser: Parser): Result[ArgumentType, ParserError] =
  let rootIdent = ? parser.run(identifierSpec)
  let maybeImpls = ? parser.run(optional(
    contained("type_params", "[",
      separatedBy(argumentTypeSpec, commaWithSpacesSpec), "]")))
  if maybeImpls.isSome:
    ok(newArgumentType(rootIdent.name, maybeImpls.get, rootIdent.loc))
  else:
    ok(newArgumentType(rootIdent.name, rootIdent.loc))

let argumentDefinitionSpec = Spec[ArgumentDefinition](
  name: "argument_definition",
  parseFn: proc(parser: Parser): Result[ArgumentDefinition, ParserError] =
  let argName = ? parser.run(identifierSpec)
  discard ? parser.run(colonWithSpacesSpec)
  let argType = ? parser.run(argumentTypeSpec)
  ok(newArgumentDefinition(argName.name, argType, argName.loc))
)

let argumentDefinitionListSpec = Spec[ArgumentDefinitionList](
  name: "argument_definition_list",
  parseFn: proc(parser: Parser): Result[ArgumentDefinitionList, ParserError] =
  let openParen = ? parser.run(punctuationSpec("("))
  discard parser.run(any(spaceSpec))
  let argDefs = ? parser.run(separatedBy(argumentDefinitionSpec,
      commaWithSpacesSpec))
  discard parser.run(any(spaceSpec))
  discard ? parser.run(punctuationSpec(")"))
  ok(newArgumentDefinitionList(argDefs, openParen.loc))
)

let functionDefinitionSpec = Spec[FunctionDefinition](
  name: "function_definition",
  parseFn: proc(parser: Parser): Result[FunctionDefinition, ParserError] =
  let funcLoc = ? parser.run(keywordSpec("func"))
  discard ? parser.run(spacesSpec)
  let funcName = ? parser.run(identifierSpec)
  discard parser.run(spacesSpec)
  let argDefList = ? parser.run(argumentDefinitionListSpec)
  discard ? parser.run(colonWithSpacesSpec)
  let returnType = ? parser.run(argumentTypeSpec)
  ok(newFunctionDefinition(funcName.name, argDefList, returnType, funcLoc))
)

# Forward-declared because expressions appear inside argument lists
# of function calls, creating a mutual recursion:
# expression -> functionCall -> argumentList -> expression
let expressionSpec = newSpec[Expression]("expression")

let argumentListSpec = Spec[ArgumentList](
  name: "argument_list",
  parseFn: proc(parser: Parser): Result[ArgumentList, ParserError] =
  let loc = parser.loc
  let args = ? parser.run(contained("argument_list", "(",
    separatedBy(expressionSpec, commaWithSpacesSpec), ")"))
  ok(newArgumentList(args, loc))
)

let functionCallSpec = Spec[FunctionCall](
  name: "function_call",
  parseFn: proc(parser: Parser): Result[FunctionCall, ParserError] =
  let argType = ? parser.run(argumentTypeSpec)
  discard ? parser.run(punctuationSpec("."))
  let funcNameIdent = ? parser.run(identifierSpec)
  discard parser.run(spacesSpec)
  let argList = ? parser.run(argumentListSpec)
  ok(newFunctionCall(argType, funcNameIdent.name, argList))
)

expressionSpec.parseFn = oneOf("expression", [
  stringLiteralSpec.map("string_expression",
    proc(v: StringLiteral): Expression = newExpression(v)),
  functionCallSpec.map("fncall_expression",
    proc(v: FunctionCall): Expression = newExpression(v)),
]).parseFn

let equalsSeparatorSpec = separatorSpec("=")

let assignmentSpec = Spec[Assignment](
  name: "assignment",
  parseFn: proc(parser: Parser): Result[Assignment, ParserError] =
  let targetIdent = ? parser.run(identifierSpec)
  discard ? parser.run(equalsSeparatorSpec)
  let expression = ? parser.run(expressionSpec)
  ok(newAssignment(targetIdent.name, expression, targetIdent.loc))
)

let statementSpec = oneOf("statement", [
  assignmentSpec.map("assignment_statement",
    proc(v: Assignment): Statement = newStatement(v)),
  expressionSpec.map("expression_statement",
    proc(v: Expression): Statement = newStatement(v)),
])

proc statementLineSpec(level: uint32): Spec[Statement] =
  Spec[Statement](
    name: "statement_line",
    parseFn: proc(parser: Parser): Result[Statement, ParserError] =
    discard ? parser.run(indentationSpec(level))
    let statement = ? parser.run(statementSpec)
    discard ? parser.run(ignorableLineSpec)
    ok(statement)
  )

proc statementListSpec(level: uint32): Spec[StatementList] =
  atLeastOne(statementLineSpec(level)).map("statement_list",
    proc(stmts: seq[Statement]): StatementList = newStatementList(stmts))

proc functionSpec(level: uint32): Spec[Function] =
  Spec[Function](
    name: "function",
    parseFn: proc(parser: Parser): Result[Function, ParserError] =
    discard ? parser.run(indentationSpec(level))
    let funcDef = ? parser.run(functionDefinitionSpec)
    discard ? parser.run(ignorableLineSpec)
    let stmtList = ? parser.run(statementListSpec(level + 1))
    ok(newFunction(funcDef, stmtList))
  )

proc functionListSpec(level: uint32): Spec[FunctionList] =
  # Each function block skips leading ignorable lines then parses a function.
  # any() backtracks the ignorable line consumption if no function follows.
  let funcBlockSpec = Spec[Function](
    name: "function_block",
    parseFn: proc(parser: Parser): Result[Function, ParserError] =
    discard parser.run(any(ignorableLineSpec))
    let f = ? parser.run(functionSpec(level))
    ok(f)
  )
  any(funcBlockSpec).map("function_list",
    proc(fns: seq[Function]): FunctionList = newFunctionList(fns))

proc moduleSpec(level: uint32): Spec[Module] =
  Spec[Module](
    name: "module",
    parseFn: proc(parser: Parser): Result[Module, ParserError] =
    discard ? parser.run(indentationSpec(level))
    let moduleLoc = ? parser.run(keywordSpec("module"))
    discard ? parser.run(spacesSpec)
    let moduleNameIdent = ? parser.run(identifierSpec)
    discard parser.run(spacesSpec)
    discard ? parser.run(punctuationSpec(":"))
    discard ? parser.run(ignorableLineSpec)
    discard parser.run(any(ignorableLineSpec))
    let funcList = ? parser.run(functionListSpec(level + 1))
    ok(newModule(moduleNameIdent.name, funcList, moduleLoc))
  )

let fileSpec = Spec[File](
  name: "file",
  parseFn: proc(parser: Parser): Result[File, ParserError] =
  var modules: seq[Module]
  while not parser.done():
    discard parser.run(any(ignorableLineSpec))
    if parser.done(): break
    let module = ? parser.run(moduleSpec(0))
    modules.add(module)
  ok(newFile(parser.filepath, modules))
)

proc parse*(filepath: string, indentWidth: uint32, tokens: seq[Token]): Result[
    File, string] =
  let parser = newParser(filepath, indentWidth, tokens)
  let maybeFile = parser.run(fileSpec)
  if maybeFile.isErr:
    err(fmt"{filepath}:{maybeFile.error}")
  else:
    ok(maybeFile.get)
