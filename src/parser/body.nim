import strformat, strutils, options, tables, results

import tokenizer
import combinators
import helpers
import identifiers
import literals
import argtypes
import patterns

# ============================================================
# Getter
# ============================================================

type Getter* = ref object
  source: Identifier
  property: Identifier
  loc: Location

proc newGetter*(source: Identifier, property: Identifier,
    loc: Location): Getter =
  Getter(source: source, property: property, loc: loc)

proc source*(g: Getter): Identifier = g.source
proc property*(g: Getter): Identifier = g.property
proc loc*(g: Getter): Location = g.loc

proc asl(getter: Getter): string =
  fmt"{asl(getter.source)}.{asl(getter.property)}"

let getterSpec* = Spec[Getter](
  name: "getter",
  parseFn: proc(parser: Parser): Result[Getter, ParserError] =
  let source = ? parser.run(identifierSpec)
  discard ? parser.run(punctuationSpec("."))
  let property = ? parser.run(identifierSpec)
  ok(newGetter(source, property, source.loc))
)

# ============================================================
# LiteralInitializer
# ============================================================

type LiteralInitializer* = ref object
  argType: ArgumentType
  value: Literal
  loc: Location

proc newLiteralInitializer*(argType: ArgumentType, value: Literal, loc: Location): LiteralInitializer =
  LiteralInitializer(argType: argType, value: value, loc: loc)

proc loc*(literalInit: LiteralInitializer): Location = literalInit.loc
proc argType*(literalInit: LiteralInitializer): ArgumentType = literalInit.argType
proc value*(literalInit: LiteralInitializer): Literal = literalInit.value

proc asl(prim: LiteralInitializer): string =
  fmt"{asl(prim.argType)} {asl(prim.value)}"

# type literal
let literalInitializerSpec* = Spec[LiteralInitializer](
  name: "literal_initializer",
  parseFn: proc(parser: Parser): Result[LiteralInitializer, ParserError] =
  let argType = ? parser.run(argumentTypeSpec)
  discard ? parser.run(atLeastOne(spaceSpec))
  let value = ? parser.run(literalSpec)
  ok(newLiteralInitializer(argType, value, argType.loc))
)



# ----------------- StructRef -----------------
# One shape: the receiver module identifier plus a (possibly empty)
# impls list. Empty impls === the user wrote `Module { ... }`; non-empty
# impls === the user wrote `Module[Impl, ...] { ... }`. The parser no
# longer discriminates between the two surface forms — downstream layers
# initialise their GenericImplMap from the impls seq directly (empty
# seq → empty map, non-empty → pre-populated).
type StructRef* = ref object
  module: Identifier
  impls: seq[ArgumentType]
  loc: Location

proc newStructRef*(module: Identifier, impls: seq[ArgumentType],
    loc: Location): StructRef =
  StructRef(module: module, impls: impls, loc: loc)

proc module*(s: StructRef): Identifier = s.module
proc impls*(s: StructRef): seq[ArgumentType] = s.impls
proc loc*(s: StructRef): Location = s.loc
proc asl*(s: StructRef): string =
  if s.impls.len == 0:
    asl(s.module)
  else:
    var implStrs: seq[string]
    for impl in s.impls:
      implStrs.add(asl(impl))
    fmt"{asl(s.module)}[{implStrs.join("", "")}]"

# ----------------- UnionRef -----------------
# Mirror of StructRef: same one-shape module+impls layout.
type UnionRef* = ref object
  module: Identifier
  impls: seq[ArgumentType]
  loc: Location

proc newUnionRef*(module: Identifier, impls: seq[ArgumentType],
    loc: Location): UnionRef =
  UnionRef(module: module, impls: impls, loc: loc)

proc module*(u: UnionRef): Identifier = u.module
proc impls*(u: UnionRef): seq[ArgumentType] = u.impls
proc loc*(u: UnionRef): Location = u.loc
proc asl*(u: UnionRef): string =
  if u.impls.len == 0:
    asl(u.module)
  else:
    var implStrs: seq[string]
    for impl in u.impls:
      implStrs.add(asl(impl))
    fmt"{asl(u.module)}[{implStrs.join("", "")}]"


# ============================================================
# Body cluster (mutually recursive)
# ============================================================

type
  ArgumentList* = ref object
    args: seq[Expression]
    loc: Location

  FunctionCall* = ref object
    root: Identifier
    name: Identifier
    argList: ArgumentList

  KeywordArgument* = ref object
    name: Identifier
    expression: Expression
    loc: Location

  KeywordArgumentList* = ref object
    args: seq[KeywordArgument]
    loc: Location

  StructInitializer* = ref object
    structRef: StructRef
    kwargList: KeywordArgumentList
    loc: Location

  UnionInitializer* = ref object
    unionRef: UnionRef
    variantName: Identifier
    kwargList: KeywordArgumentList
    loc: Location

  InitializerKind* = enum
    ikLiteral, ikStruct, ikUnion
  Initializer* = ref object
    case kind: InitializerKind
    of ikLiteral: literal: LiteralInitializer
    of ikStruct: struct: StructInitializer
    of ikUnion: union: UnionInitializer

  Assignment* = ref object
    target: Identifier
    expression: Expression
    loc: Location

  Setter* = ref object
    target: Getter
    expression: Expression
    loc: Location

  CaseBlock* = ref object
    pattern: CasePattern
    body: StatementList
    loc: Location

  MatchExpression* = ref object
    subject: Expression
    cases: seq[CaseBlock]
    loc: Location

  ExpressionKind* = enum
    ekLiteral, ekFnCall, ekGetter, ekInitializer, ekVariable, ekMatch
  Expression* = ref object
    case kind: ExpressionKind
    of ekLiteral: literal: Literal
    of ekFnCall: fncall: FunctionCall
    of ekGetter: getter: Getter
    of ekInitializer: initializer: Initializer
    of ekVariable: variable: Identifier
    of ekMatch: match: MatchExpression

  StatementKind* = enum
    skAssignment, skExpr, skSetter
  Statement* = ref object
    case kind: StatementKind
    of skAssignment: assignment: Assignment
    of skExpr: expression: Expression
    of skSetter: setter: Setter

  StatementList* = ref object
    statements: seq[Statement]

# Forward declarations for mutually-recursive asl procs.
proc asl(expr: Expression): string
proc asl*(stmt: Statement): string
proc aslBlock*(stmt: Statement, indentWidth: uint32): seq[string]

# ----------------- ArgumentList -----------------
proc newArgumentList*(args: seq[Expression], loc: Location): ArgumentList =
  ArgumentList(args: args, loc: loc)

proc asl(argList: ArgumentList): string =
  result = "("
  for i, arg in argList.args:
    if i > 0: result.add(", ")
    result.add(asl(arg))
  result.add(")")

# ----------------- FunctionCall -----------------
proc newFunctionCall*(root: Identifier, name: Identifier,
    argList: ArgumentList): FunctionCall =
  FunctionCall(root: root, name: name, argList: argList)

proc loc*(fncall: FunctionCall): Location = fncall.root.loc

proc root*(fncall: FunctionCall): Identifier = fncall.root
proc name*(fncall: FunctionCall): Identifier = fncall.name
proc args*(fncall: FunctionCall): seq[Expression] = fncall.argList.args

proc asl(fncall: FunctionCall): string =
  fmt"{asl(fncall.root)}.{asl(fncall.name)}{asl(fncall.argList)}"

# ----------------- KeywordArgument -----------------
proc newKeywordArgument*(name: Identifier, expression: Expression,
    loc: Location): KeywordArgument =
  KeywordArgument(name: name, expression: expression, loc: loc)

proc name*(kwarg: KeywordArgument): Identifier = kwarg.name
proc expression*(kwarg: KeywordArgument): Expression = kwarg.expression
proc loc*(kwarg: KeywordArgument): Location = kwarg.loc

proc asl(kwarg: KeywordArgument): string =
  fmt"{asl(kwarg.name)}: {asl(kwarg.expression)}"

# ----------------- KeywordArgumentList -----------------
proc newKeywordArgumentList*(args: seq[KeywordArgument], loc: Location): Result[KeywordArgumentList, ParserError] =
  if args.len == 0:
    let msg = "keyword argument list must contain at least 1 field"
    return err(newParserError(msg, loc))

  var argIndex: Table[Identifier, int]
  for index, arg in args:
    if arg.name in argIndex:
      let prev = args[argIndex[arg.name]]
      let msg = fmt"duplicate field encountered, see previous assignment at {prev.loc}"
      return err(newParserError(msg, arg.loc))
    argIndex[arg.name] = index
  ok(KeywordArgumentList(args: args, loc: loc))

proc asl(kwargList: KeywordArgumentList): string =
  result = "{ "
  for i, arg in kwargList.args:
    if i > 0: result.add(", ")
    result.add(asl(arg))
  result.add(" }")

# ----------------- StructInitializer -----------------
proc newStructInitializer*(structRef: StructRef, kwargList: KeywordArgumentList, loc: Location): StructInitializer =
  StructInitializer(structRef: structRef, kwargList: kwargList, loc: loc)

proc structRef*(struct: StructInitializer): StructRef = struct.structRef
proc kwargs*(struct: StructInitializer): seq[KeywordArgument] = struct.kwargList.args
proc loc*(struct: StructInitializer): Location = struct.loc

proc asl(nonPrim: StructInitializer): string =
  fmt"{asl(nonPrim.structRef)} {asl(nonPrim.kwargList)}"

# ----------------- UnionInitializer -----------------
proc newUnionInitializer*(unionRef: UnionRef, variantName: Identifier,
    kwargList: KeywordArgumentList, loc: Location): UnionInitializer =
  UnionInitializer(unionRef: unionRef, variantName: variantName,
    kwargList: kwargList, loc: loc)

proc loc*(unionInit: UnionInitializer): Location = unionInit.loc
proc unionRef*(unionInit: UnionInitializer): UnionRef = unionInit.unionRef
proc variant*(unionInit: UnionInitializer): Identifier = unionInit.variantName
proc kwargs*(unionInit: UnionInitializer): seq[KeywordArgument] = unionInit.kwargList.args

proc asl(unionInit: UnionInitializer): string =
  fmt"{asl(unionInit.unionRef)}.{asl(unionInit.variantName)} {asl(unionInit.kwargList)}"

# ----------------- Initializer -----------------
proc newInitializer*(literal: LiteralInitializer): Initializer =
  Initializer(kind: ikLiteral, literal: literal)

proc newInitializer*(struct: StructInitializer): Initializer =
  Initializer(kind: ikStruct, struct: struct)

proc newInitializer*(union: UnionInitializer): Initializer =
  Initializer(kind: ikUnion, union: union)

proc kind*(i: Initializer): InitializerKind = i.kind

proc literal*(i: Initializer): LiteralInitializer =
  assert i.kind == ikLiteral,
    fmt"Initializer.literal accessed but kind is {i.kind}"
  i.literal

proc struct*(i: Initializer): StructInitializer =
  assert i.kind == ikStruct,
    fmt"Initializer.struct accessed but kind is {i.kind}"
  i.struct

proc union*(i: Initializer): UnionInitializer =
  assert i.kind == ikUnion,
    fmt"Initializer.union accessed but kind is {i.kind}"
  i.union

proc loc*(initializer: Initializer): Location =
  case initializer.kind:
  of ikLiteral: initializer.literal.loc
  of ikStruct: initializer.struct.loc
  of ikUnion: initializer.union.loc

proc asl(initializer: Initializer): string =
  case initializer.kind:
  of ikLiteral: asl(initializer.literal)
  of ikStruct: asl(initializer.struct)
  of ikUnion: asl(initializer.union)

# ----------------- Assignment -----------------
proc newAssignment*(target: Identifier, expression: Expression,
    loc: Location): Assignment =
  Assignment(target: target, expression: expression, loc: loc)

proc loc*(assignment: Assignment): Location = assignment.target.loc
proc target*(assignment: Assignment): Identifier = assignment.target
proc expression*(assignment: Assignment): Expression = assignment.expression

proc asl(assignment: Assignment): string =
  fmt"{asl(assignment.target)} = {asl(assignment.expression)}"

# ----------------- Setter -----------------
proc newSetter*(target: Getter, expression: Expression,
    loc: Location): Setter =
  Setter(target: target, expression: expression, loc: loc)

proc target*(setter: Setter): Getter = setter.target
proc expression*(setter: Setter): Expression = setter.expression
proc loc*(setter: Setter): Location = setter.loc

proc asl(setter: Setter): string =
  fmt"{asl(setter.target)} = {asl(setter.expression)}"

# ----------------- CaseBlock -----------------
proc newCaseBlock*(pattern: CasePattern, body: StatementList,
    loc: Location): CaseBlock =
  CaseBlock(pattern: pattern, body: body, loc: loc)

proc pattern*(caseBlock: CaseBlock): CasePattern = caseBlock.pattern
proc statements*(caseBlock: CaseBlock): seq[Statement] = caseBlock.body.statements
proc loc*(caseBlock: CaseBlock): Location = caseBlock.loc

proc asl(caseBlock: CaseBlock, indentWidth: uint32): seq[string] =
  result.add(fmt"case {asl(caseBlock.pattern)}:")
  let indent = " ".repeat(indentWidth)
  for s in caseBlock.body.statements:
    for line in aslBlock(s, indentWidth):
      result.add(fmt"{indent}{line}")

# ----------------- MatchExpression -----------------
proc newMatchExpression*(subject: Expression, cases: seq[CaseBlock],
    loc: Location): MatchExpression =
  # TODO: case pattern can be either integer or variable (with at max 1 variable pattern that too last)
  # TODO: for integer case pattern all integer values must be unique
  # TODO: case pattern can be either variant or variable (with at max 1 variable pattern that too last)
  # TODO: for integer case pattern all variants must be unique
  MatchExpression(subject: subject, cases: cases, loc: loc)

proc subject*(match: MatchExpression): Expression = match.subject
proc cases*(match: MatchExpression): seq[CaseBlock] = match.cases
proc loc*(match: MatchExpression): Location = match.loc

proc asl(matchExpr: MatchExpression, indentWidth: uint32): seq[string] =
  result.add(fmt"match {asl(matchExpr.subject)}:")
  let indent = " ".repeat(indentWidth)
  for cb in matchExpr.cases:
    for line in asl(cb, indentWidth):
      result.add(fmt"{indent}{line}")

# ----------------- Expression -----------------
proc newExpression*(literal: Literal): Expression =
  Expression(kind: ekLiteral, literal: literal)

proc newExpression*(fncall: FunctionCall): Expression =
  Expression(kind: ekFnCall, fncall: fncall)

proc newExpression*(getter: Getter): Expression =
  Expression(kind: ekGetter, getter: getter)

proc newExpression*(initializer: Initializer): Expression =
  Expression(kind: ekInitializer, initializer: initializer)

proc newExpression*(variable: Identifier): Expression =
  Expression(kind: ekVariable, variable: variable)

proc newExpression*(match: MatchExpression): Expression =
  Expression(kind: ekMatch, match: match)

proc kind*(e: Expression): ExpressionKind = e.kind

proc literal*(e: Expression): Literal =
  assert e.kind == ekLiteral,
    fmt"Expression.literal accessed but kind is {e.kind}"
  e.literal

proc fncall*(e: Expression): FunctionCall =
  assert e.kind == ekFnCall,
    fmt"Expression.fncall accessed but kind is {e.kind}"
  e.fncall

proc getter*(e: Expression): Getter =
  assert e.kind == ekGetter,
    fmt"Expression.getter accessed but kind is {e.kind}"
  e.getter

proc initializer*(e: Expression): Initializer =
  assert e.kind == ekInitializer,
    fmt"Expression.initializer accessed but kind is {e.kind}"
  e.initializer

proc variable*(e: Expression): Identifier =
  assert e.kind == ekVariable,
    fmt"Expression.variable accessed but kind is {e.kind}"
  e.variable

proc match*(e: Expression): MatchExpression =
  assert e.kind == ekMatch,
    fmt"Expression.match accessed but kind is {e.kind}"
  e.match

proc loc*(expression: Expression): Location =
  case expression.kind:
  of ekFnCall: expression.fncall.loc
  of ekGetter: expression.getter.loc
  of ekInitializer: expression.initializer.loc
  of ekLiteral: expression.literal.loc
  of ekMatch: expression.match.loc
  of ekVariable: expression.variable.loc

proc asl(expr: Expression): string =
  case expr.kind:
  of ekLiteral: asl(expr.literal)
  of ekFnCall: asl(expr.fncall)
  of ekGetter: asl(expr.getter)
  of ekInitializer: asl(expr.initializer)
  of ekVariable: asl(expr.variable)
  of ekMatch: "" # match is a block expression, use aslBlock

# ----------------- Statement -----------------
proc newStatement*(assignment: Assignment): Statement =
  Statement(kind: skAssignment, assignment: assignment)

proc newStatement*(expression: Expression): Statement =
  Statement(kind: skExpr, expression: expression)

proc newStatement*(setter: Setter): Statement =
  Statement(kind: skSetter, setter: setter)

proc kind*(s: Statement): StatementKind = s.kind

proc assignment*(s: Statement): Assignment =
  assert s.kind == skAssignment,
    fmt"Statement.assignment accessed but kind is {s.kind}"
  s.assignment

proc expression*(s: Statement): Expression =
  assert s.kind == skExpr,
    fmt"Statement.expression accessed but kind is {s.kind}"
  s.expression

proc setter*(s: Statement): Setter =
  assert s.kind == skSetter,
    fmt"Statement.setter accessed but kind is {s.kind}"
  s.setter

proc loc*(statement: Statement): Location =
  case statement.kind:
  of skAssignment: statement.assignment.loc
  of skExpr: statement.expression.loc
  of skSetter: statement.setter.loc

proc isBlockStatement(stmt: Statement): bool =
  case stmt.kind:
  of skExpr: stmt.expression.kind == ekMatch
  of skAssignment:
    stmt.assignment.expression.kind == ekMatch
  of skSetter: false

proc asl*(stmt: Statement): string =
  case stmt.kind:
  of skAssignment: asl(stmt.assignment)
  of skSetter: asl(stmt.setter)
  of skExpr: asl(stmt.expression)

proc aslBlock*(stmt: Statement, indentWidth: uint32): seq[string] =
  if not stmt.isBlockStatement:
    return @[asl(stmt)]
  case stmt.kind:
  of skExpr:
    result = asl(stmt.expression.match, indentWidth)
  of skAssignment:
    let matchLines = asl(stmt.assignment.expression.match, indentWidth)
    result.add(fmt"{asl(stmt.assignment.target)} = {matchLines[0]}")
    for i in 1..<matchLines.len:
      result.add(matchLines[i])
  of skSetter:
    result = @[asl(stmt.setter)]

# ----------------- StatementList -----------------
proc newStatementList*(statements: seq[Statement]): StatementList =
  StatementList(statements: statements)

proc statements*(sl: StatementList): seq[Statement] = sl.statements

# ============================================================
# Specs for the body cluster
# ============================================================

# Forward-declared because expressions appear inside argument lists
# of function calls, creating a mutual recursion:
# expression -> functionCall -> argumentList -> expression
let expressionSpec* = newSpec[Expression]("expression")

# Forward declare statementListSpec for mutual recursion:
# match -> caseBlock -> statementList -> statementLine -> statement -> match
let statementListSpec* = newSpec[StatementList]("statement_list")

let argumentListSpec* = Spec[ArgumentList](
  name: "argument_list",
  parseFn: proc(parser: Parser): Result[ArgumentList, ParserError] =
  let loc = parser.loc
  let args = ? parser.run(contained("argument_list", "(",
    separatedBy(expressionSpec, commaWithSpacesSpec), ")"))
  ok(newArgumentList(args, loc))
)

let functionCallSpec* = Spec[FunctionCall](
  name: "function_call",
  parseFn: proc(parser: Parser): Result[FunctionCall, ParserError] =
  let root = ? parser.run(identifierSpec)
  discard ? parser.run(punctuationSpec("."))
  let funcNameIdent = ? parser.run(identifierSpec)
  discard parser.run(any(spaceSpec))
  let argList = ? parser.run(argumentListSpec)
  ok(newFunctionCall(root, funcNameIdent, argList))
)

let kwargSpec* = Spec[KeywordArgument](
  name: "keyword_argument",
  parseFn: proc(parser: Parser): Result[KeywordArgument, ParserError] =
  let name = ? parser.run(identifierSpec)
  discard ? parser.run(colonWithSpacesSpec)
  let expression = ? parser.run(expressionSpec)
  ok(newKeywordArgument(name, expression, name.loc))
)

let kwargListSpec* = Spec[KeywordArgumentList](
  name: "keyword_argument_list",
  parseFn: proc(parser: Parser): Result[KeywordArgumentList, ParserError] =
  let loc = parser.loc
  let args = ? parser.run(contained("keyword_argument_list", "{",
    separatedBy(kwargSpec, commaWithSpacesSpec), "}"))
  newKeywordArgumentList(args, loc)
)

# Type.Variant { fields } (bare — drives leave-as-is inference) or
# Type[Impls].Variant { fields } (explicit-impls — escape hatch when
# leave-as-is can't produce a fully-bound type). Both productions land
# on the same UnionRef shape carrying an impls seq; empty means bare.
let unionInitializerSpec* = Spec[UnionInitializer](
  name: "union_initializer",
  parseFn: proc(parser: Parser): Result[UnionInitializer, ParserError] =
  let argType = ? parser.run(argumentTypeSpec)
  discard ? parser.run(punctuationSpec("."))
  let variantName = ? parser.run(identifierSpec)
  discard parser.run(any(spaceSpec))
  let kwargList = ? parser.run(kwargListSpec)
  let unionRef = newUnionRef(argType.root, argType.impls, argType.loc)
  ok(newUnionInitializer(unionRef, variantName, kwargList, argType.loc))
)

# Either `Type { fields }` (bare) or `Type[Impls] { fields }` (explicit
# impls, used for phantom-typed structs whose module declares a requires
# block). Both productions land on the same StructRef shape carrying an
# impls seq; empty means bare.
let structInitializerSpec* = Spec[StructInitializer](
  name: "struct_initializer",
  parseFn: proc(parser: Parser): Result[StructInitializer, ParserError] =
  let argType = ? parser.run(argumentTypeSpec)
  discard parser.run(any(spaceSpec))
  let kwargList = ? parser.run(kwargListSpec)
  let structRef = newStructRef(argType.root, argType.impls, argType.loc)
  ok(newStructInitializer(structRef, kwargList, argType.loc))
)

let initializerSpec* = oneOf("initializer", [
  unionInitializerSpec.map("union",
    proc(v: UnionInitializer): Initializer = newInitializer(v)),
  structInitializerSpec.map("struct",
    proc(v: StructInitializer): Initializer = newInitializer(v)),
  literalInitializerSpec.map("literal",
    proc(v: LiteralInitializer): Initializer = newInitializer(v)),
])

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

let assignmentSpec* = Spec[Assignment](
  name: "assignment",
  parseFn: proc(parser: Parser): Result[Assignment, ParserError] =
  let targetIdent = ? parser.run(identifierSpec)
  discard ? parser.run(equalsSeparatorSpec)
  let expression = ? parser.run(expressionSpec)
  ok(newAssignment(targetIdent, expression, targetIdent.loc))
)

let setterSpec* = Spec[Setter](
  name: "setter",
  parseFn: proc(parser: Parser): Result[Setter, ParserError] =
  let getter = ? parser.run(getterSpec)
  discard ? parser.run(equalsSeparatorSpec)
  let expression = ? parser.run(expressionSpec)
  ok(newSetter(getter, expression, getter.loc))
)

let inlineStatementSpec* = oneOf("inline_statement", [
  setterSpec.map("mutation_statement",
    proc(v: Setter): Statement = newStatement(v)),
  assignmentSpec.map("assignment_statement",
    proc(v: Assignment): Statement = newStatement(v)),
  expressionSpec.map("expression_statement",
    proc(v: Expression): Statement = newStatement(v)),
])

let caseHeaderSpec = Spec[CasePattern](
  name: "case_header",
  parseFn: proc(parser: Parser): Result[CasePattern, ParserError] =
  discard ? parser.run(keywordSpec("case"))
  discard ? parser.run(atLeastOne(spaceSpec))
  let pattern = ? parser.run(casePatternSpec)
  discard parser.run(any(spaceSpec))
  discard ? parser.run(punctuationSpec(":"))
  ok(pattern)
)

let caseBlockSpec* = blockSpec("case", caseHeaderSpec, statementListSpec,
  proc(h: CasePattern, b: StatementList): CaseBlock =
  newCaseBlock(h, b, h.loc))

# Match body: parses "match" keyword + subject + ":" + newline + caseBlocks
# Does NOT consume indentation — caller handles that
let matchBodySpec* = Spec[MatchExpression](
  name: "match_body",
  parseFn: proc(parser: Parser): Result[MatchExpression, ParserError] =
  let loc = ? parser.run(keywordSpec("match"))
  discard ? parser.run(atLeastOne(spaceSpec))
  # Match expressions cannot be the subject of another match expression.
  # expressionSpec intentionally excludes match (match is parsed separately
  # in statementLineSpec). This check guards against future changes that
  # might add match to expressionSpec.
  let subject = ? parser.run(expressionSpec)
  case subject.kind:
  of ekMatch:
    return err(newParserError(
      "match expression cannot be the subject of another match", loc))
  of ekLiteral, ekFnCall, ekGetter, ekInitializer, ekVariable: discard
  discard parser.run(any(spaceSpec))
  discard ? parser.run(punctuationSpec(":"))
  discard ? parser.run(ignorableLineSpec)
  parser.level += 1
  let casesBody = atLeastOne(Spec[CaseBlock](
    name: "case_block_line",
    parseFn: proc(parser: Parser): Result[CaseBlock, ParserError] =
    discard parser.run(any(ignorableLineSpec))
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

let statementLineSpec* = Spec[Statement](
  name: "statement_line",
  parseFn: proc(parser: Parser): Result[Statement, ParserError] =
  discard parser.run(any(ignorableLineSpec))
  discard ? parser.run(indentationSpec)
  # Try match assignment: identifier = match ...:
  let maybeMatchAssign = parser.run(Spec[Statement](
    name: "match_assignment",
    parseFn: proc(parser: Parser): Result[Statement, ParserError] =
    let target = ? parser.run(identifierSpec)
    discard ? parser.run(equalsSeparatorSpec)
    let matchExpr = ? parser.run(matchBodySpec)
    ok(newStatement(newAssignment(target, newExpression(matchExpr), target.loc)))
  ))
  if maybeMatchAssign.isOk: return ok(maybeMatchAssign.get)
  # Try standalone match: match ...:
  let maybeMatch = parser.run(matchBodySpec)
  if maybeMatch.isOk:
    return ok(newStatement(newExpression(maybeMatch.get)))
  # Inline statements: statement + newline
  let statement = ? parser.run(inlineStatementSpec)
  discard ? parser.run(ignorableLineSpec)
  ok(statement)
)

statementListSpec.parseFn = atLeastOne(statementLineSpec).map("statement_list",
  proc(stmts: seq[Statement]): StatementList = newStatementList(stmts)).parseFn
