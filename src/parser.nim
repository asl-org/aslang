import results, strformat, strutils, sequtils

import tokenizer

type
  ParserError = ref object
    loc: Location
    msg: string

proc newParserError(msg: string, loc: Location): ParserError =
  ParserError(msg: msg, loc: loc)

proc `<`(err1: ParserError, err2: ParserError): bool =
  err1.loc < err2.loc

proc `$`(error: ParserError): string =
  fmt"{error.loc} {error.msg}"

type Parser = ref object
  filepath: string
  indentWidth: uint32
  tokens: seq[Token]
  index: int = 0

proc newParser(filepath: string, indentWidth: uint32, tokens: seq[
    Token]): Parser =
  Parser(filepath: filepath, indentWidth: indentWidth, tokens: tokens)

proc done(parser: Parser): bool =
  parser.index == parser.tokens.len

proc loc(parser: Parser): Location =
  if parser.done(): parser.tokens[^1].loc
  else: parser.tokens[parser.index].loc

proc peek(parser: Parser, tokenRepr: string): Result[Token, ParserError] =
  if parser.done():
    let msg = fmt"expected {tokenRepr} but reached end of token stream"
    err(newParserError(msg, parser.loc))
  else:
    ok(parser.tokens[parser.index])

proc consume(parser: Parser, tokenRepr: string): Result[Token, ParserError] =
  let token = ? parser.peek(tokenRepr)
  parser.index += 1
  ok(token)

proc consumeExceptNewline(parser: Parser, tokenRepr: string): Result[Token, ParserError] =
  let token = ? parser.peek(tokenRepr)
  if token.kind == tkNewline:
    let msg = fmt"{token.repr} is not supported as {tokenRepr}"
    err(newParserError(msg, parser.loc))
  else:
    parser.index += 1
    ok(token)

proc consume(parser: Parser, kind: TokenKind,
    tokenRepr: string): Result[Token, ParserError] =
  let token = ? parser.peek(tokenRepr)
  if token.kind != kind:
    let msg = fmt"expected {tokenRepr} but found {token.repr}"
    err(newParserError(msg, parser.loc))
  else:
    parser.index += 1
    ok(token)

proc consumePunctuation(parser: Parser, value: string): Result[
    Token, ParserError] =
  let token = ? parser.peek(fmt"punctuation '{value}'")
  if token.kind != tkPunctuation or token.value != value:
    let msg = fmt"expected punctuation '{value}' but found {token.repr}"
    err(newParserError(msg, token.loc))
  else:
    parser.index += 1
    ok(token)

proc consumeSpace(parser: Parser): Result[
    Token, ParserError] =
  parser.consume(tkSpace, "space ' '")

proc consumeNewline(parser: Parser): Result[
    Token, ParserError] =
  parser.consume(tkNewline, "newline '\\n'")

proc consumeDigit(parser: Parser): Result[Token, ParserError] =
  parser.consume(tkDigit, "digit [0-9]")

proc consumeAlphabet(parser: Parser): Result[Token, ParserError] =
  parser.consume(tkAlphabet, "alphabet [a-zA-Z]")

proc consumeUtf8(parser: Parser): Result[Token, ParserError] =
  parser.consume(tkUtf8, "utf8 character")

type EmptyLine = ref object
  loc: Location

proc newEmptyLine(loc: Location): EmptyLine =
  EmptyLine(loc: loc)

proc value(line: EmptyLine): string = "\n"

type
  Comment = ref object
    content: string
    loc: Location

proc newComment(content: string, loc: Location): Comment =
  Comment(content: content, loc: loc)

proc value(comment: Comment): string = fmt"#{comment.content}\n"

type
  Identifier = ref object
    name: string
    loc: Location

proc newIdentifier(name: string, loc: Location): Identifier =
  Identifier(name: name, loc: loc)

proc value(identifier: Identifier): string = identifier.name

type Indentation = ref object
  indentation: uint32
  loc: Location

proc newIndentation(indentation: uint32, loc: Location): Indentation =
  Indentation(indentation: indentation, loc: loc)

proc value(indentation: Indentation): string =
  " ".repeat(indentation.indentation)

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

proc value(argDef: ArgumentDefinition): string =
  fmt"{argDef.name}: {argDef.argType.value}"

type ArgumentDefinitionList = ref object
  argDefs: seq[ArgumentDefinition]
  loc: Location

proc newArgumentDefinitionList(argDefs: seq[ArgumentDefinition],
    loc: Location): ArgumentDefinitionList =
  ArgumentDefinitionList(argDefs: argDefs, loc: loc)

proc value(argDefList: ArgumentDefinitionList): string =
  let argDefs = argDefList.argDefs.mapIt(it.value)
  let argDefsJoined = argDefs.join(", ")
  fmt"({argDefsJoined})"

type FunctionDefinition = ref object
  name: string
  argDefList: ArgumentDefinitionList
  returns: ArgumentType
  loc: Location

proc newFunctionDefinition(name: string, argDefList: ArgumentDefinitionList,
    returns: ArgumentType, loc: Location): FunctionDefinition =
  FunctionDefinition(name: name, argDefList: argDefList, returns: returns, loc: loc)

proc value(def: FunctionDefinition): string =
  fmt"func {def.name}{def.argDefList.value}: {def.returns.value}"

type StringContent = ref object
  content: string
  loc: Location

proc newStringContent(content: string,
    loc: Location): StringContent =
  StringContent(content: content, loc: loc)

proc value(strContent: StringContent): string =
  strContent.content

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

proc loc(fncall: FunctionCall): Location =
  fncall.argType.loc

proc value(fncall: FunctionCall): string =
  fmt"{fncall.argType.value}.{fncall.name}{fncall.argList.value}"

proc newExpression(strLit: StringLiteral): Expression =
  Expression(kind: ekStrLit, strLit: strLit)

proc newExpression(fncall: FunctionCall): Expression =
  Expression(kind: ekFnCall, fncall: fncall)

proc loc(expression: Expression): Location =
  case expression.kind:
  of ekFnCall: expression.fncall.loc
  of ekStrLit: expression.strLit.loc

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

proc value(assignment: Assignment): string =
  fmt"{assignment.value} = {assignment.expression.value}"

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

proc loc(statement: Statement): Location =
  case statement.kind:
  of skAssignment: statement.assignment.loc
  of skExpr: statement.expression.loc

proc value(statement: Statement): string =
  case statement.kind:
  of skAssignment: statement.assignment.value
  of skExpr: statement.expression.value

type StatementList = ref object of RootObj
  statements: seq[Statement]

proc newStatementList(statements: seq[Statement]): StatementList =
  StatementList(statements: statements)

proc loc(statementList: StatementList): Location =
  statementList.statements[0].loc

proc value(statementList: StatementList): string =
  statementList.statements.mapIt(it.value).join("\n")

type Function = ref object
  def: FunctionDefinition
  statementList: StatementList

proc newFunction(def: FunctionDefinition,
    statementList: StatementList): Function =
  Function(def: def, statementList: statementList)

proc loc(function: Function): Location =
  function.def.loc

proc value(function: Function): string =
  # TODO: Consider the `parser.indentWidth`
  let statements = function.statementList.statements.mapIt("  " &
      it.value).join("\n")
  [function.def.value, statements].join("\n")

type FunctionList = ref object
  functions: seq[Function]

proc newFunctionList(functions: seq[Function]): FunctionList =
  FunctionList(functions: functions)

proc loc(funclist: FunctionList): Location =
  funclist.functions[0].loc

proc value(funclist: FunctionList): string =
  funclist.functions.mapIt(it.value).join("\n")

type Module = ref object
  name: string
  funcList: FunctionList
  loc: Location

proc newModule(name: string, funcList: FunctionList, loc: Location): Module =
  Module(name: name, funcList: funcList, loc: loc)

proc value(module: Module): string =
  # TODO: complete the function
  fmt"module {module.name}:" & "\n" & module.funcList.functions.mapIt(
      it.value).join("\n\n")

type File = ref object
  path: string
  modules: seq[Module]

proc newFile(path: string, modules: seq[Module]): File =
  File(path: path, modules: modules)

proc loc(file: File): Location = newLocation()
proc value(file: File): string =
  file.modules.mapIt(it.value).join("\n\n")


type
  AslNodeKind = enum
    ankIdentifier, ankComment, ankEmptyLine, ankIndetation
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
    of ankIndetation: indentation: Indentation
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

proc newAslNode(line: EmptyLine): AslNode =
  AslNode(kind: ankEmptyLine, line: line)

proc newAslNode(comment: Comment): AslNode =
  AslNode(kind: ankComment, comment: comment)

proc newAslNode(identifier: Identifier): AslNode =
  AslNode(kind: ankIdentifier, identifier: identifier)

proc newAslNode(indentation: Indentation): AslNode =
  AslNode(kind: ankIndetation, indentation: indentation)

proc newAslNode(argType: ArgumentType): AslNode =
  AslNode(kind: ankArgType, argType: argType)

proc newAslNode(argDef: ArgumentDefinition): AslNode =
  AslNode(kind: ankArgDef, argDef: argDef)

proc newAslNode(argDefList: ArgumentDefinitionList): AslNode =
  AslNode(kind: ankArgDefList, argDefList: argDefList)

proc newAslNode(funcDef: FunctionDefinition): AslNode =
  AslNode(kind: ankFuncDef, funcDef: funcDef)

proc newAslNode(strContent: StringContent): AslNode =
  AslNode(kind: ankStrContent, strContent: strContent)

proc newAslNode(strLit: StringLiteral): AslNode =
  AslNode(kind: ankStrLit, strLit: strLit)

proc newAslNode(argList: ArgumentList): AslNode =
  AslNode(kind: ankArgList, argList: argList)

proc newAslNode(fncall: FunctionCall): AslNode =
  AslNode(kind: ankFuncCall, fncall: fncall)

proc newAslNode(expression: Expression): AslNode =
  AslNode(kind: ankExpression, expression: expression)

proc newAslNode(assignment: Assignment): AslNode =
  AslNode(kind: ankAssignment, assignment: assignment)

proc newAslNode(statement: Statement): AslNode =
  AslNode(kind: ankStatement, statement: statement)

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

proc loc(node: AslNode): Location =
  case node.kind:
  of ankEmptyLine: node.line.loc
  of ankComment: node.comment.loc
  of ankIdentifier: node.identifier.loc
  of ankIndetation: node.indentation.loc
  of ankArgType: node.argType.loc
  of ankArgDef: node.argDef.loc
  of ankArgDefList: node.argDefList.loc
  of ankFuncDef: node.funcDef.loc
  of ankStrContent: node.strLit.loc
  of ankStrLit: node.strLit.loc
  of ankArgList: node.argList.loc
  of ankFuncCall: node.fncall.loc
  of ankExpression: node.expression.loc
  of ankAssignment: node.assignment.loc
  of ankStatement: node.statement.loc
  of ankStatementList: node.statementList.loc
  of ankFunction: node.function.loc
  of ankFunctionList: node.funcList.loc
  of ankModule: node.module.loc
  of ankFile: node.file.loc

proc value(node: AslNode): string =
  case node.kind:
  of ankEmptyLine: node.line.value
  of ankComment: node.comment.value
  of ankIdentifier: node.identifier.value
  of ankIndetation: node.indentation.value
  of ankArgType: node.argType.value
  of ankArgDef: node.argDef.value
  of ankArgDefList: node.argDefList.value
  of ankFuncDef: node.funcDef.value
  of ankStrContent: node.strContent.value
  of ankStrLit: node.strLit.value
  of ankArgList: node.argList.value
  of ankFuncCall: node.fncall.value
  of ankExpression: node.expression.value
  of ankAssignment: node.expression.value
  of ankStatement: node.statement.value
  of ankStatementList: node.statementList.value
  of ankFunction: node.function.value
  of ankFunctionList: node.funcList.value
  of ankModule: node.module.value
  of ankFile: node.file.value

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


proc parseSpaces(parser: Parser): Result[AslNode, ParserError] =
  let loc = parser.loc

  var spaces: uint32 = 0
  var maybeSpace = parser.consumeSpace()
  while maybeSpace.isOk:
    spaces += 1
    maybeSpace = parser.consumeSpace()

  if spaces == 0:
    err(newParserError(fmt"expected spaces", loc))
  else:
    ok(newAslNode(newIndentation(spaces, loc)))

proc parseEmptyLine(parser: Parser): Result[AslNode, ParserError] =
  discard parser.parse(parseSpaces)
  let newline = ? parser.consumeNewline()
  ok(newAslNode(newEmptyLine(newline.loc)))

proc parseComment(parser: Parser): Result[AslNode, ParserError] =
  let hashtag = ? parser.consumePunctuation("#")

  var content: string
  var maybeToken = parser.consume("any character except new line '\n'")
  # NOTE: consume all tokens until we hit the new line character
  while maybeToken.isOk:
    content.add(maybeToken.get.value)
    maybeToken = parser.consume("any character except new line '\n'")

  discard ? consumeNewline(parser)

  ok(newAslNode(newComment(content, hashtag.loc)))

proc parseIgnorableLine(parser: Parser): Result[AslNode, ParserError] =
  var errors: seq[ParserError]

  let maybeEmptyLine = parser.parse(parseEmptyLine)
  if maybeEmptyLine.isOk: return maybeEmptyLine
  else: errors.add(maybeEmptyLine.error)

  let maybeComment = parser.parse(parseComment)
  if maybeComment.isOk: return maybeComment
  else: errors.add(maybeComment.error)

  err(max(errors))

proc parseIndentation(parser: Parser, level: uint32): Result[AslNode, ParserError] =
  var spaces: uint32 = 0
  let loc = parser.loc
  var maybeSpace = consumeSpace(parser)
  while maybeSpace.isOk:
    spaces += 1
    maybeSpace = consumeSpace(parser)

  let expectedSpaces = parser.indentWidth * level

  if spaces != expectedSpaces:
    let msg = fmt"indentation error expected {expectedSpaces} but found {spaces} space(s)"
    err(newParserError(msg, loc))
  else:
    ok(newAslNode(newIndentation(spaces, loc)))

proc parseIdentifierHead(parser: Parser): Result[AslNode, ParserError] =
  var errors: seq[ParserError]

  let maybeUnderscore = parser.consumePunctuation("_")
  if maybeUnderscore.isOk:
    let underscore = maybeUnderscore.get
    return ok(newAslNode(newIdentifier(underscore.value, underscore.loc)))
  else:
    errors.add(maybeUnderscore.error)

  let maybeAlphabet = parser.consumeAlphabet()
  if maybeAlphabet.isOk:
    let alphabet = maybeAlphabet.get
    return ok(newAslNode(newIdentifier(alphabet.value, alphabet.loc)))
  else:
    errors.add(maybeAlphabet.error)

  err(max(errors))

proc parseIdentifierTail(parser: Parser): Result[AslNode, ParserError] =
  var errors: seq[ParserError]

  let maybeIdentifierHead = parser.parse(parseIdentifierHead)
  if maybeIdentifierHead.isOk:
    return maybeIdentifierHead
  else:
    errors.add(maybeIdentifierHead.error)

  let maybeDigit = parser.consumeDigit()
  if maybeDigit.isOk:
    let digit = maybeDigit.get
    return ok(newAslNode(newIdentifier(digit.value, digit.loc)))
  else:
    errors.add(maybeDigit.error)

  err(max(errors))

proc parseIdentifier(parser: Parser): Result[AslNode, ParserError] =
  var identifierContent: string

  let identifierHead = ? parser.parse(parseIdentifierHead)

  assert identifierHead.kind == ankIdentifier, "expected identifier in parseIdentifier"
  identifierContent.add(identifierHead.identifier.name)

  var identifierTail: AslNode
  var maybeIdentifierTail = parser.parse(parseIdentifierTail)
  while maybeIdentifierTail.isOk:
    identifierTail = maybeIdentifierTail.get

    assert identifierTail.kind == ankIdentifier, "expected identifier in parseIdentifier"
    identifierContent.add(identifierTail.identifier.name)
    maybeIdentifierTail = parser.parse(parseIdentifierTail)

  ok(newAslNode(newIdentifier(identifierContent,
      identifierHead.identifier.loc)))

proc parseArgumentType(parser: Parser): Result[AslNode, ParserError] =
  let rootArgType = ? parser.parse(parseIdentifier)

  let maybeOpenSquare = parser.consumePunctuation("[")
  if maybeOpenSquare.isErr:
    return ok(newAslNode(newArgumentType(rootArgType.value, rootArgType.loc)))

  var impls: seq[ArgumentType]
  discard parser.parse(parseSpaces)
  var maybeArgType = parser.parse(parseArgumentType)
  while maybeArgType.isOk:
    let implType = maybeArgType.get

    assert implType.kind == ankArgType, "expected argument type"
    impls.add(implType.argType)

    discard parser.parse(parseSpaces)

    let maybeComma = parser.consumePunctuation(",")
    if maybeComma.isErr: break

    discard parser.parse(parseSpaces)
    maybeArgType = parser.parse(parseArgumentType)

  discard ? parser.consumePunctuation("]")

  ok(newAslNode(newArgumentType(rootArgType.value, impls, rootArgType.loc)))

proc parseArgumentDefinition(parser: Parser): Result[AslNode, ParserError] =
  let argName = ? parser.parse(parseIdentifier)
  discard parser.parse(parseSpaces)

  discard ? parser.consumePunctuation(":")
  discard parser.parse(parseSpaces)

  let argTypeNode = ? parser.parse(parseArgumentType)
  assert argTypeNode.kind == ankArgType, "expected argument type"
  let argType = argTypeNode.argType

  ok(newAslNode(newArgumentDefinition(argName.value, argType, argName.loc)))

proc parseArgumentDefinitionList(parser: Parser): Result[AslNode, ParserError] =
  let openParen = ? parser.consumePunctuation("(")

  discard parser.parse(parseSpaces)

  var argDefList: seq[ArgumentDefinition]
  var maybeArgDef = parser.parse(parseArgumentDefinition)
  while maybeArgDef.isOk:
    let argDefNode = maybeArgDef.get

    assert argDefNode.kind == ankArgDef, "expected argument definition"
    argDefList.add(argDefNode.argDef)

    discard parser.parse(parseSpaces)

    var maybeComma = parser.consumePunctuation(",")
    if maybeComma.isErr: break

    discard parser.parse(parseSpaces)

    maybeArgDef = parser.parse(parseArgumentDefinition)

  discard ? parser.consumePunctuation(")")
  ok(newAslNode(newArgumentDefinitionList(argDefList, openParen.loc)))

proc parseFunctionDefinition(parser: Parser): Result[AslNode, ParserError] =
  let funcKeyword = ? parser.parse(parseIdentifier)
  assert funcKeyword.kind == ankIdentifier, "expected identifier"
  if funcKeyword.value != "func":
    let msg = fmt"expected macro 'func' but found '{funcKeyword.value}'"
    return err(newParserError(msg, funcKeyword.loc))

  discard ? parser.parse(parseSpaces)

  let funcName = ? parser.parse(parseIdentifier)

  discard parser.parse(parseSpaces)

  let argDefListNode = ? parser.parse(parseArgumentDefinitionList)
  assert argDefListNode.kind == ankArgDefList, "expected argument definition list"
  let argDefList = argDefListNode.argDefList

  discard parser.parse(parseSpaces)

  discard ? parser.consumePunctuation(":")
  discard parser.parse(parseSpaces)

  let returnTypeNode = ? parser.parse(parseArgumentType)
  assert returnTypeNode.kind == ankArgType, "expected argument type"
  let returnType = returnTypeNode.argType

  ok(newAslNode(newFunctionDefinition(funcName.value, argDefList, returnType,
      funcKeyword.loc)))

proc parseEscapedStringCharacter(parser: Parser): Result[AslNode, ParserError] =
  var errors: seq[ParserError]
  let backslash = ? parser.consumePunctuation("\\")

  let maybeBackSlash = parser.consumePunctuation("\\")
  if maybeBackSlash.isOk:
    return ok(newAslNode(newStringContent("\\\\", backslash.loc)))
  else:
    errors.add(maybeBackSlash.error)

  let maybeDoubleQuote = parser.consumePunctuation("\"")
  if maybeDoubleQuote.isOk:
    return ok(newAslNode(newStringContent("\\\"", backslash.loc)))
  else:
    errors.add(maybeDoubleQuote.error)

  let maybeAlphabet = parser.consumeAlphabet()
  if maybeAlphabet.isOk:
    let token = maybeAlphabet.get
    if token.value notin "tn":
      return err(newParserError("strings only support '\\t' and '\\n'", token.loc))
    else:
      return ok(newAslNode(newStringContent("\\" & token.value,
          backslash.loc)))
  else:
    errors.add(maybeAlphabet.error)

  err(max(errors))

proc parseStringContent(parser: Parser): Result[AslNode, ParserError] =
  var errors: seq[ParserError]

  let maybeEscaped = parser.parse(parseEscapedStringCharacter)
  if maybeEscaped.isOk: return maybeEscaped
  else: errors.add(maybeEscaped.error)

  let maybeStrChar = parser.consumeExceptNewline("unescaped string character")
  if maybeStrChar.isOk:
    let token = maybeStrChar.get
    if token.value != "\"":
      return ok(newAslNode(newStringContent(token.value, token.loc)))
    else:
      errors.add(newParserError("expected a valid string character but found '{token.value}'", token.loc))
  else:
    errors.add(maybeStrChar.error)

  err(max(errors))

proc parseStringLiteral(parser: Parser): Result[AslNode, ParserError] =
  var content: string
  let leftDoubleQuote = ? parser.consumePunctuation("\"")
  content.add("\"")

  var maybeStrContent = parser.parse(parseStringContent)
  while maybeStrContent.isOk:
    let strContentNode = maybeStrContent.get
    assert strContentNode.kind == ankStrContent, "expected a string character"
    content.add(strContentNode.value)

    maybeStrContent = parser.parse(parseStringContent)

  discard ? parser.consumePunctuation("\"")
  content.add("\"")

  ok(newAslNode(newStringLiteral(content, leftDoubleQuote.loc)))

proc parseExpression(parser: Parser): Result[AslNode, ParserError]

proc parseArgumentList(parser: Parser): Result[AslNode, ParserError] =
  let openParen = ? parser.consumePunctuation("(")

  discard parser.parse(parseSpaces)

  var args: seq[Expression]
  var maybeArgument = parser.parse(parseExpression)
  while maybeArgument.isOk:
    let exprNode = maybeArgument.get
    assert exprNode.kind == ankExpression, "expected an expression"
    args.add(exprNode.expression)

    discard parser.parse(parseSpaces)

    let maybeComma = parser.consumePunctuation(",")
    if maybeComma.isErr: break

    discard parser.parse(parseSpaces)
    maybeArgument = parser.parse(parseExpression)

  discard ? parser.consumePunctuation(")")
  ok(newAslNode(newArgumentList(args, openParen.loc)))

proc parseFunctionCall(parser: Parser): Result[AslNode, ParserError] =
  let argTypeNode = ? parser.parse(parseArgumentType)
  assert argTypeNode.kind == ankArgType, "expected an argument type"
  let argType = argTypeNode.argType

  discard ? parser.consumePunctuation(".")

  let funcNameNode = ? parser.parse(parseIdentifier)
  assert funcNameNode.kind == ankIdentifier, "expected identifier"
  let funcName = funcNameNode.value

  discard parser.parse(parseSpaces)

  let argListNode = ? parser.parse(parseArgumentList)
  assert argListNode.kind == ankArgList, "expected an argument list"
  let argList = argListNode.argList

  ok(newAslNode(newFunctionCall(argType, funcName, argList)))

proc parseExpression(parser: Parser): Result[AslNode, ParserError] =
  var errors: seq[ParserError]

  let maybeStringLiteralNode = parser.parse(parseStringLiteral)
  if maybeStringLiteralNode.isOk:
    let stringLiteralNode = maybeStringLiteralNode.get
    assert stringLiteralNode.kind == ankStrLit, "expected string literal"
    return ok(newAslNode(newExpression(stringLiteralNode.strLit)))
  else:
    errors.add(maybeStringLiteralNode.error)

  let maybeFunctionCallNode = parser.parse(parseFunctionCall)
  if maybeFunctionCallNode.isOk:
    let fncallNode = maybeFunctionCallNode.get
    assert fncallNode.kind == ankFuncCall, "expected fncall"
    return ok(newAslNode(newExpression(fncallNode.fncall)))
  else:
    errors.add(maybeFunctionCallNode.error)

  err(max(errors))

proc parseAssignment(parser: Parser): Result[AslNode, ParserError] =
  let targetNode = ? parser.parse(parseIdentifier)
  assert targetNode.kind == ankIdentifier, "expected identifier"
  let target = targetNode.identifier.value

  discard parser.parse(parseSpaces)

  discard ? parser.consumePunctuation("=")

  discard parser.parse(parseSpaces)

  let expressionNode = ? parser.parse(parseExpression)
  assert expressionNode.kind == ankExpression, "expected expression"
  let expression = expressionNode.expression

  ok(newAslNode(newAssignment(target, expression, targetNode.loc)))


proc parseStatement(parser: Parser): Result[AslNode, ParserError] =
  var errors: seq[ParserError]

  let maybeExpression = parser.parse(parseExpression)
  if maybeExpression.isOk:
    let exprNode = maybeExpression.get
    assert exprNode.kind == ankExpression, "expected expression"
    return ok(newAslNode(newStatement(exprNode.expression)))
  else:
    errors.add(maybeExpression.error)


  let maybeAssignment = parser.parse(parseAssignment)
  if maybeAssignment.isOk:
    let assignmentNode = maybeAssignment.get
    assert assignmentNode.kind == ankAssignment, "expected assignment"
    let assignment = assignmentNode.assignment
    return ok(newAslNode(newStatement(assignment)))
  else:
    errors.add(maybeAssignment.error)

  err(max(errors))

proc parseStatementList(parser: Parser, level: uint32): Result[AslNode, ParserError] =
  var statements: seq[Statement]
  discard ? parser.parse(parseIndentation, level)

  var maybeStatement = parser.parse(parseStatement)
  while maybeStatement.isOk:
    let statementNode = maybeStatement.get
    assert statementNode.kind == ankStatement, "expected statement"
    statements.add(statementNode.statement)

    discard ? parser.parse(parseIgnorableLine)

    let maybeIndentation = parser.parse(parseIndentation, level)
    if maybeIndentation.isErr: break

    maybeStatement = parser.parse(parseStatement)

  ok(newAslNode(newStatementList(statements)))

proc parseFunction(parser: Parser, level: uint32): Result[AslNode, ParserError] =
  discard ? parser.parse(parseIndentation, level)
  let funcDefNode = ? parser.parse(parseFunctionDefinition)
  assert funcDefNode.kind == ankFuncDef, "expected a function definition"
  let funcDef = funcDefNode.funcDef
  discard ? parser.parse(parseIgnorableLine)
  let statementListNode = ? parser.parse(parseStatementList, level + 1)
  assert statementListNode.kind == ankStatementList, "expected statement list"
  let statementList = statementListNode.statementList

  ok(newAslNode(newFunction(funcDef, statementList)))

proc parseFunctionList(parser: Parser, level: uint32): Result[AslNode, ParserError] =
  var functions: seq[Function]
  var maybeFunction = parser.parse(parseFunction, level)
  while maybeFunction.isOk:
    let functionNode = maybeFunction.get
    assert functionNode.kind == ankFunction, "expected a function"
    functions.add(functionNode.function)

    # consume other empty lines
    var maybeLine = parser.parse(parseIgnorableLine)
    while maybeLine.isOk: maybeLine = parser.parse(parseIgnorableLine)

    maybeFunction = parser.parse(parseFunction, level)

  ok(newAslNode(newFunctionList(functions)))

proc parseModule(parser: Parser, level: uint32): Result[AslNode, ParserError] =
  discard ? parser.parse(parseIndentation, level)

  let moduleKeyword = ? parser.parse(parseIdentifier)
  assert moduleKeyword.kind == ankIdentifier, "expected identifier"
  if moduleKeyword.value != "module":
    let msg = fmt"expected macro 'module' but found '{moduleKeyword.value}'"
    return err(newParserError(msg, moduleKeyword.loc))

  discard ? parser.parse(parseSpaces)

  let moduleNameNode = ? parser.parse(parseIdentifier)
  assert moduleNameNode.kind == ankIdentifier, "expected identifier"
  let moduleName = moduleNameNode.value

  discard parser.parse(parseSpaces)

  discard ? parser.consumePunctuation(":")

  # required new line
  discard ? parser.parse(parseIgnorableLine)

  # consume other empty lines
  var maybeLine = parser.parse(parseIgnorableLine)
  while maybeLine.isOk: maybeLine = parser.parse(parseIgnorableLine)

  let funcListNode = ? parser.parse(parseFunctionList, level + 1)
  assert funcListNode.kind == ankFunctionList, "expected function list"
  ok(newAslNode(newModule(moduleName, funcListNode.funcList,
      moduleKeyword.loc)))

proc parseFile(parser: Parser): Result[AslNode, ParserError] =
  var modules: seq[Module]
  while not parser.done():
    var maybeIgnorableLine = parser.parse(parseIgnorableLine)
    while maybeIgnorableLine.isOk:
      maybeIgnorableLine = parser.parse(parseIgnorableLine)

    let moduleNode = ? parser.parse(parseModule, 0)
    assert moduleNode.kind == ankModule, "expected module"
    modules.add(moduleNode.module)

  ok(newAslNode(newFile(parser.filepath, modules)))

proc parse*(filepath: string, indentWidth: uint32, tokens: seq[Token]): Result[
    File, string] =
  let parser = newParser(filepath, indentWidth, tokens)
  let maybeFile = parseFile(parser)
  if maybeFile.isErr:
    err(fmt"{filepath}:{maybeFile.error}")
  else:
    let fileNode = maybeFile.get
    assert fileNode.kind == ankFile, "expected file"
    ok(fileNode.file)
