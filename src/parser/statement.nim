import strformat, strutils, sequtils, tables, results

import ../tokenizer/main as tokenizer
import error

import identifiers
import literals
import refs

# ============================================================
# Getter
# ============================================================

type Getter* = ref object
  source: Identifier
  property: Identifier
  loc: Location

proc newGetter*(source: Identifier, property: Identifier, loc: Location): Getter =
  Getter(source: source, property: property, loc: loc)

proc source*(g: Getter): Identifier = g.source
proc property*(g: Getter): Identifier = g.property
proc loc*(g: Getter): Location = g.loc

proc asl*(getter: Getter): string =
  fmt"{asl(getter.source)}.{asl(getter.property)}"

# ============================================================
# UnionPatternField
# ============================================================

type UnionPatternField* = ref object
  name: Identifier
  binding: Identifier
  loc: Location

proc newUnionPatternField*(name: Identifier, binding: Identifier,
    loc: Location): UnionPatternField =
  UnionPatternField(name: name, binding: binding, loc: loc)

proc name*(field: UnionPatternField): Identifier = field.name
proc binding*(field: UnionPatternField): Identifier = field.binding

proc asl(field: UnionPatternField): string =
  fmt"{asl(field.name)}: {asl(field.binding)}"

# ============================================================
# UnionPattern
# ============================================================

proc validateFieldNameConflict(fields: seq[UnionPatternField]): Result[void, ParserError] =
  var nameIndex: Table[Identifier, int]
  for index, field in fields:
    if field.name in nameIndex:
      let prev = fields[nameIndex[field.name]].name
      let msg = fmt"duplicate field encountered, see previous declaration at {prev.loc}"
      return err(newParserError(msg, field.name.loc))
    nameIndex[field.name] = index
  ok()

proc validateFieldBindingConflict(fields: seq[UnionPatternField]): Result[void, ParserError] =
  var bindingIndex: Table[Identifier, int]
  for index, field in fields:
    if field.binding in bindingIndex:
      let prev = fields[bindingIndex[field.binding]].binding
      let msg = fmt"duplicate binding encountered, see previous binding at {prev.loc}"
      return err(newParserError(msg, field.binding.loc))
    else:
      bindingIndex[field.binding] = index
  ok()

type UnionPattern* = ref object
  variant: Identifier
  fields: seq[UnionPatternField]
  bindings: seq[Identifier]
  loc: Location

proc newUnionPattern*(variant: Identifier, fields: seq[UnionPatternField]): Result[UnionPattern, ParserError] =
  ? validateFieldNameConflict(fields)
  ? validateFieldBindingConflict(fields)
  let bindings = fields.mapIt(it.binding)
  ok(UnionPattern(variant: variant, fields: fields, bindings: bindings))

proc name*(vp: UnionPattern): Identifier = vp.variant
proc fields*(vp: UnionPattern): seq[UnionPatternField] = vp.fields
proc bindings*(vp: UnionPattern): seq[Identifier] = vp.bindings
proc loc*(vp: UnionPattern): Location = vp.name.loc

proc asl(vp: UnionPattern): string =
  var content: string
  let inner = vp.fields.mapIt(asl(it)).join(", ")
  content.add(fmt"{asl(vp.variant)} {{ {inner} }}")
  content

# ============================================================
# CasePattern
# ============================================================

type
  CasePatternKind* = enum
    cpkInteger, cpkVariable, cpkUnion
  CasePattern* = ref object
    case kind: CasePatternKind
    of cpkInteger: intLit: IntegerLiteral
    of cpkVariable: variable: Identifier
    of cpkUnion: variant: UnionPattern

proc newCasePattern*(intLit: IntegerLiteral): CasePattern =
  CasePattern(kind: cpkInteger, intLit: intLit)

proc newCasePattern*(variable: Identifier): CasePattern =
  CasePattern(kind: cpkVariable, variable: variable)

proc newCasePattern*(variant: UnionPattern): CasePattern =
  CasePattern(kind: cpkUnion, variant: variant)

proc kind*(cp: CasePattern): CasePatternKind = cp.kind
proc loc*(cp: CasePattern): Location =
  case cp.kind:
  of cpkInteger: cp.intLit.loc
  of cpkVariable: cp.variable.loc
  of cpkUnion: cp.variant.loc

proc intLit*(cp: CasePattern): IntegerLiteral =
  assert cp.kind == cpkInteger,
    fmt"CasePattern.intLit accessed but kind is {cp.kind}"
  cp.intLit

proc variable*(cp: CasePattern): Identifier =
  assert cp.kind == cpkVariable,
    fmt"CasePattern.variable accessed but kind is {cp.kind}"
  cp.variable

proc variant*(cp: CasePattern): UnionPattern =
  assert cp.kind == cpkUnion,
    fmt"CasePattern.variant accessed but kind is {cp.kind}"
  cp.variant

proc asl*(pattern: CasePattern): string =
  case pattern.kind:
  of cpkInteger: asl(pattern.intLit)
  of cpkVariable: asl(pattern.variable)
  of cpkUnion: asl(pattern.variant)

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
proc asl*(stmt: Statement, level: int, indentWidth: uint32): seq[string]

# ----------------- ArgumentList -----------------
proc newArgumentList*(args: seq[Expression], loc: Location): ArgumentList =
  ArgumentList(args: args, loc: loc)

proc arity(argList: ArgumentList): int = argList.args.len

proc asl(argList: ArgumentList): string =
  var content: string
  let inner = argList.args.mapIt(asl(it)).join(", ")
  content.add(fmt"({inner})")
  content

# ----------------- FunctionCall -----------------
proc newFunctionCall*(root: Identifier, name: Identifier,
    argList: ArgumentList): FunctionCall =
  FunctionCall(root: root, name: name, argList: argList)

proc loc*(fncall: FunctionCall): Location = fncall.root.loc

proc root*(fncall: FunctionCall): Identifier = fncall.root
proc name*(fncall: FunctionCall): Identifier = fncall.name
proc args*(fncall: FunctionCall): seq[Expression] = fncall.argList.args
proc arity*(fncall: FunctionCall): int = fncall.argList.arity

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

proc validateKeyNameConflict(args: seq[KeywordArgument]): Result[void, ParserError] =
  var argIndex: Table[Identifier, int]
  for index, arg in args:
    if arg.name in argIndex:
      let prev = args[argIndex[arg.name]]
      let msg = fmt"duplicate field encountered, see previous assignment at {prev.loc}"
      return err(newParserError(msg, arg.loc))
    argIndex[arg.name] = index
  ok()

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

proc newGeneratedKeywordArgumentList(args: seq[KeywordArgument], loc: Location): KeywordArgumentList =
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

# ----------------- StructInitializer -----------------
proc newStructInitializer*(structRef: StructRef, kwargList: KeywordArgumentList): StructInitializer =
  StructInitializer(structRef: structRef, kwargList: kwargList)

proc structRef*(struct: StructInitializer): StructRef = struct.structRef
proc kwargs*(struct: StructInitializer): seq[KeywordArgument] = struct.kwargList.args
proc kwargList*(struct: StructInitializer): KeywordArgumentList = struct.kwargList
proc loc*(struct: StructInitializer): Location = struct.structRef.loc

proc asl(nonPrim: StructInitializer): string =
  fmt"{asl(nonPrim.structRef)} {asl(nonPrim.kwargList)}"

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

proc asl(caseBlock: CaseBlock, level: int, indentWidth: uint32): seq[string] =
  let indent = " ".repeat(level * indentWidth.int)
  var lines: seq[string]
  lines.add(fmt"{indent}case {asl(caseBlock.pattern)}:")
  for s in caseBlock.body.statements:
    for line in asl(s, level + 1, indentWidth):
      lines.add(line)
  lines

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

proc asl(matchExpr: MatchExpression, level: int, indentWidth: uint32): seq[string] =
  let indent = " ".repeat(level * indentWidth.int)
  var lines: seq[string]
  lines.add(fmt"{indent}match {asl(matchExpr.subject)}:")
  for cb in matchExpr.cases:
    for line in asl(cb, level + 1, indentWidth):
      lines.add(line)
  lines

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
  of ekMatch: "" # match is a block expression, use asl(stmt, level, indentWidth)

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

proc asl*(stmt: Statement, level: int, indentWidth: uint32): seq[string] =
  let indent = " ".repeat(level * indentWidth.int)
  if not stmt.isBlockStatement:
    return @[fmt"{indent}{asl(stmt)}"]
  var lines: seq[string]
  case stmt.kind:
  of skExpr:
    lines = asl(stmt.expression.match, level, indentWidth)
  of skAssignment:
    # RHS is a match expression spanning multiple lines. Render as:
    #   <indent>x = match <subj>:
    #   <indent+width>  case ...
    # The match's asl returns lines already indented at `level`; the
    # first line starts with `<indent>match <subj>:` — replace the
    # leading indent + `match` with `<indent>x = match` to join.
    let matchLines = asl(stmt.assignment.expression.match, level, indentWidth)
    let firstAfterIndent = matchLines[0][indent.len..^1]
    lines.add(fmt"{indent}{asl(stmt.assignment.target)} = {firstAfterIndent}")
    for i in 1..<matchLines.len:
      lines.add(matchLines[i])
  of skSetter:
    lines = @[fmt"{indent}{asl(stmt.setter)}"]
  lines

# ----------------- StatementList -----------------
proc newStatementList*(statements: seq[Statement]): StatementList =
  StatementList(statements: statements)

proc statements*(sl: StatementList): seq[Statement] = sl.statements

proc expand(expression: Expression, start: int, replace: bool = true): (seq[Statement], Expression, int)
proc expand(statement: Statement, start: int): (seq[Statement], int)

proc expand(fncall: FunctionCall, start: int): (seq[Statement], FunctionCall, int) =
  var expandedStmts: seq[Statement]
  var expandedArgs: seq[Expression]
  var counter = start

  for arg in fncall.argList.args:
    let (updatedStmts, updatedArg, updatedCounter) = arg.expand(counter)
    expandedStmts.add(updatedStmts)
    expandedArgs.add(updatedArg)
    counter = updatedCounter

  let generatedArgList = newArgumentList(expandedArgs, fncall.argList.loc)
  let generatedFunctionCall = newFunctionCall(fncall.root, fncall.name, generatedArgList)
  (expandedStmts, generatedFunctionCall, counter)

proc expand(structInit: StructInitializer, start: int): (seq[Statement], StructInitializer, int) =
  var expandedStmts: seq[Statement]
  var expandedkwargs: seq[KeywordArgument]
  var counter = start
  for kwarg in structInit.kwargs:
    let (updatedStmts, updatedValue, updatedCounter) = kwarg.expression.expand(counter)
    expandedStmts.add(updatedStmts)
    expandedkwargs.add(newKeywordArgument(kwarg.name, updatedValue, kwarg.loc))
    counter = updatedCounter

  let generatedkwargList = newGeneratedKeywordArgumentList(expandedkwargs, structInit.kwargList.loc)
  let generatedStructInit = newStructInitializer(structInit.structRef, generatedkwargList)
  (expandedStmts, generatedStructInit, counter)

proc expand(unionInit: UnionInitializer, start: int): (seq[Statement], UnionInitializer, int) =
  var expandedStmts: seq[Statement]
  var expandedkwargs: seq[KeywordArgument]
  var counter = start
  for kwarg in unionInit.kwargs:
    let (updatedStmts, updatedValue, updatedCounter) = kwarg.expression.expand(counter)
    expandedStmts.add(updatedStmts)
    expandedkwargs.add(newKeywordArgument(kwarg.name, updatedValue, kwarg.loc))
    counter = updatedCounter

  let generatedkwargList = newGeneratedKeywordArgumentList(expandedkwargs, unionInit.kwargList.loc)
  let generatedUnionInit = newUnionInitializer(unionInit.unionRef, generatedkwargList)
  (expandedStmts, generatedUnionInit, counter)

proc expand(initializer: Initializer, start: int): (seq[Statement], Initializer, int) =
  case initializer.kind:
  of ikStruct:
    let (expandedStmts, expandedStructInit, counter) = initializer.struct.expand(start)
    return (expandedStmts, newInitializer(expandedStructInit), counter)
  of ikLiteral:
    return (newSeq[Statement](), initializer, start)
  of ikUnion:
    let (expandedStmts, expandedUnionInit, counter) = initializer.union.expand(start)
    return (expandedStmts, newInitializer(expandedUnionInit), counter)

proc expand(caseBlock: CaseBlock, start: int): (CaseBlock, int) =
  var expanded: seq[Statement]
  var counter = start
  for statement in caseBlock.statements:
    let (expandedStmts, updatedCounter) = statement.expand(counter)
    expanded.add(expandedStmts)
    counter = updatedCounter

  let expandedCaseBlock = newCaseBlock(caseBlock.pattern, newStatementList(expanded), caseBlock.loc)
  (expandedCaseBlock, counter)

proc expand(match: MatchExpression, start: int): (seq[Statement], MatchExpression, int) =
  var expandedStmts: seq[Statement]
  var counter = start
  let (expandedSubjectStmts, expandedSubjectExpr, updatedCounter) = match.subject.expand(counter)
  expandedStmts.add(expandedSubjectStmts)
  counter = updatedCounter

  var expandedCases: seq[CaseBlock]
  for caseBlock in match.cases:
    let (expandedCase, updatedCounter) = caseBlock.expand(counter)
    expandedCases.add(expandedCase)
    counter = updatedCounter

  let expandedMatchExpr = newMatchExpression(expandedSubjectExpr, expandedCases, match.loc)
  (expandedStmts, expandedMatchExpr, counter)

proc replace(expression: Expression, start: int): (Statement, Expression, int) =
  let generatedTarget = newGeneratedIdentifier(start, expression.loc)
  let generatedAssignment = newAssignment(generatedTarget, expression, expression.loc)
  (newStatement(generatedAssignment), newExpression(generatedTarget), start + 1)

proc expand(expression: Expression, start: int, replace: bool = true): (seq[Statement], Expression, int) =
  case expression.kind:
  of ekLiteral, ekVariable:
    # Literals and variables are already terminal — no sub-expressions
    # to lift and no useful transformation from binding them to a temp:
    # a literal at a value position needs to reach `analyzeBareLiteral`
    # with its expected context intact (Approach C's concrete-adopt);
    # a variable is already a named binding, so wrapping in another
    # temp would just add noise. Return as-is regardless of `replace`.
    return (@[], expression, start)
  of ekGetter:
    # A Getter has no sub-expressions to lift (source and property are
    # both Identifiers), but at a value position we still want to bind
    # its read result to a temp so the ANF invariant holds: every
    # value-position expression downstream is a Variable or a Literal.
    # The `replace = false` path (assignment / setter RHS) leaves it
    # alone because the enclosing construct is already the binding.
    if replace:
      var (replacedStmt, replacedExpr, replacedCounter) = expression.replace(start)
      (@[replacedStmt], replacedExpr, replacedCounter)
    else:
      (@[], expression, start)
  of ekFnCall:
    var (expandedStmts, expandedFncall, counter) = expression.fncall.expand(start)
    if replace:
      var (replacedStmt, replacedExpr, replacedCounter) = expandedFncall.newExpression.replace(counter)
      expandedStmts.add(replacedStmt)
      (expandedStmts, replacedExpr, replacedCounter)
    else:
      (expandedStmts, newExpression(expandedFncall), counter)
  of ekInitializer:
    var (expandedStmts, expandedInitializer, counter) = expression.initializer.expand(start)
    if replace:
      var (replacedStmt, replacedExpr, replacedCounter) = expandedInitializer.newExpression.replace(counter)
      expandedStmts.add(replacedStmt)
      (expandedStmts, replacedExpr, replacedCounter)
    else:
      (expandedStmts, newExpression(expandedInitializer), counter)
  of ekMatch:
    var (expandedStmts, expandedMatchExpr, counter) = expression.match.expand(start)
    if replace:
      var (replacedStmt, replacedExpr, replacedCounter) = expandedMatchExpr.newExpression.replace(counter)
      expandedStmts.add(replacedStmt)
      (expandedStmts, replacedExpr, replacedCounter)
    else:
      (expandedStmts, newExpression(expandedMatchExpr), counter)

proc expand(assignment: Assignment, start: int): (seq[Statement], Assignment, int) =
  let (expandedStmts, expandedExpr, counter) = assignment.expression.expand(start, replace = false)
  (expandedStmts, newAssignment(assignment.target, expandedExpr, assignment.loc), counter)

proc expand(setter: Setter, start: int): (seq[Statement], Setter, int) =
  let (expandedStmts, expandedExpr, counter) = setter.expression.expand(start, replace = false)
  (expandedStmts, newSetter(setter.target, expandedExpr, setter.loc), counter)

proc expand(statement: Statement, start: int): (seq[Statement], int) =
  case statement.kind:
  of skAssignment:
    var (expandedStmts, expandedAssignment, updatedCounter) = statement.assignment.expand(start)
    expandedStmts.add(newStatement(expandedAssignment))
    (expandedStmts, updatedCounter)
  of skSetter:
    var (expandedStmts, expandedSetter, updatedCounter) = statement.setter.expand(start)
    expandedStmts.add(newStatement(expandedSetter))
    (expandedStmts, updatedCounter)
  of skExpr:
    # Every bare-expression statement is explicitly wrapped in a
    # synthesized `__asl_arg_N = <expr>` assignment. Two steps:
    #   1. `expression.expand(start, replace = false)` lifts nested
    #      *subexpressions* (function args, kwarg values, match
    #      subjects) into their own preceding temp assignments. The
    #      outer expression is NOT wrapped at this step — that's what
    #      `replace = false` signals, matching how `expand(assignment)`
    #      and `expand(setter)` treat their RHS.
    #   2. `.replace(counter)` on the resulting outer expression binds
    #      it to a fresh temp, producing the final assignment.
    #
    # Note the asymmetry between expressions and statements: bare
    # literal / variable EXPRESSIONS (as subexpressions) are never
    # expanded — the `ekLiteral, ekVariable` arm of `expression.expand`
    # returns them unchanged regardless of `replace`, because they're
    # already terminal (a literal reaches `analyzeBareLiteral` with its
    # expected context intact under Approach C; a variable is already
    # a named binding). Getters ARE lifted at value positions
    # (`replace = true`) but pass through unchanged at RHS positions
    # (`replace = false`). But when any of these shapes — literal,
    # variable, or getter — appear as the *outer* expression of a
    # bare-expression STATEMENT, we still wrap them here at the
    # statement level via the explicit `.replace(counter)` below.
    # That keeps the invariant that every top-level statement in a
    # function body is an Assignment or a Setter, never a raw
    # bare-expression — downstream layers reason about a uniform
    # ANF shape.
    #
    # Two failure modes without the wrap:
    # - A bare `value` in a case body would vanish (empty case block
    #   trips body.nim:326's non-empty-statements assertion) because
    #   the top-level `expand(Expression)` returns the variable
    #   unchanged and the skExpr arm has nothing to add.
    # - The uniform ANF invariant would leak: a mix of assignments and
    #   bare expressions in the same body forces downstream code to
    #   handle two shapes per position.
    var (expandedStmts, expandedExpr, counter) = statement.expression.expand(start, replace = false)
    let (replacedStmt, _, replacedCounter) = expandedExpr.replace(counter)
    expandedStmts.add(replacedStmt)
    (expandedStmts, replacedCounter)

proc expand(sl: StatementList): StatementList =
  var expanded: seq[Statement]
  var counter: int = 0
  for statement in sl.statements:
    let (expandedStmts, updatedCounter) = statement.expand(counter)
    expanded.add(expandedStmts)
    counter = updatedCounter
  newStatementList(expanded)
