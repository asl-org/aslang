import strformat, strutils, sequtils, tables, results, options

import parser

import identifiers
import literals
import scalars
import refs

# Getter and the case-pattern grammar were extracted to their own files
# (they are non-recursive leaves of the body cluster); re-exported so
# `import statement` still surfaces them.
import getter
import pattern

type
  ArgumentList* = ref object
    args: seq[InlineExpression]
    loc: Location

  FunctionCallKind* = enum
    fckDefault, fckTry
  FunctionCall* = ref object
    root: Identifier
    name: Identifier
    argList: ArgumentList
    case kind: FunctionCallKind
    of fckDefault: discard
    of fckTry: tryLoc: Location

  KeywordArgument* = ref object
    name: Identifier
    expression: InlineExpression
    loc: Location

  KeywordArgumentList* = ref object
    args: seq[KeywordArgument]
    loc: Location

  StructInitializer* = ref object
    structRef: StructRef
    kwargList: KeywordArgumentList

  UnionInitializer* = ref object
    unionRef: UnionRef
    kwargList: KeywordArgumentList

  InitializerKind* = enum
    ikLiteral, ikStruct, ikUnion
  Initializer* = ref object
    case kind: InitializerKind
    of ikLiteral: literal: LiteralInitializer
    of ikStruct: struct: StructInitializer
    of ikUnion: union: UnionInitializer

  InlineExpressionKind* = enum
    iekLiteral, iekFnCall, iekGetter, iekInitializer, iekVariable
  InlineExpression* = ref object
    case kind: InlineExpressionKind
    of iekLiteral: literal: Literal
    of iekFnCall: fncall: FunctionCall
    of iekGetter: getter: Getter
    of iekInitializer: initializer: Initializer
    of iekVariable: variable: Identifier

# ============================================================
# Body cluster — mutually recursive
# ============================================================
#
# Expression → FunctionCall → ArgumentList → Expression, and
# Match → CaseBlock → StatementList → Statement → Match.
# Forward-declared `var` specs (inlineExpressionSpec, statementListSpec)
# resolve the cycle; each is assigned once its dependencies exist.

# Forward declarations for mutually-recursive asl procs.
proc newInlineExpression*(variable: Identifier): InlineExpression
proc asl(expression: InlineExpression): string

# `inlineExpressionSpec` is a named Spec because argumentListSpec references it
# directly via `inlineExpressionSpec.parenthesisList()` (and the body cluster
# recurses back through it).
var inlineExpressionSpec*: Spec[InlineExpression]

# ----------------- ArgumentList -----------------
proc newArgumentList*(args: seq[InlineExpression], loc: Location): ArgumentList =
  ArgumentList(args: args, loc: loc)

proc arity(argList: ArgumentList): int = argList.args.len
proc loc*(argList: ArgumentList): Location = argList.loc

proc asl(argList: ArgumentList): string =
  var content: string
  let inner = argList.args.mapIt(asl(it)).join(", ")
  content.add(fmt"({inner})")
  content

proc argumentListConsumer(parser: Parser): Result[ArgumentList, ParserError] =
  let (args, loc) = ? parser.expect(inlineExpressionSpec.parenthesisList())
  ok(newArgumentList(args, loc))
let argumentListSpec* = newSpec("argument list", argumentListConsumer)

# ----------------- FunctionCall -----------------
proc newFunctionCall*(root: Identifier, name: Identifier, argList: ArgumentList): FunctionCall =
  FunctionCall(kind: fckDefault, root: root, name: name, argList: argList)

proc newFunctionCall*(tryLoc: Location, fncall: FunctionCall): FunctionCall =
  FunctionCall(kind: fckTry, tryLoc: tryLoc, root: fncall.root, name: fncall.name, argList: fncall.argList)

proc loc*(fncall: FunctionCall): Location =
  case fncall.kind:
  of fckDefault: fncall.root.loc
  of fckTry: fncall.tryLoc

proc kind*(fncall: FunctionCall): FunctionCallKind = fncall.kind
proc root*(fncall: FunctionCall): Identifier = fncall.root
proc name*(fncall: FunctionCall): Identifier = fncall.name
proc argList*(fncall: FunctionCall): ArgumentList = fncall.argList
proc args*(fncall: FunctionCall): seq[InlineExpression] = fncall.argList.args
proc arity*(fncall: FunctionCall): int = fncall.argList.arity

proc asl(fncall: FunctionCall): string =
  let default = fmt"{asl(fncall.root)}.{asl(fncall.name)}{asl(fncall.argList)}"
  case fncall.kind:
  of fckDefault: default
  of fckTry: fmt"try {default}"

proc defaultFunctionCallConsumer(parser: Parser): Result[FunctionCall, ParserError] =
  let target = ? parser.expect(identifierSpec)
  discard ? parser.expect(".")
  let function = ? parser.expect(identifierSpec)
  discard ? parser.expect(SPACE.optional())
  let args = ? parser.expect(argumentListSpec)
  ok(newFunctionCall(target, function, args))

let defaultFunctionCallSpec* = newSpec[FunctionCall]("default function call", defaultFunctionCallConsumer)

proc tryFunctionCallConsumer(parser: Parser): Result[FunctionCall, ParserError] =
  let tryKeyword = ? parser.expect("try")
  discard ? parser.expect(SPACE)
  let fncall = ? parser.expect(defaultFunctionCallSpec)
  ok(newFunctionCall(tryKeyword.loc, fncall))

let tryFunctionCallSpec = newSpec[FunctionCall]("try function call", tryFunctionCallConsumer)

let fncallSpec* = oneOf("function call", @[
  defaultFunctionCallSpec,
  tryFunctionCallSpec,
])

# ----------------- KeywordArgument -----------------
proc newKeywordArgument*(name: Identifier, expression: InlineExpression,
    loc: Location): KeywordArgument =
  KeywordArgument(name: name, expression: expression, loc: loc)

proc newKeywordArgument*(name: Identifier): KeywordArgument =
  newKeywordArgument(name, newInlineExpression(name), name.loc)

proc name*(kwarg: KeywordArgument): Identifier = kwarg.name
proc expression*(kwarg: KeywordArgument): InlineExpression = kwarg.expression
proc loc*(kwarg: KeywordArgument): Location = kwarg.loc

proc asl(kwarg: KeywordArgument): string =
  fmt"{asl(kwarg.name)}: {asl(kwarg.expression)}"

proc validateKeyNameConflict(args: seq[KeywordArgument]): Result[void, ParserError] =
  var argIndex: Table[Identifier, int]
  for index, arg in args:
    if arg.name in argIndex:
      let prev = args[argIndex[arg.name]]
      let msg = fmt"duplicate field encountered, see previous assignment at {prev.loc}"
      return err(newParserError(msg, arg.loc))
    argIndex[arg.name] = index
  ok()


proc explicitKwargConsumer(parser: Parser): Result[KeywordArgument, ParserError] =
  let name = ? parser.expect(identifierSpec)
  discard ? parser.expect(SPACE.optional())
  discard ? parser.expect(":")
  discard ? parser.expect(SPACE.optional())
  let expression = ? parser.expect(inlineExpressionSpec)
  ok(newKeywordArgument(name, expression, name.loc))

let explicitKwargSpec = newSpec("explicit keyword argument", explicitKwargConsumer)
let implicitKwargSpec = identifierSpec.map(newKeywordArgument)

let kwargSpec* = oneOf("keyword_argument", @[
  explicitKwargSpec,
  implicitKwargSpec,
])

# ----------------- KeywordArgumentList -----------------
proc newKeywordArgumentList*(args: seq[KeywordArgument], loc: Location): Result[KeywordArgumentList, ParserError] =
  ## `KeywordArgumentList` carries the raw kwarg sequence + a duplicate
  ## check. Emptiness is a per-initializer concern, not a list-level
  ## one: `StructInitializer`'s "no empty structs" rule falls out of
  ## `newStructDef` (≥ 1 field guaranteed) combined with the resolver's
  ## `kwargs.len != fields.len` count check; `UnionInitializer` needs
  ## empty to be legal so `Variant {}` on a zero-field variant works.
  ? validateKeyNameConflict(args)
  ok(KeywordArgumentList(args: args, loc: loc))

proc newKeywordArgumentList*(items: (seq[KeywordArgument], Location)): Result[KeywordArgumentList, ParserError] =
  newKeywordArgumentList(items[0], items[1])

proc newGeneratedKeywordArgumentList*(args: seq[KeywordArgument], loc: Location): KeywordArgumentList =
  let maybeSuccess = validateKeyNameConflict(args)
  assert(maybeSuccess.isOk, $(maybeSuccess.error))
  KeywordArgumentList(args: args, loc: loc)

proc items*(kwargList: KeywordArgumentList): seq[KeywordArgument] = kwargList.args
proc loc*(kwargList: KeywordArgumentList): Location = kwargList.loc

proc asl(kwargList: KeywordArgumentList): string =
  var content: string
  let inner = kwargList.items.mapIt(asl(it)).join(", ")
  content.add(fmt"{{ {inner} }}")
  content

let kwargListSpec* = kwargSpec.curlyBracketList().map(newKeywordArgumentList)

# ----------------- StructInitializer -----------------
proc newStructInitializer*(structRef: StructRef, kwargList: KeywordArgumentList): StructInitializer =
  StructInitializer(structRef: structRef, kwargList: kwargList)

proc structRef*(struct: StructInitializer): StructRef = struct.structRef
proc kwargs*(struct: StructInitializer): seq[KeywordArgument] = struct.kwargList.args
proc kwargList*(struct: StructInitializer): KeywordArgumentList = struct.kwargList
proc loc*(struct: StructInitializer): Location = struct.structRef.loc

proc asl(nonPrim: StructInitializer): string =
  fmt"{asl(nonPrim.structRef)} {asl(nonPrim.kwargList)}"

proc structInitializerConsumer(parser: Parser): Result[StructInitializer, ParserError] =
  let structRef = ? parser.expect(structRefSpec)
  discard ? parser.expect(SPACE.optional())
  let fields = ? parser.expect(kwargListSpec)
  ok(newStructInitializer(structRef, fields))

let structInitSpec* = newSpec[StructInitializer]("struct initializer", structInitializerConsumer)

# ----------------- UnionInitializer -----------------
proc newUnionInitializer*(unionRef: UnionRef, kwargList: KeywordArgumentList): UnionInitializer =
  UnionInitializer(unionRef: unionRef, kwargList: kwargList)

proc loc*(unionInit: UnionInitializer): Location = unionInit.unionRef.loc
proc variant*(unionInit: UnionInitializer): Identifier = unionInit.unionRef.variant
proc unionRef*(unionInit: UnionInitializer): UnionRef = unionInit.unionRef
proc kwargList*(unionInit: UnionInitializer): KeywordArgumentList = unionInit.kwargList
proc kwargs*(unionInit: UnionInitializer): seq[KeywordArgument] = unionInit.kwargList.args

proc asl(unionInit: UnionInitializer): string =
  fmt"{asl(unionInit.unionRef)} {asl(unionInit.kwargList)}"

# LocalType.Variant { fields } (bare — drives leave-as-is inference) or
# LocalType[Impls].Variant { fields } (explicit-impls — escape hatch when
# leave-as-is can't produce a fully-bound type). Both productions land
# on the same UnionRef shape carrying an impls seq; empty means bare.
proc unionInitializerConsumer(parser: Parser): Result[UnionInitializer, ParserError] =
  let unionRef = ? parser.expect(unionRefSpec)
  discard ? parser.expect(SPACE.optional())
  let fields = ? parser.expect(kwargListSpec)
  ok(newUnionInitializer(unionRef, fields))

let unionInitSpec* = newSpec[UnionInitializer]("union initializer", unionInitializerConsumer)

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

let initSpec* = oneOf("initializer spec", @[
  map(unionInitSpec, newInitializer),
  map(structInitSpec, newInitializer),
  map(literalInitSpec, newInitializer),
])

# ----------------- InlineExpression -----------------
proc newInlineExpression*(literal: Literal): InlineExpression =
  InlineExpression(kind: iekLiteral, literal: literal)

proc newInlineExpression*(fncall: FunctionCall): InlineExpression =
  InlineExpression(kind: iekFnCall, fncall: fncall)

proc newInlineExpression*(getter: Getter): InlineExpression =
  InlineExpression(kind: iekGetter, getter: getter)

proc newInlineExpression*(initializer: Initializer): InlineExpression =
  InlineExpression(kind: iekInitializer, initializer: initializer)

proc newInlineExpression*(variable: Identifier): InlineExpression =
  InlineExpression(kind: iekVariable, variable: variable)

proc kind*(e: InlineExpression): InlineExpressionKind = e.kind

proc literal*(e: InlineExpression): Literal =
  assert e.kind == iekLiteral,
    fmt"InlineExpression.literal accessed but kind is {e.kind}"
  e.literal

proc fncall*(e: InlineExpression): FunctionCall =
  assert e.kind == iekFnCall,
    fmt"InlineExpression.fncall accessed but kind is {e.kind}"
  e.fncall

proc getter*(e: InlineExpression): Getter =
  assert e.kind == iekGetter,
    fmt"InlineExpression.getter accessed but kind is {e.kind}"
  e.getter

proc initializer*(e: InlineExpression): Initializer =
  assert e.kind == iekInitializer,
    fmt"InlineExpression.initializer accessed but kind is {e.kind}"
  e.initializer

proc variable*(e: InlineExpression): Identifier =
  assert e.kind == iekVariable,
    fmt"InlineExpression.variable accessed but kind is {e.kind}"
  e.variable

proc loc*(expression: InlineExpression): Location =
  case expression.kind:
  of iekFnCall: expression.fncall.loc
  of iekGetter: expression.getter.loc
  of iekInitializer: expression.initializer.loc
  of iekLiteral: expression.literal.loc
  of iekVariable: expression.variable.loc

proc asl(expression: InlineExpression): string =
  case expression.kind:
  of iekLiteral: asl(expression.literal)
  of iekFnCall: asl(expression.fncall)
  of iekGetter: asl(expression.getter)
  of iekInitializer: asl(expression.initializer)
  of iekVariable: asl(expression.variable)

inlineExpressionSpec = oneOf("expression", @[
  literalSpec.map(newInlineExpression),
  initSpec.map(newInlineExpression),
  fncallSpec.map(newInlineExpression),
  getterSpec.map(newInlineExpression),
  identifierSpec.map(newInlineExpression),
])

type
  StatementKind* = enum
    skNone, skVariable, skGetter
  Statement* = ref object
    expression: Expression
    loc: Location
    case kind: StatementKind
    of skNone: discard
    of skVariable: target: Identifier
    of skGetter: getter: Getter

  CaseBlock* = ref object
    pattern: CasePattern
    body: StatementList
    loc: Location

  MatchHeaderKind* = enum
    mhkAssigned, mhkDefault
  MatchHeader* = ref object
    loc: Location
    subject: InlineExpression
    case kind: MatchHeaderKind
    of mhkAssigned: target: Identifier
    of mhkDefault: discard

  MatchExpressionKind* = enum
    mekInteger, mekVariant
  MatchExpression* = ref object
    # TODO: `kind` is set here at parse time but not yet consumed. Read it
    # in the resolver to drive integer-vs-variant match handling instead of
    # re-deriving the classification from the subject type.
    kind: MatchExpressionKind
    subject: InlineExpression
    cases: seq[CaseBlock]
    loc: Location

  ExpressionKind* = enum
    ekInline, ekMatch
  Expression* = ref object
    case kind: ExpressionKind
    of ekInline: inline: InlineExpression
    of ekMatch: match: MatchExpression

  StatementList* = ref object
    statements: seq[Statement]

# Forward declarations for mutually-recursive asl procs.
proc newExpression*(inline: InlineExpression): Expression
proc newStatement*(header: MatchHeader, cases: seq[CaseBlock]): Result[Statement, ParserError]
proc asl(expression: Expression): string
proc asl*(statement: Statement): string
proc asl*(stmt: Statement, level: int, indentWidth: uint32): seq[string]
var statementListSpec*: Spec[StatementList]

# ----------------- Statement -----------------
proc newStatement*(expression: Expression, loc: Location): Statement =
  Statement(kind: skNone, expression: expression, loc: loc)

proc newStatement*(target: Identifier, expression: Expression, loc: Location): Statement =
  Statement(kind: skVariable, target: target, expression: expression, loc: loc)

proc newStatement*(getter: Getter, expression: Expression, loc: Location): Statement =
  Statement(kind: skGetter, getter: getter, expression: expression, loc: loc)

proc kind*(statement: Statement): StatementKind = statement.kind
proc loc*(statement: Statement): Location = statement.loc
proc expression*(statement: Statement): Expression = statement.expression
proc getter*(statement: Statement): Getter =
  assert(statement.kind == skGetter, fmt"Statement.getter accessed but kind is {statement.kind}")
  statement.getter
proc target*(statement: Statement): Option[Identifier] =
  case statement.kind:
  of skNone: none(Identifier)
  of skVariable: some(statement.target)
  # A getter-assignment (`x.y = z`) mutates a field — it introduces no new
  # variable binding, so it names no target.
  of skGetter: none(Identifier)

proc asl*(statement: Statement): string =
  case statement.kind:
  of skNone: asl(statement.expression)
  of skVariable: fmt"{asl(statement.target)} = {asl(statement.expression)}"
  of skGetter: fmt"{asl(statement.getter)} = {asl(statement.expression)}"

proc getterStatementConsumer(parser: Parser): Result[Statement, ParserError] =
  let getter = ? parser.expect(getterSpec)
  discard ? parser.expect(SPACE.optional())
  discard ? parser.expect("=")
  discard ? parser.expect(SPACE.optional())
  let expression = ? parser.expect(inlineExpressionSpec)
  ok(newStatement(getter, newExpression(expression), getter.loc))

let getterStatementSpec = newSpec[Statement]("getter statement", getterStatementConsumer)

proc variableStatementConsumer(parser: Parser): Result[Statement, ParserError] =
  let target = ? parser.expect(identifierSpec)
  discard ? parser.expect(SPACE.optional())
  discard ? parser.expect("=")
  discard ? parser.expect(SPACE.optional())
  let expression = ? parser.expect(inlineExpressionSpec)
  ok(newStatement(target, newExpression(expression), target.loc))

let variableStatementSpec = newSpec[Statement]("variable statement", variableStatementConsumer)

proc emptyStatementConsumer(parser: Parser): Result[Statement, ParserError] =
  let expression = ? parser.expect(inlineExpressionSpec)
  ok(newStatement(newExpression(expression), expression.loc))

let emptyStatementSpec = newSpec[Statement]("empty statement", emptyStatementConsumer)

# ----------------- CaseBlock -----------------
proc newCaseBlock*(pattern: CasePattern, body: StatementList,
    loc: Location): CaseBlock =
  CaseBlock(pattern: pattern, body: body, loc: loc)

proc pattern*(caseBlock: CaseBlock): CasePattern = caseBlock.pattern
proc statements*(caseBlock: CaseBlock): seq[Statement] = caseBlock.body.statements
proc loc*(caseBlock: CaseBlock): Location = caseBlock.loc

proc asl(caseBlock: CaseBlock, level: int, indentWidth: uint32): seq[string] =
  let indent = " ".repeat(level * indentWidth.int)
  var lines: seq[string]
  lines.add(fmt"{indent}case {asl(caseBlock.pattern)}:")
  for s in caseBlock.body.statements:
    for line in asl(s, level + 1, indentWidth):
      lines.add(line)
  lines

proc caseConsumer(parser: Parser): Result[CaseBlock, ParserError] =
  let (pat, body) = ? parser.indentedBlock(caseHeaderSpec, statementListSpec)
  ok(newCaseBlock(pat, body, pat.loc))

let caseBlockSpec* = newSpec[CaseBlock]("case block", caseConsumer)

# ----------------- MatchHeader -----------------
proc newMatchHeader*(target: Identifier, subject: InlineExpression, loc: Location): Result[MatchHeader, ParserError] =
  ok(MatchHeader(kind: mhkAssigned, loc: loc, target: target, subject: subject))

proc newMatchHeader*(subject: InlineExpression, loc: Location): Result[MatchHeader, ParserError] =
  ok(MatchHeader(kind: mhkDefault, loc: loc, subject: subject))

proc kind*(header: MatchHeader): MatchHeaderKind = header.kind
proc subject*(header: MatchHeader): InlineExpression = header.subject
proc loc*(header: MatchHeader): Location = header.loc
proc target*(header: MatchHeader): Identifier =
  assert header.kind == mhkAssigned,
    fmt"MatchHeader.target accessed but kind is {header.kind}"
  header.target

proc defaultMatchHeaderConsumer(parser: Parser): Result[MatchHeader, ParserError] =
  let matchKeyword = ? parser.expect("match")
  discard ? parser.expect(SPACE)
  let subject = ? parser.expect(inlineExpressionSpec)
  discard parser.expect(SPACE.optional())
  discard ? parser.expect(":")
  newMatchHeader(subject, matchKeyword.loc)

let defaultMatchHeaderSpec* = newSpec("match header", defaultMatchHeaderConsumer)

proc assignedMatchHeaderConsumer(parser: Parser): Result[MatchHeader, ParserError] =
  let target = ? parser.expect(identifierSpec)
  discard ? parser.expect(SPACE.optional())
  discard ? parser.expect("=")
  discard ? parser.expect(SPACE.optional())
  let matchHeader = ? parser.expect(defaultMatchHeaderSpec)
  newMatchHeader(target, matchHeader.subject, matchHeader.loc)

let assignedMatchHeaderSpec* = newSpec("assigned match header", assignedMatchHeaderConsumer)

let matchHeaderSpec* = oneOf("match header", @[
  defaultMatchHeaderSpec,
  assignedMatchHeaderSpec,
])

proc validateIntegerCasePatterns(cases: seq[CaseBlock]): Result[void, ParserError] =
  # Uniqueness is keyed on the parsed value's canonical form (`value`),
  # not the raw spelling, so `0`/`00`/`+0` collapse to one key and only a
  # genuinely repeated value is rejected.
  var values: Table[string, Location]
  for index, caseBlock in cases:
    case caseBlock.pattern.kind:
    of cpkInteger:
      if caseBlock.pattern.intLit.value in values:
        let prev = values[caseBlock.pattern.intLit.value]
        let msg = fmt"{caseBlock.pattern.loc} duplicate value encountered previously being matched at {prev}"
        return err(newParserError(msg, caseBlock.pattern.loc))
      else:
        values[caseBlock.pattern.intLit.value] = caseBlock.pattern.loc
    of cpkUnion:
      let msg = fmt"{caseBlock.pattern.loc} variant pattern can not be mixed with integer patterns"
      return err(newParserError(msg, caseBlock.pattern.loc))
    of cpkVariable:
      if index < cases.len - 1:
        let msg = fmt"{caseBlock.pattern.loc} variable pattern is only allowed in last case block"
        return err(newParserError(msg, caseBlock.pattern.loc))
  ok()

proc validateVariantCasePatterns(cases: seq[CaseBlock]): Result[void, ParserError] =
  var variants: Table[Identifier, Location]
  for index, caseBlock in cases:
    case caseBlock.pattern.kind:
    of cpkUnion:
      if caseBlock.pattern.variant.name in variants:
        let prev = variants[caseBlock.pattern.variant.name]
        let msg = fmt"{caseBlock.pattern.loc} duplicate variant encountered previously being matched at {prev}"
        return err(newParserError(msg, caseBlock.pattern.loc))
      else:
        variants[caseBlock.pattern.variant.name] = caseBlock.pattern.loc
    of cpkInteger:
      let msg = fmt"{caseBlock.pattern.loc} integer pattern can not be mixed with variant patterns"
      return err(newParserError(msg, caseBlock.pattern.loc))
    of cpkVariable:
      if index < cases.len - 1:
        let msg = fmt"{caseBlock.pattern.loc} variable pattern is only allowed in last case block"
        return err(newParserError(msg, caseBlock.pattern.loc))
  ok()

# ----------------- MatchExpression -----------------
proc newMatchExpression*(subject: InlineExpression, cases: seq[CaseBlock],
    loc: Location): Result[MatchExpression, ParserError] =
  var errors: seq[ParserError]
  let maybeIntegerMatchExpr = validateIntegerCasePatterns(cases)
  if maybeIntegerMatchExpr.isOk:
    return ok(MatchExpression(kind: mekInteger, subject: subject, cases: cases, loc: loc))
  else:
    errors.add(maybeIntegerMatchExpr.error)

  let maybeVariantMatchExpr = validateVariantCasePatterns(cases)
  if maybeVariantMatchExpr.isOk:
    return ok(MatchExpression(kind: mekVariant, subject: subject, cases: cases, loc: loc))
  else:
    errors.add(maybeVariantMatchExpr.error)

  err(errors.max())

proc subject*(match: MatchExpression): InlineExpression = match.subject
proc cases*(match: MatchExpression): seq[CaseBlock] = match.cases
proc loc*(match: MatchExpression): Location = match.loc

proc asl(matchExpr: MatchExpression, level: int, indentWidth: uint32): seq[string] =
  let indent = " ".repeat(level * indentWidth.int)
  var lines: seq[string]
  lines.add(fmt"{indent}match {asl(matchExpr.subject)}:")
  for cb in matchExpr.cases:
    for line in asl(cb, level + 1, indentWidth):
      lines.add(line)
  lines

proc matchBlockConsumer(parser: Parser): Result[Statement, ParserError] =
  let (header, cases) = ? parser.indentedBlock(matchHeaderSpec, caseBlockSpec.atLeastOne())
  newStatement(header, cases)

let matchBlockSpec* = newSpec("match block", matchBlockConsumer)

# ----------------- Expression -----------------
proc newExpression*(inline: InlineExpression): Expression =
  Expression(kind: ekInline, inline: inline)

proc newExpression*(match: MatchExpression): Expression =
  Expression(kind: ekMatch, match: match)

proc newExpression*(variable: Identifier): Expression =
  variable.newInlineExpression().newExpression()

proc kind*(e: Expression): ExpressionKind = e.kind

proc inline*(e: Expression): InlineExpression =
  assert e.kind == ekInline,
    fmt"Expression.inline accessed but kind is {e.kind}"
  e.inline

proc match*(e: Expression): MatchExpression =
  assert e.kind == ekMatch,
    fmt"Expression.match accessed but kind is {e.kind}"
  e.match

proc loc*(expression: Expression): Location =
  case expression.kind:
  of ekInline: expression.inline.loc
  of ekMatch: expression.match.loc

proc asl(expression: Expression): string =
  case expression.kind:
  of ekInline: expression.inline.asl
  of ekMatch: "" # match is a block expression, use asl(stmt, level, indentWidth)

# ----------------- Statement (match construction) -----------------
proc newStatement*(header: MatchHeader, cases: seq[CaseBlock]): Result[Statement, ParserError] =
  let matchExpr = ? newMatchExpression(header.subject, cases, header.loc)
  case header.kind:
  of mhkDefault: ok(newStatement(newExpression(matchExpr), matchExpr.loc))
  of mhkAssigned: ok(newStatement(header.target, newExpression(matchExpr), header.loc))

proc isBlockStatement(stmt: Statement): bool = stmt.expression.kind == ekMatch

proc asl*(stmt: Statement, level: int, indentWidth: uint32): seq[string] =
  let indent = " ".repeat(level * indentWidth.int)
  if not stmt.isBlockStatement:
    return @[fmt"{indent}{asl(stmt)}"]
  # RHS is a match expression spanning multiple lines.
  let matchLines = asl(stmt.expression.match, level, indentWidth)
  let maybeTarget = target(stmt)
  var lines: seq[string]
  if maybeTarget.isNone:
    # Bare `match <subj>:` statement (no assignment target) — the match's
    # own asl already renders it correctly, so pass the lines through.
    lines = matchLines
  else:
    # Targeted `x = match <subj>:`. The match's asl returns lines already
    # indented at `level`; the first starts `<indent>match <subj>:`, so
    # splice `<target> = ` in after the leading indent to join.
    let firstAfterIndent = matchLines[0][indent.len..^1]
    lines.add(fmt"{indent}{asl(maybeTarget.get)} = {firstAfterIndent}")
    for i in 1..<matchLines.len:
      lines.add(matchLines[i])
  lines

let inlineStatementSpec = oneOf("inline statement", @[getterStatementSpec, variableStatementSpec, emptyStatementSpec])

let statementSpec = oneOf("statement", @[
  matchBlockSpec,
  inlineStatementSpec.indentedLine(),
])

# ----------------- StatementList -----------------
proc newStatementList*(statements: seq[Statement]): StatementList =
  StatementList(statements: statements)

proc statements*(sl: StatementList): seq[Statement] = sl.statements

statementListSpec = statementSpec.atLeastOne().map(newStatementList)
