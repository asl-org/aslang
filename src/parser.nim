import strformat, strutils, sequtils, results, options

import tokenizer

# ============================================================
# Parser Error
# ============================================================

type
  ParserError* = ref object
    loc*: Location
    msg*: string

proc newParserError*(msg: string, loc: Location): ParserError =
  ParserError(msg: msg, loc: loc)

proc `<`*(err1: ParserError, err2: ParserError): bool =
  err1.loc < err2.loc

proc `$`*(error: ParserError): string =
  fmt"{error.loc} {error.msg}"

# ============================================================
# Parser
# ============================================================

type
  Parser* = ref object
    filepath*: string
    indentWidth*: uint32
    tokens*: seq[Token]
    index*: int

proc newParser*(filepath: string, indentWidth: uint32,
    tokens: seq[Token]): Parser =
  Parser(filepath: filepath, indentWidth: indentWidth, tokens: tokens, index: 0)

proc done*(parser: Parser): bool =
  parser.index == parser.tokens.len

proc loc*(parser: Parser): Location =
  if parser.done(): parser.tokens[^1].loc
  else: parser.tokens[parser.index].loc

# ============================================================
# Token consumption
# ============================================================

proc peek*(parser: Parser, tokenRepr: string): Result[Token, ParserError] =
  if parser.done():
    let msg = fmt"expected {tokenRepr} but reached end of token stream"
    err(newParserError(msg, parser.loc))
  else:
    ok(parser.tokens[parser.index])

proc consume*(parser: Parser, tokenRepr: string): Result[Token, ParserError] =
  let token = ? parser.peek(tokenRepr)
  parser.index += 1
  ok(token)

proc consumeExceptNewline*(parser: Parser,
    tokenRepr: string): Result[Token, ParserError] =
  let token = ? parser.peek(tokenRepr)
  if token.kind == tkNewline:
    let msg = fmt"{token.repr} is not supported as {tokenRepr}"
    err(newParserError(msg, parser.loc))
  else:
    parser.index += 1
    ok(token)

proc consume*(parser: Parser, kind: TokenKind,
    tokenRepr: string): Result[Token, ParserError] =
  let token = ? parser.peek(tokenRepr)
  if token.kind != kind:
    let msg = fmt"expected {tokenRepr} but found {token.repr}"
    err(newParserError(msg, parser.loc))
  else:
    parser.index += 1
    ok(token)

proc consumePunctuation*(parser: Parser,
    value: string): Result[Token, ParserError] =
  let token = ? parser.peek(fmt"punctuation '{value}'")
  if token.kind != tkPunctuation or token.value != value:
    let msg = fmt"expected punctuation '{value}' but found {token.repr}"
    err(newParserError(msg, token.loc))
  else:
    parser.index += 1
    ok(token)

proc consumeSpace*(parser: Parser): Result[Token, ParserError] =
  parser.consume(tkSpace, "space ' '")

proc consumeNewline*(parser: Parser): Result[Token, ParserError] =
  parser.consume(tkNewline, "newline '\\n'")

proc consumeDigit*(parser: Parser): Result[Token, ParserError] =
  parser.consume(tkDigit, "digit [0-9]")

proc consumeAlphabet*(parser: Parser): Result[Token, ParserError] =
  parser.consume(tkAlphabet, "alphabet [a-zA-Z]")

proc consumeUtf8*(parser: Parser): Result[Token, ParserError] =
  parser.consume(tkUtf8, "utf8 character")

# ============================================================
# Spec[T] — named, typed parser combinator
# ============================================================

type
  Spec*[T] = ref object
    name*: string
    parseFn*: proc(parser: Parser): Result[T, ParserError]

proc newSpec*[T](name: string): Spec[T] =
  Spec[T](name: name, parseFn: nil)

proc run*[T](parser: Parser, spec: Spec[T]): Result[T, ParserError] =
  assert spec.parseFn != nil, "spec '" & spec.name & "' has no implementation"
  let checkpoint = parser.index
  let maybeValue = spec.parseFn(parser)
  if maybeValue.isErr:
    parser.index = checkpoint
  return maybeValue

# ============================================================
# Combinators
# ============================================================

proc oneOf*[T](name: string, specs: openArray[Spec[T]]): Spec[T] =
  let captured = @specs
  assert captured.len > 0, "oneOf requires at least one alternative"
  Spec[T](
    name: name,
    parseFn: proc(parser: Parser): Result[T, ParserError] =
    var errors: seq[ParserError]
    for spec in captured:
      let checkpoint = parser.index
      let maybeValue = spec.parseFn(parser)
      if maybeValue.isOk:
        return maybeValue
      parser.index = checkpoint
      errors.add(maybeValue.error)
    err(max(errors))
  )

proc any*[T](spec: Spec[T]): Spec[seq[T]] =
  Spec[seq[T]](
    name: spec.name & "*",
    parseFn: proc(parser: Parser): Result[seq[T], ParserError] =
    var items: seq[T]
    while true:
      let checkpoint = parser.index
      let maybeValue = spec.parseFn(parser)
      if maybeValue.isErr:
        parser.index = checkpoint
        break
      items.add(maybeValue.get)
    ok(items)
  )

proc atLeastOne*[T](spec: Spec[T]): Spec[seq[T]] =
  Spec[seq[T]](
    name: spec.name & "+",
    parseFn: proc(parser: Parser): Result[seq[T], ParserError] =
    var items: seq[T]
    let checkpoint = parser.index
    let first = spec.parseFn(parser)
    if first.isErr:
      parser.index = checkpoint
      return err(first.error)
    items.add(first.get)
    while true:
      let cp = parser.index
      let maybeValue = spec.parseFn(parser)
      if maybeValue.isErr:
        parser.index = cp
        break
      items.add(maybeValue.get)
    ok(items)
  )

proc optional*[T](spec: Spec[T]): Spec[Option[T]] =
  Spec[Option[T]](
    name: spec.name & "?",
    parseFn: proc(parser: Parser): Result[Option[T], ParserError] =
    let checkpoint = parser.index
    let maybeValue = spec.parseFn(parser)
    if maybeValue.isErr:
      parser.index = checkpoint
      ok(none(T))
    else:
      ok(some(maybeValue.get))
  )

proc map*[T, U](spec: Spec[T], name: string,
    fn: proc(v: T): U): Spec[U] =
  Spec[U](
    name: name,
    parseFn: proc(parser: Parser): Result[U, ParserError] =
    let maybeValue = spec.parseFn(parser)
    if maybeValue.isErr:
      err(maybeValue.error)
    else:
      ok(fn(maybeValue.get))
  )

proc separatedBy*[T, S](spec: Spec[T], sep: Spec[S]): Spec[seq[T]] =
  Spec[seq[T]](
    name: spec.name & "...",
    parseFn: proc(parser: Parser): Result[seq[T], ParserError] =
    var items: seq[T]
    # First element — optional
    let checkpoint = parser.index
    let first = spec.parseFn(parser)
    if first.isErr:
      parser.index = checkpoint
      return ok(items)
    items.add(first.get)
    # Subsequent (sep element)* pairs
    while true:
      let cp = parser.index
      let sepResult = sep.parseFn(parser)
      if sepResult.isErr:
        parser.index = cp
        break
      let elem = spec.parseFn(parser)
      if elem.isErr:
        parser.index = cp
        break
      items.add(elem.get)
    ok(items)
  )

proc contained*[T](name: string, open: string, inner: Spec[T],
    close: string): Spec[T] =
  Spec[T](
    name: name,
    parseFn: proc(parser: Parser): Result[T, ParserError] =
    discard ? parser.consumePunctuation(open)
    while parser.consumeSpace().isOk: discard
    let maybeValue = ? inner.parseFn(parser)
    while parser.consumeSpace().isOk: discard
    discard ? parser.consumePunctuation(close)
    ok(maybeValue)
  )

# ============================================================
# Leaf token specs
# ============================================================

proc tokenSpec*(kind: TokenKind, tokenRepr: string): Spec[Token] =
  Spec[Token](
    name: tokenRepr,
    parseFn: proc(parser: Parser): Result[Token, ParserError] =
    parser.consume(kind, tokenRepr)
  )

proc punctuationSpec*(value: string): Spec[Token] =
  Spec[Token](
    name: "'" & value & "'",
    parseFn: proc(parser: Parser): Result[Token, ParserError] =
    parser.consumePunctuation(value)
  )

proc anyTokenSpec*(tokenRepr: string): Spec[Token] =
  Spec[Token](
    name: tokenRepr,
    parseFn: proc(parser: Parser): Result[Token, ParserError] =
    parser.consume(tokenRepr)
  )

proc anyTokenExceptNewlineSpec*(tokenRepr: string): Spec[Token] =
  Spec[Token](
    name: tokenRepr,
    parseFn: proc(parser: Parser): Result[Token, ParserError] =
    parser.consumeExceptNewline(tokenRepr)
  )

let spaceSpec* = tokenSpec(tkSpace, "space ' '")
let newlineSpec* = tokenSpec(tkNewline, "newline '\\n'")
let alphabetSpec* = tokenSpec(tkAlphabet, "alphabet [a-zA-Z]")
let digitSpec* = tokenSpec(tkDigit, "digit [0-9]")
let utf8Spec* = tokenSpec(tkUtf8, "utf8 character")

# ============================================================
# AST types
# ============================================================

type EmptyLine = ref object
  loc: Location

proc newEmptyLine(loc: Location): EmptyLine =
  EmptyLine(loc: loc)

type
  Comment = ref object
    content: string
    loc: Location

proc newComment(content: string, loc: Location): Comment =
  Comment(content: content, loc: loc)

type
  Identifier = ref object
    name: string
    loc: Location

proc newIdentifier(name: string, loc: Location): Identifier =
  Identifier(name: name, loc: loc)

type Indentation = ref object
  indentation: uint32
  loc: Location

proc newIndentation(indentation: uint32, loc: Location): Indentation =
  Indentation(indentation: indentation, loc: loc)

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

type ArgumentDefinitionList = ref object
  argDefs: seq[ArgumentDefinition]
  loc: Location

proc newArgumentDefinitionList(argDefs: seq[ArgumentDefinition],
    loc: Location): ArgumentDefinitionList =
  ArgumentDefinitionList(argDefs: argDefs, loc: loc)

type FunctionDefinition = ref object
  name: string
  argDefList: ArgumentDefinitionList
  returns: ArgumentType
  loc: Location

proc newFunctionDefinition(name: string, argDefList: ArgumentDefinitionList,
    returns: ArgumentType, loc: Location): FunctionDefinition =
  FunctionDefinition(name: name, argDefList: argDefList, returns: returns, loc: loc)

type StringContent = ref object
  content: string
  loc: Location

proc newStringContent(content: string,
    loc: Location): StringContent =
  StringContent(content: content, loc: loc)

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

proc value(fncall: FunctionCall): string =
  fmt"{fncall.argType.value}.{fncall.name}{fncall.argList.value}"

proc newExpression(strLit: StringLiteral): Expression =
  Expression(kind: ekStrLit, strLit: strLit)

proc newExpression(fncall: FunctionCall): Expression =
  Expression(kind: ekFnCall, fncall: fncall)

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

type StatementList = ref object
  statements: seq[Statement]

proc newStatementList(statements: seq[Statement]): StatementList =
  StatementList(statements: statements)

type Function = ref object
  def: FunctionDefinition
  statementList: StatementList

proc newFunction(def: FunctionDefinition,
    statementList: StatementList): Function =
  Function(def: def, statementList: statementList)

type FunctionList = ref object
  functions: seq[Function]

proc newFunctionList(functions: seq[Function]): FunctionList =
  FunctionList(functions: functions)

type Module = ref object
  name: string
  funcList: FunctionList
  loc: Location

proc newModule(name: string, funcList: FunctionList, loc: Location): Module =
  Module(name: name, funcList: funcList, loc: loc)

type File = ref object
  path: string
  modules: seq[Module]

proc newFile(path: string, modules: seq[Module]): File =
  File(path: path, modules: modules)

# ============================================================
# Grammar specs
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

let escapedBackslash = escapedCharSpec("\\")
let escapedDoubleQuote = escapedCharSpec("\"")
let escapedNewline = escapedAlphaSpec("n")
let escapedTab = escapedAlphaSpec("t")

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
