import strformat, strutils, results, options

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
    level*: uint32

proc newParser*(filepath: string, indentWidth: uint32, tokens: seq[
    Token]): Parser =
  Parser(filepath: filepath, indentWidth: indentWidth, tokens: tokens, index: 0, level: 0)

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

proc consumeTokenKind*(parser: Parser, kind: TokenKind,
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
  parser.consumeTokenKind(tkSpace, "space ' '")

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
  let indexCheckpoint = parser.index
  let levelCheckpoint = parser.level
  let maybeValue = spec.parseFn(parser)
  if maybeValue.isErr:
    parser.index = indexCheckpoint
    parser.level = levelCheckpoint
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
      let maybeValue = parser.run(spec)
      if maybeValue.isOk: return maybeValue
      errors.add(maybeValue.error)
    err(max(errors))
  )

proc any*[T](spec: Spec[T]): Spec[seq[T]] =
  Spec[seq[T]](
    name: spec.name & "*",
    parseFn: proc(parser: Parser): Result[seq[T], ParserError] =
    var items: seq[T]
    while true:
      let maybeValue = parser.run(spec)
      if maybeValue.isErr: break
      items.add(maybeValue.get)
    ok(items)
  )

proc atLeastOne*[T](spec: Spec[T]): Spec[seq[T]] =
  Spec[seq[T]](
    name: spec.name & "+",
    parseFn: proc(parser: Parser): Result[seq[T], ParserError] =
    let first = ? parser.run(spec)
    var items = @[first]
    let rest = ? parser.run(any(spec))
    items.add(rest)
    ok(items)
  )

proc optional*[T](spec: Spec[T]): Spec[Option[T]] =
  Spec[Option[T]](
    name: spec.name & "?",
    parseFn: proc(parser: Parser): Result[Option[T], ParserError] =
    let maybeValue = parser.run(spec)
    if maybeValue.isErr: ok(none(T))
    else: ok(some(maybeValue.get))
  )

proc map*[T, U](spec: Spec[T], name: string,
    fn: proc(v: T): U): Spec[U] =
  Spec[U](
    name: name,
    parseFn: proc(parser: Parser): Result[U, ParserError] =
    let value = ? parser.run(spec)
    ok(fn(value))
  )

proc separatedBy*[T, S](spec: Spec[T], sep: Spec[S]): Spec[seq[T]] =
  let pairSpec = Spec[T](
    name: spec.name & "_pair",
    parseFn: proc(parser: Parser): Result[T, ParserError] =
    discard ? parser.run(sep)
    let elem = ? parser.run(spec)
    ok(elem)
  )
  Spec[seq[T]](
    name: spec.name & "...",
    parseFn: proc(parser: Parser): Result[seq[T], ParserError] =
    var items: seq[T]
    let first = parser.run(spec)
    if first.isOk:
      items.add(first.get)
      let rest = ? parser.run(any(pairSpec))
      items.add(rest)
    ok(items)
  )

proc contained*[T](name: string, open: string, inner: Spec[T],
    close: string): Spec[T] =
  Spec[T](
    name: name,
    parseFn: proc(parser: Parser): Result[T, ParserError] =
    discard ? parser.consumePunctuation(open)
    while parser.consumeSpace().isOk: discard
    let maybeValue = ? parser.run(inner)
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
    parser.consumeTokenKind(kind, tokenRepr)
  )

proc punctuationSpec*(value: string): Spec[Token] =
  Spec[Token](
    name: "'" & value & "'",
    parseFn: proc(parser: Parser): Result[Token, ParserError] =
    parser.consumePunctuation(value)
  )

proc anyTokenExceptNewlineSpec*(tokenRepr: string): Spec[Token] =
  Spec[Token](
    name: tokenRepr,
    parseFn: proc(parser: Parser): Result[Token, ParserError] =
    parser.consumeExceptNewline(tokenRepr)
  )

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

type Space = ref object
  spaces: uint32
  loc: Location

proc newSpace(spaces: uint32, loc: Location): Space =
  Space(spaces: spaces, loc: loc)

type ArgumentType = ref object
  root: string
  impls: seq[ArgumentType]
  loc: Location

proc newArgumentType(root: string, loc: Location): ArgumentType =
  ArgumentType(root: root, loc: loc)

proc newArgumentType(root: string, impls: seq[ArgumentType],
    loc: Location): ArgumentType =
  ArgumentType(root: root, loc: loc, impls: impls)

proc asl(argType: ArgumentType): string =
  result = argType.root
  if argType.impls.len > 0:
    result.add("[")
    for i, impl in argType.impls:
      if i > 0: result.add(", ")
      result.add(asl(impl))
    result.add("]")

type ArgumentDefinition = ref object
  name: string
  argType: ArgumentType
  loc: Location

proc newArgumentDefinition(name: string, argType: ArgumentType,
    loc: Location): ArgumentDefinition =
  ArgumentDefinition(name: name, argType: argType, loc: loc)

proc asl(argDef: ArgumentDefinition): string =
  fmt"{argDef.name}: {asl(argDef.argType)}"

type ArgumentDefinitionList = ref object
  argDefs: seq[ArgumentDefinition]
  loc: Location

proc newArgumentDefinitionList(argDefs: seq[ArgumentDefinition],
    loc: Location): ArgumentDefinitionList =
  ArgumentDefinitionList(argDefs: argDefs, loc: loc)

proc asl(argDefList: ArgumentDefinitionList): string =
  result = "("
  for i, argDef in argDefList.argDefs:
    if i > 0: result.add(", ")
    result.add(asl(argDef))
  result.add(")")

type FunctionDefinition = ref object
  name: string
  argDefList: ArgumentDefinitionList
  returns: ArgumentType
  loc: Location

proc newFunctionDefinition(name: string, argDefList: ArgumentDefinitionList,
    returns: ArgumentType, loc: Location): FunctionDefinition =
  FunctionDefinition(name: name, argDefList: argDefList, returns: returns, loc: loc)

proc asl(funcDef: FunctionDefinition): string =
  fmt"func {funcDef.name}{asl(funcDef.argDefList)}: {asl(funcDef.returns)}"

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

proc newStringLiteral(content: string, loc: Location): StringLiteral =
  StringLiteral(content: content, loc: loc)

proc newFunctionCall(argType: ArgumentType, name: string,
    argList: ArgumentList): FunctionCall =
  FunctionCall(argType: argType, name: name, argList: argList)

proc newExpression(strLit: StringLiteral): Expression =
  Expression(kind: ekStrLit, strLit: strLit)

proc newExpression(fncall: FunctionCall): Expression =
  Expression(kind: ekFnCall, fncall: fncall)

proc asl(expr: Expression): string

proc asl(strLit: StringLiteral): string = strLit.content

proc asl(argList: ArgumentList): string =
  result = "("
  for i, arg in argList.args:
    if i > 0: result.add(", ")
    result.add(asl(arg))
  result.add(")")

proc asl(fncall: FunctionCall): string =
  fmt"{asl(fncall.argType)}.{fncall.name}{asl(fncall.argList)}"

proc asl(expr: Expression): string =
  case expr.kind:
  of ekStrLit: asl(expr.strLit)
  of ekFnCall: asl(expr.fncall)

type Assignment = ref object
  target: string
  expression: Expression
  loc: Location

proc newAssignment(target: string, expression: Expression,
    loc: Location): Assignment =
  Assignment(target: target, expression: expression, loc: loc)

proc asl(assignment: Assignment): string =
  fmt"{assignment.target} = {asl(assignment.expression)}"

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

proc asl(stmt: Statement): string =
  case stmt.kind:
  of skAssignment: asl(stmt.assignment)
  of skExpr: asl(stmt.expression)

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

proc asl(fn: Function, indentWidth: uint32): seq[string] =
  result.add(asl(fn.def))
  let indent = " ".repeat(indentWidth)
  for stmt in fn.statementList.statements:
    result.add(fmt"{indent}{asl(stmt)}")

type FunctionList = ref object
  functions: seq[Function]

proc newFunctionList(functions: seq[Function]): FunctionList =
  FunctionList(functions: functions)

type Import = ref object
  names: seq[string]
  source: string
  loc: Location

proc newImport(names: seq[string], source: string, loc: Location): Import =
  Import(names: names, source: source, loc: loc)

proc asl(imp: Import): string =
  result = "import { "
  for i, name in imp.names:
    if i > 0: result.add(", ")
    result.add(name)
  result.add(fmt" }} from {imp.source}")

type Generic = ref object
  name: string
  funcDefs: seq[FunctionDefinition]
  loc: Location

proc newGeneric(name: string, funcDefs: seq[FunctionDefinition],
    loc: Location): Generic =
  Generic(name: name, funcDefs: funcDefs, loc: loc)

proc asl(gen: Generic, indentWidth: uint32): seq[string] =
  result.add(fmt"generic {gen.name}:")
  let indent = " ".repeat(indentWidth)
  for funcDef in gen.funcDefs:
    result.add(fmt"{indent}{asl(funcDef)}")

type Module = ref object
  name: string
  funcList: FunctionList
  loc: Location

proc newModule(name: string, funcList: FunctionList, loc: Location): Module =
  Module(name: name, funcList: funcList, loc: loc)

proc asl(module: Module, indentWidth: uint32): seq[string] =
  result.add(fmt"module {module.name}:")
  let indent = " ".repeat(indentWidth)
  for i, fn in module.funcList.functions:
    if i > 0: result.add("")
    for line in asl(fn, indentWidth):
      result.add(fmt"{indent}{line}")

type
  FileItemKind = enum
    fikModule, fikGeneric
  FileItem = ref object
    case kind: FileItemKind
    of fikModule: module: Module
    of fikGeneric: generic: Generic

proc newFileItem(module: Module): FileItem =
  FileItem(kind: fikModule, module: module)

proc newFileItem(generic: Generic): FileItem =
  FileItem(kind: fikGeneric, generic: generic)

type File = ref object
  path: string
  imports: seq[Import]
  modules: seq[Module]
  generics: seq[Generic]

proc newFile(path: string, imports: seq[Import], items: seq[FileItem]): File =
  var modules: seq[Module]
  var generics: seq[Generic]
  for item in items:
    case item.kind:
    of fikModule: modules.add(item.module)
    of fikGeneric: generics.add(item.generic)
  File(path: path, imports: imports, modules: modules, generics: generics)

proc asl*(file: File, indentWidth: uint32): string =
  var lines: seq[string]
  for imp in file.imports:
    lines.add(asl(imp))
  if file.imports.len > 0 and (file.generics.len > 0 or file.modules.len > 0):
    lines.add("")
  for i, gen in file.generics:
    if i > 0: lines.add("")
    for line in asl(gen, indentWidth):
      lines.add(line)
  if file.generics.len > 0 and file.modules.len > 0:
    lines.add("")
  for i, module in file.modules:
    if i > 0: lines.add("")
    for line in asl(module, indentWidth):
      lines.add(line)
  lines.join("\n") & "\n"

# ============================================================
# Grammar specs
# ============================================================


let spaceSpec = tokenSpec(tkSpace, "space ' '")
let newlineSpec = tokenSpec(tkNewline, "newline '\\n'")
let alphabetSpec = tokenSpec(tkAlphabet, "alphabet [a-zA-Z]")
let digitSpec = tokenSpec(tkDigit, "digit [0-9]")
let underscoreSpec = punctuationSpec("_")
let hashSpec = punctuationSpec("#")
let backslashSpec = punctuationSpec("\\")
let doubleQuoteSpec = punctuationSpec("\"")

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

let identifierHeadCharSpec = oneOf("identifier_head", [
  underscoreSpec,
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
  discard parser.run(any(spaceSpec))
  let hashtag = ? parser.run(hashSpec)
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

let indentationSpec = Spec[Space](
  name: "indentation",
  parseFn: proc(parser: Parser): Result[Space, ParserError] =
  let loc = parser.loc
  let spaces = ? parser.run(any(spaceSpec))
  let count = spaces.len.uint32
  let expected = parser.indentWidth * parser.level
  if count != expected:
    let msg = fmt"indentation error expected {expected} but found {count} space(s)"
    err(newParserError(msg, loc))
  else:
    ok(newSpace(count, loc))
)

proc escapedSpec(character: string, charSpec: Spec[Token]): Spec[
    StringContent] =
  Spec[StringContent](
    name: "'\\" & character & "'",
    parseFn: proc(parser: Parser): Result[StringContent, ParserError] =
    let backslash = ? parser.run(backslashSpec)
    let token = ? parser.run(charSpec)
    if token.value != character:
      return err(newParserError(
        fmt"expected '\\{character}' but found '\\{token.value}'", token.loc))
    ok(newStringContent("\\" & character, backslash.loc))
  )

let escapedBackslash = escapedSpec("\\", backslashSpec)
let escapedDoubleQuote = escapedSpec("\"", doubleQuoteSpec)
let escapedNewline = escapedSpec("n", alphabetSpec)
let escapedTab = escapedSpec("t", alphabetSpec)

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
  let openQuote = ? parser.run(doubleQuoteSpec)
  var content = "\""
  let chars = ? parser.run(any(stringContentSpec))
  for ch in chars: content.add(ch.content)
  discard ? parser.run(doubleQuoteSpec)
  content.add("\"")
  ok(newStringLiteral(content, openQuote.loc))
)

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
  let loc = parser.loc
  let argDefs = ? parser.run(contained("argument_definition_list", "(",
    separatedBy(argumentDefinitionSpec, commaWithSpacesSpec), ")"))
  ok(newArgumentDefinitionList(argDefs, loc))
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

let statementLineSpec = Spec[Statement](
  name: "statement_line",
  parseFn: proc(parser: Parser): Result[Statement, ParserError] =
  discard ? parser.run(indentationSpec)
  let statement = ? parser.run(statementSpec)
  discard ? parser.run(ignorableLineSpec)
  ok(statement)
)

let statementListSpec = atLeastOne(statementLineSpec).map("statement_list",
  proc(stmts: seq[Statement]): StatementList = newStatementList(stmts))

proc blockSpec[H, B, R](name: string,
    header: Spec[H], body: Spec[B],
    combine: proc(h: H, b: B): R): Spec[R] =
  Spec[R](
    name: name,
    parseFn: proc(parser: Parser): Result[R, ParserError] =
    discard ? parser.run(indentationSpec)
    let h = ? parser.run(header)
    discard ? parser.run(ignorableLineSpec)
    parser.level += 1
    let b = ? parser.run(body)
    parser.level -= 1
    ok(combine(h, b))
  )

let functionSpec = blockSpec("function", functionDefinitionSpec,
  statementListSpec,
  proc(h: FunctionDefinition, b: StatementList): Function = newFunction(h, b))

# Each function block skips leading ignorable lines then parses a function.
# any() backtracks the ignorable line consumption if no function follows.
let funcBlockSpec = Spec[Function](
  name: "function_block",
  parseFn: proc(parser: Parser): Result[Function, ParserError] =
  discard parser.run(any(ignorableLineSpec))
  let f = ? parser.run(functionSpec)
  ok(f)
)

let functionListSpec = any(funcBlockSpec).map("function_list",
  proc(fns: seq[Function]): FunctionList = newFunctionList(fns))

type ModuleHeader = tuple[name: string, loc: Location]

let moduleHeaderSpec = Spec[ModuleHeader](
  name: "module_header",
  parseFn: proc(parser: Parser): Result[ModuleHeader, ParserError] =
  let loc = ? parser.run(keywordSpec("module"))
  discard ? parser.run(spacesSpec)
  let nameIdent = ? parser.run(identifierSpec)
  discard parser.run(spacesSpec)
  discard ? parser.run(punctuationSpec(":"))
  ok((nameIdent.name, loc))
)

type GenericHeader = tuple[name: string, loc: Location]

let genericHeaderSpec = Spec[GenericHeader](
  name: "generic_header",
  parseFn: proc(parser: Parser): Result[GenericHeader, ParserError] =
  let loc = ? parser.run(keywordSpec("generic"))
  discard ? parser.run(spacesSpec)
  let nameIdent = ? parser.run(identifierSpec)
  discard parser.run(spacesSpec)
  discard ? parser.run(punctuationSpec(":"))
  ok((nameIdent.name, loc))
)

# Function definition line: indentation + function signature + newline
let functionDefinitionLineSpec = Spec[FunctionDefinition](
  name: "function_definition_line",
  parseFn: proc(parser: Parser): Result[FunctionDefinition, ParserError] =
  discard ? parser.run(indentationSpec)
  let funcDef = ? parser.run(functionDefinitionSpec)
  discard ? parser.run(ignorableLineSpec)
  ok(funcDef)
)

let functionDefinitionListSpec = atLeastOne(functionDefinitionLineSpec)

let genericSpec = blockSpec("generic", genericHeaderSpec,
  functionDefinitionListSpec,
  proc(h: GenericHeader, b: seq[FunctionDefinition]): Generic = newGeneric(
      h.name, b, h.loc))

let moduleSpec = blockSpec("module", moduleHeaderSpec, functionListSpec,
  proc(h: ModuleHeader, b: FunctionList): Module = newModule(h.name, b, h.loc))

let fileItemSpec = oneOf("file_item", [
  moduleSpec.map("module_item",
    proc(v: Module): FileItem = newFileItem(v)),
  genericSpec.map("generic_item",
    proc(v: Generic): FileItem = newFileItem(v)),
])

# import { Name, Name } from "path"
let importLineSpec = Spec[Import](
  name: "import_line",
  parseFn: proc(parser: Parser): Result[Import, ParserError] =
  let loc = ? parser.run(keywordSpec("import"))
  discard ? parser.run(spacesSpec)
  let names = ? parser.run(contained("import_names", "{",
    separatedBy(identifierSpec, commaWithSpacesSpec), "}"))
  discard ? parser.run(spacesSpec)
  discard ? parser.run(keywordSpec("from"))
  discard ? parser.run(spacesSpec)
  let source = ? parser.run(stringLiteralSpec)
  discard ? parser.run(ignorableLineSpec)
  var nameStrings: seq[string]
  for n in names: nameStrings.add(n.name)
  ok(newImport(nameStrings, source.content, loc))
)

let importBlockSpec = Spec[Import](
  name: "import_block",
  parseFn: proc(parser: Parser): Result[Import, ParserError] =
  discard parser.run(any(ignorableLineSpec))
  let imp = ? parser.run(importLineSpec)
  ok(imp)
)

let fileItemBlockSpec = Spec[FileItem](
  name: "file_item_block",
  parseFn: proc(parser: Parser): Result[FileItem, ParserError] =
  discard parser.run(any(ignorableLineSpec))
  let item = ? parser.run(fileItemSpec)
  ok(item)
)

# file: import* (module | generic)*
let fileSpec = Spec[File](
  name: "file",
  parseFn: proc(parser: Parser): Result[File, ParserError] =
  let imports = ? parser.run(any(importBlockSpec))
  let items = ? parser.run(any(fileItemBlockSpec))
  discard parser.run(any(ignorableLineSpec))
  if not parser.done():
    # Force a parse attempt to get a specific error message
    discard ? parser.run(fileItemSpec)
  ok(newFile(parser.filepath, imports, items))
)

proc parse*(filepath: string, indentWidth: uint32, tokens: seq[Token]): Result[
    File, string] =
  let parser = newParser(filepath, indentWidth, tokens)
  let maybeFile = parser.run(fileSpec)
  if maybeFile.isErr:
    err(fmt"{filepath}:{maybeFile.error}")
  else:
    ok(maybeFile.get)
