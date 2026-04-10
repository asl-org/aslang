import strformat, strutils, results, options

import tokenizer

# ============================================================
# Parser Error
# ============================================================

type
  ParserError = ref object
    loc: Location
    msg: string
    fatal: bool

proc newParserError(msg: string, loc: Location): ParserError =
  ParserError(msg: msg, loc: loc)

proc `<`(err1: ParserError, err2: ParserError): bool =
  err1.loc < err2.loc

proc `$`(error: ParserError): string =
  fmt"{error.loc} {error.msg}"

# ============================================================
# Parser
# ============================================================

type
  Parser = ref object
    filepath: string
    indentWidth: uint32
    tokens: seq[Token]
    index: int
    level: uint32

proc newParser(filepath: string, indentWidth: uint32, tokens: seq[
    Token]): Parser =
  Parser(filepath: filepath, indentWidth: indentWidth, tokens: tokens, index: 0, level: 0)

proc done(parser: Parser): bool =
  parser.index == parser.tokens.len

proc loc(parser: Parser): Location =
  if parser.done(): parser.tokens[^1].loc
  else: parser.tokens[parser.index].loc

# ============================================================
# Token consumption
# ============================================================

proc peek(parser: Parser, tokenRepr: string): Result[Token, ParserError] =
  if parser.done():
    let msg = fmt"expected {tokenRepr} but reached end of token stream"
    err(newParserError(msg, parser.loc))
  else:
    ok(parser.tokens[parser.index])

proc consumeExceptNewline(parser: Parser,
    tokenRepr: string): Result[Token, ParserError] =
  let token = ? parser.peek(tokenRepr)
  if token.kind == tkNewline:
    let msg = fmt"{token.repr} is not supported as {tokenRepr}"
    err(newParserError(msg, parser.loc))
  else:
    parser.index += 1
    ok(token)

proc consumeTokenKind(parser: Parser, kind: TokenKind,
    tokenRepr: string): Result[Token, ParserError] =
  let token = ? parser.peek(tokenRepr)
  if token.kind != kind:
    let msg = fmt"expected {tokenRepr} but found {token.repr}"
    err(newParserError(msg, parser.loc))
  else:
    parser.index += 1
    ok(token)

proc consumePunctuation(parser: Parser,
    value: string): Result[Token, ParserError] =
  let token = ? parser.peek(fmt"punctuation '{value}'")
  if token.kind != tkPunctuation or token.value != value:
    let msg = fmt"expected punctuation '{value}' but found {token.repr}"
    err(newParserError(msg, token.loc))
  else:
    parser.index += 1
    ok(token)

proc consumeSpace(parser: Parser): Result[Token, ParserError] =
  parser.consumeTokenKind(tkSpace, "space ' '")

# ============================================================
# Spec[T] — named, typed parser combinator
# ============================================================

type
  Spec*[T] = ref object
    name*: string
    parseFn*: proc(parser: Parser): Result[T, ParserError]

proc newSpec[T](name: string): Spec[T] =
  Spec[T](name: name, parseFn: nil)

proc run[T](parser: Parser, spec: Spec[T]): Result[T, ParserError] =
  assert spec.parseFn != nil, "spec '" & spec.name & "' has no implementation"
  let indexCheckpoint = parser.index
  let levelCheckpoint = parser.level
  let maybeValue = spec.parseFn(parser)
  if maybeValue.isErr and not maybeValue.error.fatal:
    parser.index = indexCheckpoint
    parser.level = levelCheckpoint
  return maybeValue

# ============================================================
# Combinators
# ============================================================

proc oneOf[T](name: string, specs: openArray[Spec[T]]): Spec[T] =
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

proc any[T](spec: Spec[T]): Spec[seq[T]] =
  Spec[seq[T]](
    name: spec.name & "*",
    parseFn: proc(parser: Parser): Result[seq[T], ParserError] =
    var items: seq[T]
    while true:
      let maybeValue = parser.run(spec)
      if maybeValue.isErr:
        if maybeValue.error.fatal: return err(maybeValue.error)
        break
      items.add(maybeValue.get)
    ok(items)
  )

proc atLeastOne[T](spec: Spec[T]): Spec[seq[T]] =
  Spec[seq[T]](
    name: spec.name & "+",
    parseFn: proc(parser: Parser): Result[seq[T], ParserError] =
    let first = ? parser.run(spec)
    var items = @[first]
    let rest = ? parser.run(any(spec))
    items.add(rest)
    ok(items)
  )

proc optional[T](spec: Spec[T]): Spec[Option[T]] =
  Spec[Option[T]](
    name: spec.name & "?",
    parseFn: proc(parser: Parser): Result[Option[T], ParserError] =
    let maybeValue = parser.run(spec)
    if maybeValue.isErr: ok(none(T))
    else: ok(some(maybeValue.get))
  )

proc map[T, U](spec: Spec[T], name: string,
    fn: proc(v: T): U): Spec[U] =
  Spec[U](
    name: name,
    parseFn: proc(parser: Parser): Result[U, ParserError] =
    let value = ? parser.run(spec)
    ok(fn(value))
  )

proc separatedBy[T, S](spec: Spec[T], sep: Spec[S]): Spec[seq[T]] =
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

proc contained[T](name: string, open: string, inner: Spec[T],
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

proc tokenSpec(kind: TokenKind, tokenRepr: string): Spec[Token] =
  Spec[Token](
    name: tokenRepr,
    parseFn: proc(parser: Parser): Result[Token, ParserError] =
    parser.consumeTokenKind(kind, tokenRepr)
  )

proc punctuationSpec(value: string): Spec[Token] =
  Spec[Token](
    name: "'" & value & "'",
    parseFn: proc(parser: Parser): Result[Token, ParserError] =
    parser.consumePunctuation(value)
  )

proc anyTokenExceptNewlineSpec(tokenRepr: string): Spec[Token] =
  Spec[Token](
    name: tokenRepr,
    parseFn: proc(parser: Parser): Result[Token, ParserError] =
    parser.consumeExceptNewline(tokenRepr)
  )

# ============================================================
# AST types
# ============================================================

type Decorator = ref object
  name: string
  loc: Location

proc newDecorator(name: string, loc: Location): Decorator =
  Decorator(name: name, loc: loc)

proc asl(decorator: Decorator): string =
  fmt"@{decorator.name}"

type
  Identifier* = ref object
    name: string
    loc: Location

proc newIdentifier(name: string, loc: Location): Identifier =
  Identifier(name: name, loc: loc)

proc name*(id: Identifier): string = id.name
proc loc*(id: Identifier): Location = id.loc

proc asl(identifier: Identifier): string = identifier.name

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

type ArgumentDefinition* = ref object
  name: Identifier
  argType: ArgumentType
  loc: Location

proc name*(argDef: ArgumentDefinition): Identifier = argDef.name

proc newArgumentDefinition(name: Identifier, argType: ArgumentType,
    loc: Location): ArgumentDefinition =
  ArgumentDefinition(name: name, argType: argType, loc: loc)

proc asl(argDef: ArgumentDefinition): string =
  fmt"{argDef.name.name}: {asl(argDef.argType)}"

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

type Struct* = ref object
  fields: seq[ArgumentDefinition]
  loc: Location

proc fields*(s: Struct): seq[ArgumentDefinition] = s.fields

proc newStruct(fields: seq[ArgumentDefinition], loc: Location): Struct =
  Struct(fields: fields, loc: loc)

proc asl(s: Struct, indentWidth: uint32): seq[string] =
  result.add("struct:")
  let indent = " ".repeat(indentWidth)
  for field in s.fields:
    result.add(fmt"{indent}{asl(field)}")

type VariantDefinition* = ref object
  name: Identifier
  fields: seq[ArgumentDefinition]
  loc: Location

proc name*(v: VariantDefinition): Identifier = v.name
proc fields*(v: VariantDefinition): seq[ArgumentDefinition] = v.fields

proc newVariantDefinition(name: Identifier, fields: seq[ArgumentDefinition],
    loc: Location): VariantDefinition =
  VariantDefinition(name: name, fields: fields, loc: loc)

proc asl(varDef: VariantDefinition): string =
  result = varDef.name.name
  if varDef.fields.len > 0:
    result.add(" { ")
    for i, field in varDef.fields:
      if i > 0: result.add(", ")
      result.add(asl(field))
    result.add(" }")

type Union* = ref object
  variants: seq[VariantDefinition]
  loc: Location

proc variants*(u: Union): seq[VariantDefinition] = u.variants

proc newUnion(variants: seq[VariantDefinition], loc: Location): Union =
  Union(variants: variants, loc: loc)

proc asl(u: Union, indentWidth: uint32): seq[string] =
  result.add("union:")
  let indent = " ".repeat(indentWidth)
  for variant in u.variants:
    result.add(fmt"{indent}{asl(variant)}")

type
  DataBlockKind* = enum
    dbkStruct, dbkUnion
  DataBlock* = ref object
    case kind: DataBlockKind
    of dbkStruct: struct: Struct
    of dbkUnion: union: Union

proc kind*(db: DataBlock): DataBlockKind = db.kind
proc struct*(db: DataBlock): Struct =
  assert db.kind == dbkStruct,
    fmt"DataBlock.struct accessed but kind is {db.kind}"
  db.struct
proc union*(db: DataBlock): Union =
  assert db.kind == dbkUnion,
    fmt"DataBlock.union accessed but kind is {db.kind}"
  db.union

proc newDataBlock(s: Struct): DataBlock =
  DataBlock(kind: dbkStruct, struct: s)

proc newDataBlock(u: Union): DataBlock =
  DataBlock(kind: dbkUnion, union: u)

proc asl(db: DataBlock, indentWidth: uint32): seq[string] =
  case db.kind:
  of dbkStruct: asl(db.struct, indentWidth)
  of dbkUnion: asl(db.union, indentWidth)

type FunctionDefinition* = ref object
  name: string
  argDefList: ArgumentDefinitionList
  returns: ArgumentType
  loc: Location

proc name*(fd: FunctionDefinition): string = fd.name

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

  UnsignedIntegerLiteral = ref object
    value: string
    loc: Location

  SignedIntegerLiteral = ref object
    sign: string
    value: UnsignedIntegerLiteral
    loc: Location

  IntegerLiteralKind = enum
    ilkSigned, ilkUnsigned
  IntegerLiteral = ref object
    case kind: IntegerLiteralKind
    of ilkSigned: signed: SignedIntegerLiteral
    of ilkUnsigned: unsigned: UnsignedIntegerLiteral

  FloatLiteral = ref object
    value: string
    loc: Location

  FunctionCall = ref object
    argType: ArgumentType
    name: string
    argList: ArgumentList

  Getter = ref object
    source: string
    property: string
    loc: Location

  KeywordArgument = ref object
    name: string
    expression: Expression
    loc: Location

  KeywordArgumentList = ref object
    args: seq[KeywordArgument]
    loc: Location

  LiteralKind = enum
    lkString, lkInteger, lkFloat
  Literal = ref object
    case kind: LiteralKind
    of lkString: strLit: StringLiteral
    of lkInteger: intLit: IntegerLiteral
    of lkFloat: floatLit: FloatLiteral

  LiteralInitializer = ref object
    typeName: string
    value: Literal
    loc: Location

  StructInitializer = ref object
    argType: ArgumentType
    kwargList: KeywordArgumentList
    loc: Location

  UnionInitializer = ref object
    argType: ArgumentType
    variantName: string
    kwargList: KeywordArgumentList
    loc: Location

  InitializerKind = enum
    ikLiteral, ikStruct, ikUnion
  Initializer = ref object
    case kind: InitializerKind
    of ikLiteral: literal: LiteralInitializer
    of ikStruct: struct: StructInitializer
    of ikUnion: union: UnionInitializer

  ExpressionKind = enum
    ekLiteral, ekFnCall, ekGetter, ekInitializer, ekVariable, ekMatch
  Expression = ref object
    case kind: ExpressionKind
    of ekLiteral: literal: Literal
    of ekFnCall: fncall: FunctionCall
    of ekGetter: getter: Getter
    of ekInitializer: initializer: Initializer
    of ekVariable: variable: Identifier
    of ekMatch: match: MatchExpression

  Assignment = ref object
    target: string
    expression: Expression
    loc: Location

  VariantPatternField = ref object
    name: string
    binding: string
    loc: Location

  VariantPattern = ref object
    variantName: string
    fields: seq[VariantPatternField]
    loc: Location

  CasePatternKind = enum
    cpkIntegerLiteral, cpkVariable, cpkVariant
  CasePattern = ref object
    case kind: CasePatternKind
    of cpkIntegerLiteral: intLit: IntegerLiteral
    of cpkVariable: variable: Identifier
    of cpkVariant: variant: VariantPattern

  CaseBlock = ref object
    pattern: CasePattern
    body: StatementList
    loc: Location

  MatchExpression = ref object
    subject: Expression
    cases: seq[CaseBlock]
    loc: Location

  StatementKind = enum
    skAssignment, skExpr
  Statement = ref object
    case kind: StatementKind
    of skAssignment: assignment: Assignment
    of skExpr: expression: Expression

  StatementList = ref object
    statements: seq[Statement]

proc newArgumentList(args: seq[Expression], loc: Location): ArgumentList =
  ArgumentList(args: args, loc: loc)

proc newStringLiteral(content: string, loc: Location): StringLiteral =
  StringLiteral(content: content, loc: loc)

proc newFunctionCall(argType: ArgumentType, name: string,
    argList: ArgumentList): FunctionCall =
  FunctionCall(argType: argType, name: name, argList: argList)

proc newExpression(literal: Literal): Expression =
  Expression(kind: ekLiteral, literal: literal)

proc newExpression(fncall: FunctionCall): Expression =
  Expression(kind: ekFnCall, fncall: fncall)

proc newGetter(source: string, property: string, loc: Location): Getter =
  Getter(source: source, property: property, loc: loc)

proc newKeywordArgument(name: string, expression: Expression,
    loc: Location): KeywordArgument =
  KeywordArgument(name: name, expression: expression, loc: loc)

proc newKeywordArgumentList(args: seq[KeywordArgument],
    loc: Location): KeywordArgumentList =
  KeywordArgumentList(args: args, loc: loc)

proc newLiteral(strLit: StringLiteral): Literal =
  Literal(kind: lkString, strLit: strLit)

proc newLiteral(intLit: IntegerLiteral): Literal =
  Literal(kind: lkInteger, intLit: intLit)

proc newLiteral(floatLit: FloatLiteral): Literal =
  Literal(kind: lkFloat, floatLit: floatLit)

proc newLiteralInitializer(typeName: string, value: Literal,
    loc: Location): LiteralInitializer =
  LiteralInitializer(typeName: typeName, value: value, loc: loc)

proc newStructInitializer(argType: ArgumentType,
    kwargList: KeywordArgumentList, loc: Location): StructInitializer =
  StructInitializer(argType: argType, kwargList: kwargList, loc: loc)

proc newInitializer(literal: LiteralInitializer): Initializer =
  Initializer(kind: ikLiteral, literal: literal)

proc newInitializer(struct: StructInitializer): Initializer =
  Initializer(kind: ikStruct, struct: struct)

proc newUnionInitializer(argType: ArgumentType, variantName: string,
    kwargList: KeywordArgumentList, loc: Location): UnionInitializer =
  UnionInitializer(argType: argType, variantName: variantName,
    kwargList: kwargList, loc: loc)

proc newInitializer(union: UnionInitializer): Initializer =
  Initializer(kind: ikUnion, union: union)

proc newExpression(getter: Getter): Expression =
  Expression(kind: ekGetter, getter: getter)

proc newUnsignedIntegerLiteral(value: string,
    loc: Location): UnsignedIntegerLiteral =
  UnsignedIntegerLiteral(value: value, loc: loc)

proc newSignedIntegerLiteral(sign: string, value: UnsignedIntegerLiteral,
    loc: Location): SignedIntegerLiteral =
  SignedIntegerLiteral(sign: sign, value: value, loc: loc)

proc newIntegerLiteral(signed: SignedIntegerLiteral): IntegerLiteral =
  IntegerLiteral(kind: ilkSigned, signed: signed)

proc newIntegerLiteral(unsigned: UnsignedIntegerLiteral): IntegerLiteral =
  IntegerLiteral(kind: ilkUnsigned, unsigned: unsigned)

proc newFloatLiteral(value: string, loc: Location): FloatLiteral =
  FloatLiteral(value: value, loc: loc)

proc newExpression(initializer: Initializer): Expression =
  Expression(kind: ekInitializer, initializer: initializer)

proc newExpression(variable: Identifier): Expression =
  Expression(kind: ekVariable, variable: variable)

proc asl(expr: Expression): string

proc value(strLit: StringLiteral): string = strLit.content

proc asl(strLit: StringLiteral): string = fmt"""{strLit.content}"""

proc asl(unsigned: UnsignedIntegerLiteral): string = unsigned.value

proc asl(signed: SignedIntegerLiteral): string =
  fmt"{signed.sign}{asl(signed.value)}"

proc asl(intLit: IntegerLiteral): string =
  case intLit.kind:
  of ilkSigned: asl(intLit.signed)
  of ilkUnsigned: asl(intLit.unsigned)

proc asl(argList: ArgumentList): string =
  result = "("
  for i, arg in argList.args:
    if i > 0: result.add(", ")
    result.add(asl(arg))
  result.add(")")

proc asl(fncall: FunctionCall): string =
  fmt"{asl(fncall.argType)}.{fncall.name}{asl(fncall.argList)}"

proc asl(getter: Getter): string =
  fmt"{getter.source}.{getter.property}"

proc asl(kwarg: KeywordArgument): string =
  fmt"{kwarg.name}: {asl(kwarg.expression)}"

proc asl(kwargList: KeywordArgumentList): string =
  result = "{ "
  for i, arg in kwargList.args:
    if i > 0: result.add(", ")
    result.add(asl(arg))
  result.add(" }")

proc asl(floatLit: FloatLiteral): string = floatLit.value

proc asl(literal: Literal): string =
  case literal.kind:
  of lkString: asl(literal.strLit)
  of lkInteger: asl(literal.intLit)
  of lkFloat: asl(literal.floatLit)

proc asl(prim: LiteralInitializer): string =
  fmt"{prim.typeName} {asl(prim.value)}"

proc asl(nonPrim: StructInitializer): string =
  fmt"{asl(nonPrim.argType)} {asl(nonPrim.kwargList)}"

proc asl(unionInit: UnionInitializer): string =
  fmt"{asl(unionInit.argType)}.{unionInit.variantName} {asl(unionInit.kwargList)}"

proc asl(initializer: Initializer): string =
  case initializer.kind:
  of ikLiteral: asl(initializer.literal)
  of ikStruct: asl(initializer.struct)
  of ikUnion: asl(initializer.union)

proc asl(expr: Expression): string =
  case expr.kind:
  of ekLiteral: asl(expr.literal)
  of ekFnCall: asl(expr.fncall)
  of ekGetter: asl(expr.getter)
  of ekInitializer: asl(expr.initializer)
  of ekVariable: asl(expr.variable)
  of ekMatch: "" # match is a block expression, use aslBlock

proc newAssignment(target: string, expression: Expression,
    loc: Location): Assignment =
  Assignment(target: target, expression: expression, loc: loc)

proc asl(assignment: Assignment): string =
  fmt"{assignment.target} = {asl(assignment.expression)}"

proc newCasePattern(intLit: IntegerLiteral): CasePattern =
  CasePattern(kind: cpkIntegerLiteral, intLit: intLit)

proc newCasePattern(variable: Identifier): CasePattern =
  CasePattern(kind: cpkVariable, variable: variable)

proc newVariantPatternField(name: string, binding: string,
    loc: Location): VariantPatternField =
  VariantPatternField(name: name, binding: binding, loc: loc)

proc newVariantPattern(variantName: string, fields: seq[VariantPatternField],
    loc: Location): VariantPattern =
  VariantPattern(variantName: variantName, fields: fields, loc: loc)

proc newCasePattern(variant: VariantPattern): CasePattern =
  CasePattern(kind: cpkVariant, variant: variant)

proc asl(field: VariantPatternField): string =
  fmt"{field.name}: {field.binding}"

proc asl(variant: VariantPattern): string =
  result = fmt"{variant.variantName} {{ "
  for i, field in variant.fields:
    if i > 0: result.add(", ")
    result.add(asl(field))
  result.add(" }")

proc asl(pattern: CasePattern): string =
  case pattern.kind:
  of cpkIntegerLiteral: asl(pattern.intLit)
  of cpkVariable: asl(pattern.variable)
  of cpkVariant: asl(pattern.variant)

proc newCaseBlock(pattern: CasePattern, body: StatementList,
    loc: Location): CaseBlock =
  CaseBlock(pattern: pattern, body: body, loc: loc)

proc newMatchExpression(subject: Expression, cases: seq[CaseBlock],
    loc: Location): MatchExpression =
  MatchExpression(subject: subject, cases: cases, loc: loc)

proc newExpression(match: MatchExpression): Expression =
  Expression(kind: ekMatch, match: match)

proc newStatement(assignment: Assignment): Statement =
  Statement(kind: skAssignment, assignment: assignment)

proc newStatement(expression: Expression): Statement =
  Statement(kind: skExpr, expression: expression)

proc newStatementList(statements: seq[Statement]): StatementList =
  StatementList(statements: statements)

proc asl(caseBlock: CaseBlock, indentWidth: uint32): seq[string]
proc asl(matchExpr: MatchExpression, indentWidth: uint32): seq[string]

proc isBlockStatement(stmt: Statement): bool =
  case stmt.kind:
  of skExpr: stmt.expression.kind == ekMatch
  of skAssignment:
    stmt.assignment.expression.kind == ekMatch

proc asl(stmt: Statement): string
proc aslBlock(stmt: Statement, indentWidth: uint32): seq[string]

proc asl(stmt: Statement): string =
  case stmt.kind:
  of skAssignment: asl(stmt.assignment)
  of skExpr: asl(stmt.expression)

proc aslBlock(stmt: Statement, indentWidth: uint32): seq[string] =
  if not stmt.isBlockStatement:
    return @[asl(stmt)]
  case stmt.kind:
  of skExpr:
    result = asl(stmt.expression.match, indentWidth)
  of skAssignment:
    let matchLines = asl(stmt.assignment.expression.match, indentWidth)
    result.add(fmt"{stmt.assignment.target} = {matchLines[0]}")
    for i in 1..<matchLines.len:
      result.add(matchLines[i])

proc asl(caseBlock: CaseBlock, indentWidth: uint32): seq[string] =
  result.add(fmt"case {asl(caseBlock.pattern)}:")
  let indent = " ".repeat(indentWidth)
  for s in caseBlock.body.statements:
    for line in aslBlock(s, indentWidth):
      result.add(fmt"{indent}{line}")

proc asl(matchExpr: MatchExpression, indentWidth: uint32): seq[string] =
  result.add(fmt"match {asl(matchExpr.subject)}:")
  let indent = " ".repeat(indentWidth)
  for cb in matchExpr.cases:
    for line in asl(cb, indentWidth):
      result.add(fmt"{indent}{line}")

type Function* = ref object
  decorators: seq[Decorator]
  def: FunctionDefinition
  statementList: StatementList

proc name*(fn: Function): string = fn.def.name

proc newFunction(decorators: seq[Decorator], def: FunctionDefinition,
    statementList: StatementList): Function =
  Function(decorators: decorators, def: def, statementList: statementList)

proc asl(fn: Function, indentWidth: uint32): seq[string] =
  for d in fn.decorators:
    result.add(asl(d))
  result.add(asl(fn.def))
  let indent = " ".repeat(indentWidth)
  for stmt in fn.statementList.statements:
    for line in aslBlock(stmt, indentWidth):
      result.add(fmt"{indent}{line}")

type FunctionList = ref object
  functions: seq[Function]

proc newFunctionList(functions: seq[Function]): FunctionList =
  FunctionList(functions: functions)

type ImportName* = ref object
  name: string
  alias: string # empty if no alias
  loc: Location

proc name*(n: ImportName): string = n.name
proc alias*(n: ImportName): string = n.alias

proc newImportName(name: string, alias: string, loc: Location): ImportName =
  ImportName(name: name, alias: alias, loc: loc)

proc asl(importName: ImportName): string =
  if importName.alias.len > 0:
    fmt"{importName.name} as {importName.alias}"
  else:
    importName.name

type Import* = ref object
  names: seq[ImportName]
  source: string
  loc: Location

proc newImport(names: seq[ImportName], source: string, loc: Location): Import =
  Import(names: names, source: source, loc: loc)

proc names*(imp: Import): seq[ImportName] = imp.names
proc source*(imp: Import): string = imp.source

proc asl(imp: Import): string =
  result = "import { "
  for i, name in imp.names:
    if i > 0: result.add(", ")
    result.add(asl(name))
  result.add(fmt" }} from ""{imp.source}""")

type Generic* = ref object
  decorators: seq[Decorator]
  name: Identifier
  funcDefs: seq[FunctionDefinition]
  loc: Location

proc name*(g: Generic): Identifier = g.name
proc funcDefs*(g: Generic): seq[FunctionDefinition] = g.funcDefs

proc newGeneric(decorators: seq[Decorator], name: Identifier,
    funcDefs: seq[FunctionDefinition], loc: Location): Generic =
  Generic(decorators: decorators, name: name, funcDefs: funcDefs, loc: loc)

proc asl(gen: Generic, indentWidth: uint32): seq[string] =
  for d in gen.decorators:
    result.add(asl(d))
  result.add(fmt"generic {gen.name.name}:")
  let indent = " ".repeat(indentWidth)
  for funcDef in gen.funcDefs:
    result.add(fmt"{indent}{asl(funcDef)}")

type Module* = ref object
  decorators: seq[Decorator]
  name: Identifier
  data: Option[DataBlock]
  funcList: FunctionList
  loc: Location

proc name*(m: Module): Identifier = m.name
proc data*(m: Module): Option[DataBlock] = m.data
proc functions*(m: Module): seq[Function] = m.funcList.functions

proc newModule(decorators: seq[Decorator], name: Identifier,
    data: Option[DataBlock], funcList: FunctionList, loc: Location): Module =
  Module(decorators: decorators, name: name, data: data,
    funcList: funcList, loc: loc)

proc asl(module: Module, indentWidth: uint32): seq[string] =
  for d in module.decorators:
    result.add(asl(d))
  result.add(fmt"module {module.name.name}:")
  let indent = " ".repeat(indentWidth)
  if module.data.isSome:
    for line in asl(module.data.get, indentWidth):
      result.add(fmt"{indent}{line}")
    result.add("")
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

type File* = ref object
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

proc path*(file: File): string = file.path
proc imports*(file: File): seq[Import] = file.imports
proc modules*(file: File): seq[Module] = file.modules
proc generics*(file: File): seq[Generic] = file.generics

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

let commentSpec = Spec[Location](
  name: "comment",
  parseFn: proc(parser: Parser): Result[Location, ParserError] =
  let hashtag = ? parser.run(hashSpec)
  discard parser.run(any(anyTokenExceptNewlineSpec("comment character")))
  ok(hashtag.loc)
)

# ============================================================
# Implicit separators
# ============================================================

let strictSpace = atLeastOne(spaceSpec)
let optionalSpace = any(spaceSpec)

# space* comment? newline
let ignorableLineSpec = Spec[Location](
  name: "ignorable_line",
  parseFn: proc(parser: Parser): Result[Location, ParserError] =
  let loc = parser.loc
  discard ? parser.run(any(spaceSpec))
  discard ? parser.run(optional(commentSpec))
  discard ? parser.run(newlineSpec)
  ok(loc)
)

let strictLine = ignorableLineSpec
let optionalLines = any(ignorableLineSpec)

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

let escapedStringContentSpec = oneOf("escaped_string_character", [
  escapedBackslash,
  escapedDoubleQuote,
  escapedNewline,
  escapedTab,
])

let unescapedStringContentSpec = Spec[StringContent](
  name: "unescaped_string_character",
  parseFn: proc(parser: Parser): Result[StringContent, ParserError] =
  let token = ? parser.run(anyTokenExceptNewlineSpec("unescaped string character"))
  if token.value == "\"" or token.value == "\\":
    return err(newParserError(
      fmt"expected a valid string character but found '{token.value}'", token.loc))
  ok(newStringContent(token.value, token.loc))
)

let stringContentSpec = oneOf("string_content", [
  escapedStringContentSpec,
  unescapedStringContentSpec,
])

let stringLiteralSpec = Spec[StringLiteral](
  name: "string_literal",
  parseFn: proc(parser: Parser): Result[StringLiteral, ParserError] =
  let openQuote = ? parser.run(doubleQuoteSpec)
  let chars = ? parser.run(any(stringContentSpec))
  var content: string; for ch in chars: content.add(ch.content)
  discard ? parser.run(doubleQuoteSpec)
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
  ok(newArgumentDefinition(argName, argType, argName.loc))
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
  discard ? parser.run(strictSpace)
  let funcName = ? parser.run(identifierSpec)
  discard parser.run(optionalSpace)
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
  discard parser.run(optionalSpace)
  let argList = ? parser.run(argumentListSpec)
  ok(newFunctionCall(argType, funcNameIdent.name, argList))
)

let kwargSpec = Spec[KeywordArgument](
  name: "keyword_argument",
  parseFn: proc(parser: Parser): Result[KeywordArgument, ParserError] =
  let name = ? parser.run(identifierSpec)
  discard ? parser.run(colonWithSpacesSpec)
  let expression = ? parser.run(expressionSpec)
  ok(newKeywordArgument(name.name, expression, name.loc))
)

let kwargListSpec = Spec[KeywordArgumentList](
  name: "keyword_argument_list",
  parseFn: proc(parser: Parser): Result[KeywordArgumentList, ParserError] =
  let loc = parser.loc
  let args = ? parser.run(contained("keyword_argument_list", "{",
    separatedBy(kwargSpec, commaWithSpacesSpec), "}"))
  ok(newKeywordArgumentList(args, loc))
)

# digit+
let unsignedIntegerLiteralSpec = Spec[UnsignedIntegerLiteral](
  name: "unsigned_integer_literal",
  parseFn: proc(parser: Parser): Result[UnsignedIntegerLiteral, ParserError] =
  let loc = parser.loc
  let digits = ? parser.run(atLeastOne(digitSpec))
  var value: string
  for d in digits: value.add(d.value)
  ok(newUnsignedIntegerLiteral(value, loc))
)

# (+ | -) digit+
let signedIntegerLiteralSpec = Spec[SignedIntegerLiteral](
  name: "signed_integer_literal",
  parseFn: proc(parser: Parser): Result[SignedIntegerLiteral, ParserError] =
  let signToken = ? parser.run(oneOf("sign", [
    punctuationSpec("+"),
    punctuationSpec("-"),
  ]))
  let uint = ? parser.run(unsignedIntegerLiteralSpec)
  ok(newSignedIntegerLiteral(signToken.value, uint, signToken.loc))
)

let integerLiteralSpec = oneOf("integer_literal", [
  signedIntegerLiteralSpec.map("signed_int",
    proc(v: SignedIntegerLiteral): IntegerLiteral = newIntegerLiteral(v)),
  unsignedIntegerLiteralSpec.map("unsigned_int",
    proc(v: UnsignedIntegerLiteral): IntegerLiteral = newIntegerLiteral(v)),
])

# (+|-)? digit+ ("." digit+)? ((e|E) (+|-)? digit+)?
# Must have either decimal part or exponent to distinguish from integer
let floatLiteralSpec = Spec[FloatLiteral](
  name: "float_literal",
  parseFn: proc(parser: Parser): Result[FloatLiteral, ParserError] =
  let loc = parser.loc
  var value: string
  let signSpec = oneOf("sign", [punctuationSpec("+"), punctuationSpec("-")])
  # Optional sign
  let maybeSign = parser.run(signSpec)
  if maybeSign.isOk: value.add(maybeSign.get.value)
  # Integer part (required)
  let intDigits = ? parser.run(atLeastOne(digitSpec))
  for d in intDigits: value.add(d.value)
  # Decimal part (optional)
  var hasDecimal = false
  let maybeDot = parser.run(punctuationSpec("."))
  if maybeDot.isOk:
    hasDecimal = true
    value.add(".")
    let fracDigits = ? parser.run(atLeastOne(digitSpec))
    for d in fracDigits: value.add(d.value)
  # Exponent part (optional)
  var hasExponent = false
  let maybeE = parser.run(oneOf("exponent", [
    alphabetSpec, alphabetSpec,
  ]))
  if maybeE.isOk and (maybeE.get.value == "e" or maybeE.get.value == "E"):
    hasExponent = true
    value.add(maybeE.get.value)
    let maybeExpSign = parser.run(signSpec)
    if maybeExpSign.isOk: value.add(maybeExpSign.get.value)
    let expDigits = ? parser.run(atLeastOne(digitSpec))
    for d in expDigits: value.add(d.value)
  # Must have at least decimal or exponent to be a float
  if not hasDecimal and not hasExponent:
    return err(newParserError("expected '.' or 'e' for float literal", loc))
  ok(newFloatLiteral(value, loc))
)

let literalSpec = oneOf("literal", [
  stringLiteralSpec.map("string_literal",
    proc(v: StringLiteral): Literal = newLiteral(v)),
  floatLiteralSpec.map("float_literal",
    proc(v: FloatLiteral): Literal = newLiteral(v)),
  integerLiteralSpec.map("integer_literal",
    proc(v: IntegerLiteral): Literal = newLiteral(v)),
])

# Type.Variant { fields }
let unionInitializerSpec = Spec[UnionInitializer](
  name: "union_initializer",
  parseFn: proc(parser: Parser): Result[UnionInitializer, ParserError] =
  let argType = ? parser.run(argumentTypeSpec)
  discard ? parser.run(punctuationSpec("."))
  let variantName = ? parser.run(identifierSpec)
  discard parser.run(optionalSpace)
  let kwargList = ? parser.run(kwargListSpec)
  ok(newUnionInitializer(argType, variantName.name, kwargList, argType.loc))
)

# Type { fields }
let structInitializerSpec = Spec[StructInitializer](
  name: "struct_initializer",
  parseFn: proc(parser: Parser): Result[StructInitializer, ParserError] =
  let argType = ? parser.run(argumentTypeSpec)
  discard parser.run(optionalSpace)
  let kwargList = ? parser.run(kwargListSpec)
  ok(newStructInitializer(argType, kwargList, argType.loc))
)

# type literal
let literalInitializerSpec = Spec[LiteralInitializer](
  name: "literal_initializer",
  parseFn: proc(parser: Parser): Result[LiteralInitializer, ParserError] =
  let typeName = ? parser.run(identifierSpec)
  discard ? parser.run(strictSpace)
  let value = ? parser.run(literalSpec)
  ok(newLiteralInitializer(typeName.name, value, typeName.loc))
)

let initializerSpec = oneOf("initializer", [
  unionInitializerSpec.map("union",
    proc(v: UnionInitializer): Initializer = newInitializer(v)),
  structInitializerSpec.map("struct",
    proc(v: StructInitializer): Initializer = newInitializer(v)),
  literalInitializerSpec.map("literal",
    proc(v: LiteralInitializer): Initializer = newInitializer(v)),
])

let getterSpec = Spec[Getter](
  name: "getter",
  parseFn: proc(parser: Parser): Result[Getter, ParserError] =
  let source = ? parser.run(identifierSpec)
  discard ? parser.run(punctuationSpec("."))
  let property = ? parser.run(identifierSpec)
  ok(newGetter(source.name, property.name, source.loc))
)

expressionSpec.parseFn = oneOf("expression", [
  literalSpec.map("literal_expression",
    proc(v: Literal): Expression = newExpression(v)),
  initializerSpec.map("initializer_expression",
    proc(v: Initializer): Expression = newExpression(v)),
  functionCallSpec.map("fncall_expression",
    proc(v: FunctionCall): Expression = newExpression(v)),
  getterSpec.map("getter_expression",
    proc(v: Getter): Expression = newExpression(v)),
  identifierSpec.map("variable_expression",
    proc(v: Identifier): Expression = newExpression(v)),
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

let decoratorLineSpec = Spec[Decorator](
  name: "decorator_line",
  parseFn: proc(parser: Parser): Result[Decorator, ParserError] =
  discard ? parser.run(indentationSpec)
  discard ? parser.run(punctuationSpec("@"))
  let name = ? parser.run(identifierSpec)
  discard ? parser.run(strictLine)
  ok(newDecorator(name.name, name.loc))
)

# Block without decorator support (case, struct, union, generic)
proc blockSpec[H, B, R](name: string,
    header: Spec[H], body: Spec[B],
    combine: proc(h: H, b: B): R): Spec[R] =
  Spec[R](
    name: name,
    parseFn: proc(parser: Parser): Result[R, ParserError] =
    discard ? parser.run(indentationSpec)
    let h = ? parser.run(header)
    discard ? parser.run(strictLine)
    # After header succeeds, body errors are fatal — they propagate
    # through run and any without backtracking or being swallowed.
    parser.level += 1
    let bodyResult = body.parseFn(parser)
    parser.level -= 1
    if bodyResult.isErr:
      bodyResult.error.fatal = true
      return err(bodyResult.error)
    ok(combine(h, bodyResult.get))
  )

# Block with decorator support (module, function)
proc decoratedBlockSpec[H, B, R](name: string,
    header: Spec[H], body: Spec[B],
    combine: proc(decorators: seq[Decorator], h: H, b: B): R): Spec[R] =
  Spec[R](
    name: name,
    parseFn: proc(parser: Parser): Result[R, ParserError] =
    let decorators = ? parser.run(any(decoratorLineSpec))
    discard ? parser.run(indentationSpec)
    let h = ? parser.run(header)
    discard ? parser.run(strictLine)
    parser.level += 1
    let bodyResult = body.parseFn(parser)
    parser.level -= 1
    if bodyResult.isErr:
      bodyResult.error.fatal = true
      return err(bodyResult.error)
    ok(combine(decorators, h, bodyResult.get))
  )

# Variant pattern field: name ":" binding (both identifiers)
let variantPatternFieldSpec = Spec[VariantPatternField](
  name: "variant_pattern_field",
  parseFn: proc(parser: Parser): Result[VariantPatternField, ParserError] =
  let name = ? parser.run(identifierSpec)
  discard ? parser.run(colonWithSpacesSpec)
  let binding = ? parser.run(identifierSpec)
  ok(newVariantPatternField(name.name, binding.name, name.loc))
)

# Variant pattern: VariantName { field: binding, field: binding }
let variantPatternSpec = Spec[VariantPattern](
  name: "variant_pattern",
  parseFn: proc(parser: Parser): Result[VariantPattern, ParserError] =
  let name = ? parser.run(identifierSpec)
  discard parser.run(optionalSpace)
  let fields = ? parser.run(contained("variant_fields", "{",
    separatedBy(variantPatternFieldSpec, commaWithSpacesSpec), "}"))
  ok(newVariantPattern(name.name, fields, name.loc))
)

let casePatternSpec = oneOf("case_pattern", [
  integerLiteralSpec.map("integer_pattern",
    proc(v: IntegerLiteral): CasePattern = newCasePattern(v)),
  variantPatternSpec.map("variant_pattern",
    proc(v: VariantPattern): CasePattern = newCasePattern(v)),
  identifierSpec.map("variable_pattern",
    proc(v: Identifier): CasePattern = newCasePattern(v)),
])

# Forward declare statementListSpec for mutual recursion:
# match -> caseBlock -> statementList -> statementLine -> statement -> match
let statementListSpec = newSpec[StatementList]("statement_list")

let caseHeaderSpec = Spec[CasePattern](
  name: "case_header",
  parseFn: proc(parser: Parser): Result[CasePattern, ParserError] =
  discard ? parser.run(keywordSpec("case"))
  discard ? parser.run(strictSpace)
  let pattern = ? parser.run(casePatternSpec)
  discard parser.run(optionalSpace)
  discard ? parser.run(punctuationSpec(":"))
  ok(pattern)
)

proc loc(pattern: CasePattern): Location =
  case pattern.kind:
  of cpkIntegerLiteral:
    case pattern.intLit.kind:
    of ilkSigned: pattern.intLit.signed.loc
    of ilkUnsigned: pattern.intLit.unsigned.loc
  of cpkVariable: pattern.variable.loc
  of cpkVariant: pattern.variant.loc

let caseBlockSpec = blockSpec("case", caseHeaderSpec, statementListSpec,
  proc(h: CasePattern, b: StatementList): CaseBlock =
  newCaseBlock(h, b, h.loc))

let inlineStatementSpec = oneOf("inline_statement", [
  assignmentSpec.map("assignment_statement",
    proc(v: Assignment): Statement = newStatement(v)),
  expressionSpec.map("expression_statement",
    proc(v: Expression): Statement = newStatement(v)),
])

# Match body: parses "match" keyword + subject + ":" + newline + caseBlocks
# Does NOT consume indentation — caller handles that
let matchBodySpec = Spec[MatchExpression](
  name: "match_body",
  parseFn: proc(parser: Parser): Result[MatchExpression, ParserError] =
  let loc = ? parser.run(keywordSpec("match"))
  discard ? parser.run(strictSpace)
  # Match expressions cannot be the subject of another match expression.
  # expressionSpec intentionally excludes match (match is parsed separately
  # in statementLineSpec). This check guards against future changes that
  # might add match to expressionSpec.
  let subject = ? parser.run(expressionSpec)
  if subject.kind == ekMatch:
    return err(newParserError(
      "match expression cannot be the subject of another match", loc))
  discard parser.run(optionalSpace)
  discard ? parser.run(punctuationSpec(":"))
  discard ? parser.run(strictLine)
  parser.level += 1
  let casesBody = atLeastOne(Spec[CaseBlock](
    name: "case_block_line",
    parseFn: proc(parser: Parser): Result[CaseBlock, ParserError] =
    discard parser.run(optionalLines)
    let cb = ? parser.run(caseBlockSpec)
    ok(cb)
  ))
  let casesResult = casesBody.parseFn(parser)
  parser.level -= 1
  if casesResult.isErr:
    casesResult.error.fatal = true
    return err(casesResult.error)
  ok(newMatchExpression(subject, casesResult.get, loc))
)

let statementLineSpec = Spec[Statement](
  name: "statement_line",
  parseFn: proc(parser: Parser): Result[Statement, ParserError] =
  discard parser.run(optionalLines)
  discard ? parser.run(indentationSpec)
  # Try match assignment: identifier = match ...:
  let maybeMatchAssign = parser.run(Spec[Statement](
    name: "match_assignment",
    parseFn: proc(parser: Parser): Result[Statement, ParserError] =
    let target = ? parser.run(identifierSpec)
    discard ? parser.run(equalsSeparatorSpec)
    let matchExpr = ? parser.run(matchBodySpec)
    ok(newStatement(newAssignment(target.name, newExpression(matchExpr), target.loc)))
  ))
  if maybeMatchAssign.isOk: return ok(maybeMatchAssign.get)
  # Try standalone match: match ...:
  let maybeMatch = parser.run(matchBodySpec)
  if maybeMatch.isOk:
    return ok(newStatement(newExpression(maybeMatch.get)))
  # Inline statements: statement + newline
  let statement = ? parser.run(inlineStatementSpec)
  discard ? parser.run(strictLine)
  ok(statement)
)

statementListSpec.parseFn = atLeastOne(statementLineSpec).map("statement_list",
  proc(stmts: seq[Statement]): StatementList = newStatementList(stmts)).parseFn

let functionSpec = decoratedBlockSpec("function", functionDefinitionSpec,
  statementListSpec,
  proc(d: seq[Decorator], h: FunctionDefinition, b: StatementList): Function =
  newFunction(d, h, b))

# Each function block skips leading ignorable lines then parses a function.
# any() backtracks the ignorable line consumption if no function follows.
let funcBlockSpec = Spec[Function](
  name: "function_block",
  parseFn: proc(parser: Parser): Result[Function, ParserError] =
  discard parser.run(optionalLines)
  let f = ? parser.run(functionSpec)
  ok(f)
)

let functionListSpec = any(funcBlockSpec).map("function_list",
  proc(fns: seq[Function]): FunctionList = newFunctionList(fns))

type ModuleHeader = tuple[name: Identifier, loc: Location]

let moduleHeaderSpec = Spec[ModuleHeader](
  name: "module_header",
  parseFn: proc(parser: Parser): Result[ModuleHeader, ParserError] =
  let loc = ? parser.run(keywordSpec("module"))
  discard ? parser.run(strictSpace)
  let nameIdent = ? parser.run(identifierSpec)
  discard parser.run(optionalSpace)
  discard ? parser.run(punctuationSpec(":"))
  ok((nameIdent, loc))
)

type GenericHeader = tuple[name: Identifier, loc: Location]

let genericHeaderSpec = Spec[GenericHeader](
  name: "generic_header",
  parseFn: proc(parser: Parser): Result[GenericHeader, ParserError] =
  let loc = ? parser.run(keywordSpec("generic"))
  discard ? parser.run(strictSpace)
  let nameIdent = ? parser.run(identifierSpec)
  discard parser.run(optionalSpace)
  discard ? parser.run(punctuationSpec(":"))
  ok((nameIdent, loc))
)

# Function definition line: indentation + function signature + newline
let functionDefinitionLineSpec = Spec[FunctionDefinition](
  name: "function_definition_line",
  parseFn: proc(parser: Parser): Result[FunctionDefinition, ParserError] =
  discard ? parser.run(indentationSpec)
  let funcDef = ? parser.run(functionDefinitionSpec)
  discard ? parser.run(strictLine)
  ok(funcDef)
)

let functionDefinitionListSpec = atLeastOne(functionDefinitionLineSpec)

let genericSpec = blockSpec("generic", genericHeaderSpec,
  functionDefinitionListSpec,
  proc(h: GenericHeader, b: seq[FunctionDefinition]): Generic =
  newGeneric(@[], h.name, b, h.loc))

# struct: field+ (field is identifier ":" argumentType)
let structHeaderSpec = Spec[Location](
  name: "struct_header",
  parseFn: proc(parser: Parser): Result[Location, ParserError] =
  let loc = ? parser.run(keywordSpec("struct"))
  discard parser.run(optionalSpace)
  discard ? parser.run(punctuationSpec(":"))
  ok(loc)
)

# Each field line: indentation + argumentDefinition + newline
let fieldLineSpec = Spec[ArgumentDefinition](
  name: "field_line",
  parseFn: proc(parser: Parser): Result[ArgumentDefinition, ParserError] =
  discard parser.run(optionalLines)
  discard ? parser.run(indentationSpec)
  let argDef = ? parser.run(argumentDefinitionSpec)
  discard ? parser.run(strictLine)
  ok(argDef)
)

let structSpec = blockSpec("struct", structHeaderSpec,
  atLeastOne(fieldLineSpec),
  proc(h: Location, b: seq[ArgumentDefinition]): Struct =
  newStruct(b, h))

# union: variant+ (variant is identifier space* ("{" argDef, argDef "}")?)
let variantDefinitionLineSpec = Spec[VariantDefinition](
  name: "variant_definition_line",
  parseFn: proc(parser: Parser): Result[VariantDefinition, ParserError] =
  discard parser.run(optionalLines)
  discard ? parser.run(indentationSpec)
  let name = ? parser.run(identifierSpec)
  discard parser.run(optionalSpace)
  let maybeFields = ? parser.run(optional(contained("variant_fields", "{",
    separatedBy(argumentDefinitionSpec, commaWithSpacesSpec), "}")))
  var fields: seq[ArgumentDefinition]
  if maybeFields.isSome: fields = maybeFields.get
  discard ? parser.run(strictLine)
  ok(newVariantDefinition(name, fields, name.loc))
)

let unionHeaderSpec = Spec[Location](
  name: "union_header",
  parseFn: proc(parser: Parser): Result[Location, ParserError] =
  let loc = ? parser.run(keywordSpec("union"))
  discard parser.run(optionalSpace)
  discard ? parser.run(punctuationSpec(":"))
  ok(loc)
)

let unionSpec = blockSpec("union", unionHeaderSpec,
  atLeastOne(variantDefinitionLineSpec),
  proc(h: Location, b: seq[VariantDefinition]): Union =
  newUnion(b, h))

let dataBlockSpec = oneOf("data_block", [
  structSpec.map("struct_data",
    proc(v: Struct): DataBlock = newDataBlock(v)),
  unionSpec.map("union_data",
    proc(v: Union): DataBlock = newDataBlock(v)),
])

# Module body: optional data block + function list
type ModuleBody = tuple[data: Option[DataBlock], funcList: FunctionList]

let moduleBodySpec = Spec[ModuleBody](
  name: "module_body",
  parseFn: proc(parser: Parser): Result[ModuleBody, ParserError] =
  let data = ? parser.run(optional(dataBlockSpec))
  let funcList = ? parser.run(functionListSpec)
  ok((data, funcList))
)

let moduleSpec = decoratedBlockSpec("module", moduleHeaderSpec, moduleBodySpec,
  proc(d: seq[Decorator], h: ModuleHeader, b: ModuleBody): Module =
  newModule(d, h.name, b.data, b.funcList, h.loc))

let fileItemSpec = oneOf("file_item", [
  moduleSpec.map("module_item",
    proc(v: Module): FileItem = newFileItem(v)),
  genericSpec.map("generic_item",
    proc(v: Generic): FileItem = newFileItem(v)),
])

# import { Name, Name } from "path"
# identifier ("as" identifier)?
let importNameSpec = Spec[ImportName](
  name: "import_name",
  parseFn: proc(parser: Parser): Result[ImportName, ParserError] =
  let name = ? parser.run(identifierSpec)
  let maybeAs = parser.run(strictSpace)
  if maybeAs.isErr:
    return ok(newImportName(name.name, "", name.loc))
  let maybeAsKeyword = parser.run(keywordSpec("as"))
  if maybeAsKeyword.isErr:
    return ok(newImportName(name.name, "", name.loc))
  discard ? parser.run(strictSpace)
  let alias = ? parser.run(identifierSpec)
  ok(newImportName(name.name, alias.name, name.loc))
)

let importLineSpec = Spec[Import](
  name: "import_line",
  parseFn: proc(parser: Parser): Result[Import, ParserError] =
  let loc = ? parser.run(keywordSpec("import"))
  discard ? parser.run(strictSpace)
  let names = ? parser.run(contained("import_names", "{",
    separatedBy(importNameSpec, commaWithSpacesSpec), "}"))
  discard ? parser.run(strictSpace)
  discard ? parser.run(keywordSpec("from"))
  discard ? parser.run(strictSpace)
  let source = ? parser.run(stringLiteralSpec)
  discard ? parser.run(strictLine)
  ok(newImport(names, source.value, loc))
)

let importBlockSpec = Spec[Import](
  name: "import_block",
  parseFn: proc(parser: Parser): Result[Import, ParserError] =
  discard parser.run(optionalLines)
  let imp = ? parser.run(importLineSpec)
  ok(imp)
)

let fileItemBlockSpec = Spec[FileItem](
  name: "file_item_block",
  parseFn: proc(parser: Parser): Result[FileItem, ParserError] =
  discard parser.run(optionalLines)
  let item = ? parser.run(fileItemSpec)
  ok(item)
)

# file: import* (module | generic)*
let fileSpec = Spec[File](
  name: "file",
  parseFn: proc(parser: Parser): Result[File, ParserError] =
  let imports = ? parser.run(any(importBlockSpec))
  let items = ? parser.run(any(fileItemBlockSpec))
  discard parser.run(optionalLines)
  if not parser.done():
    # Force a parse attempt to get a specific error message
    discard ? parser.run(fileItemSpec)
  ok(newFile(parser.filepath, imports, items))
)

proc parse(filepath: string, indentWidth: uint32, tokens: seq[Token]): Result[
    File, string] =
  let parser = newParser(filepath, indentWidth, tokens)
  let maybeFile = parser.run(fileSpec)
  if maybeFile.isErr:
    err(fmt"{filepath}:{maybeFile.error}")
  else:
    ok(maybeFile.get)

# ============================================================
# Recursive file resolution
# ============================================================

import os, unicode, tables, deques, sets
import utils

proc readFileSafe(filepath: string): Result[string, string] =
  const MaxFileByteSize = 1 * 1024 * 1024 # 1 MB
  try:
    let fileByteSize = getFileSize(filepath)
    if fileByteSize > MaxFileByteSize:
      err(fmt"{filepath} file exceeds 1 MB limit ({fileByteSize} bytes).")
    else:
      let source = readFile(filepath)
      let pos = validateUtf8(source)
      if pos == -1: ok(source)
      else: err(fmt"{filepath} invalid UTF-8 byte at position {pos}.")
  except IOError:
    err(fmt"{filepath} failed to read file.")

proc parseFile(filepath: string, indentWidth: uint32,
    dumpTokens: bool): Result[File, string] =
  let source = ? readFileSafe(filepath)
  let tokens = ? tokenize(source, filepath, dumpTokens)
  parse(filepath, indentWidth, tokens)

proc resolveImportPath(source: string, importingFile: string): Result[string, string] =
  ## Resolves an import path relative to the importing file.
  ## Rejects paths that escape to parent directories.
  if source.startsWith(".."):
    return err(fmt"{importingFile}: import path '{source}' escapes to parent directory — imports must be from adjacent files or subdirectories")
  let dir = importingFile.parentDir
  ok((dir / source).absolutePath)

proc parse*(rootPath: string, indentWidth: uint32, dumpTokens: bool): Result[
    seq[File], string] =
  ## BFS through imports, tokenize + parse each file.
  ## Returns files in topological order: leaves first, root last.
  var parsed: Table[string, File]
  var queued: HashSet[string]
  var queue: Deque[string]

  queue.addLast(rootPath)
  queued.incl(rootPath)

  while queue.len > 0:
    let current = queue.popFirst()
    let file = ? parseFile(current, indentWidth, dumpTokens)
    parsed[current] = file

    for imp in file.imports:
      let depPath = ? resolveImportPath(imp.source, current)
      if depPath notin queued:
        queue.addLast(depPath)
        queued.incl(depPath)

  # Topological sort with cycle detection (leaves first, root last)
  let getNeighbors = proc(path: string): seq[string] =
    if parsed.hasKey(path):
      for imp in parsed[path].imports:
        let depPath = resolveImportPath(imp.source, path)
        if depPath.isOk: result.add(depPath.get)
  let sortedPaths = ? topoSort(rootPath, getNeighbors)

  var files: seq[File]
  for path in sortedPaths:
    files.add(parsed[path])
  ok(files)
