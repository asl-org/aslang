## Body-level statement cluster — the self-mutually-recursive
## expression / statement / initializer web that walks a function
## body. Nim requires mutually-referencing `ref object` types to share
## one `type` block, so every node in the cycle lives here:
##
##   ResolvedKeywordArgument, ResolvedStructInitializer,
##   ResolvedUnionInitializer, ResolvedInitializer,
##   ResolvedFunctionCall, ResolvedAssignment,
##   ResolvedCaseBlock, ResolvedMatchExpression,
##   ResolvedExpression, ResolvedStatement
##
## Leaf nodes that carry no back-reference into the cycle
## (ResolvedGetter, ResolvedLiteralInitializer, ResolvedStructRef,
## ResolvedUnionRef) live in their own files and are imported here.

import results, strformat, options, tables

import ../tokenizer/main as tokenizer
import ../parser/main as parser
import argtype
import refs

# ---- ResolvedGetter (dotted access `source.property`) ----

type ResolvedGetter* = ref object
  parsed: Getter

proc newResolvedGetter*(parsed: Getter): ResolvedGetter =
  ResolvedGetter(parsed: parsed)

proc source*(getter: ResolvedGetter): Identifier = getter.parsed.source
proc property*(getter: ResolvedGetter): Identifier = getter.parsed.property
proc loc*(getter: ResolvedGetter): Location = getter.parsed.loc

# ---- ResolvedCasePattern (integer | variable | union match) ----

type
  ResolvedCasePatternKind* = enum
    rcpkInteger, rcpkVariable, rcpkUnion
  ResolvedCasePattern* = ref object
    case kind: ResolvedCasePatternKind
    of rcpkInteger: integer: IntegerLiteral
    of rcpkVariable: variable: Identifier
    of rcpkUnion: variant: UnionPattern

proc newResolvedCasePattern*(integer: IntegerLiteral): ResolvedCasePattern =
  ResolvedCasePattern(kind: rcpkInteger, integer: integer)

proc newResolvedCasePattern*(variable: Identifier): ResolvedCasePattern =
  ResolvedCasePattern(kind: rcpkVariable, variable: variable)

proc newResolvedCasePattern*(variant: UnionPattern): ResolvedCasePattern =
  ResolvedCasePattern(kind: rcpkUnion, variant: variant)

proc kind*(pattern: ResolvedCasePattern): ResolvedCasePatternKind = pattern.kind
proc integer*(pattern: ResolvedCasePattern): IntegerLiteral =
  assert pattern.kind == rcpkInteger,
    fmt"ResolvedCasePattern.integer accessed but kind is {pattern.kind}"
  pattern.integer
proc variable*(pattern: ResolvedCasePattern): Identifier =
  assert pattern.kind == rcpkVariable,
    fmt"ResolvedCasePattern.variable accessed but kind is {pattern.kind}"
  pattern.variable
proc variant*(pattern: ResolvedCasePattern): UnionPattern =
  assert pattern.kind == rcpkUnion,
    fmt"ResolvedCasePattern.variant accessed but kind is {pattern.kind}"
  pattern.variant
proc loc*(pattern: ResolvedCasePattern): Location =
  case pattern.kind:
  of rcpkInteger: pattern.integer.loc
  of rcpkVariable: pattern.variable.loc
  of rcpkUnion: pattern.variant.loc
proc bindings*(pattern: ResolvedCasePattern): seq[Identifier] =
  case pattern.kind:
  of rcpkInteger: @[]
  of rcpkVariable: @[pattern.variable]
  of rcpkUnion: pattern.variant.bindings

# ---- ResolvedLiteralInitializer (`u32 42` — primitive literal) ----

type ResolvedLiteralInitializer* = ref object
  parsed: LiteralInitializer
  argType: ResolvedModuleArgumentType
  def: LiteralDef

proc newResolvedLiteralInitializer*(parsed: LiteralInitializer, argType: ResolvedModuleArgumentType, def: LiteralDef): ResolvedLiteralInitializer =
  ResolvedLiteralInitializer(parsed: parsed, argType: argType, def: def)

proc loc*(init: ResolvedLiteralInitializer): Location = init.parsed.loc
proc literal*(init: ResolvedLiteralInitializer): Literal = init.parsed.value
proc argType*(init: ResolvedLiteralInitializer): ResolvedModuleArgumentType = init.argType

type ResolvedLiteral* = ref object
  parsed: Literal
  default: Module
  def: LiteralDef

proc newResolvedLiteral*(parsed: Literal, module: Module, def: LiteralDef): ResolvedLiteral =
  ResolvedLiteral(parsed: parsed, default: module, def: def)

proc loc*(literal: ResolvedLiteral): Location = literal.parsed.loc
proc value*(literal: ResolvedLiteral): Literal = literal.parsed
proc default*(literal: ResolvedLiteral): Module = literal.default

type
  ResolvedKeywordArgument* = ref object
    parsed: KeywordArgument
    expression: ResolvedExpression

  ResolvedStructInitializer* = ref object
    parsed: StructInitializer
    structRef: ResolvedStructRef
    kwargs: seq[ResolvedKeywordArgument]

  ResolvedUnionInitializer* = ref object
    parsed: UnionInitializer
    unionRef: ResolvedUnionRef
    kwargs: seq[ResolvedKeywordArgument]

  ResolvedInitializerKind* = enum
    rikStruct, rikUnion, rikLiteral
  ResolvedInitializer* = ref object
    case kind: ResolvedInitializerKind
    of rikStruct: struct: ResolvedStructInitializer
    of rikUnion: union: ResolvedUnionInitializer
    of rikLiteral: literal: ResolvedLiteralInitializer

  ResolvedFunctionCall* = ref object
    parsed: FunctionCall
    typ: parser.LocalType
    args: seq[ResolvedExpression]

  ResolvedAssignmentKind* = enum
    # TODO: Expand rakDefault into rakNone and rakVariable
    rakGetter, rakDefault
  ResolvedAssignment* = ref object
    parsed: Statement
    expression: ResolvedExpression
    case kind: ResolvedAssignmentKind
    of rakGetter: getter: ResolvedGetter
    of rakDefault: discard

  ResolvedCaseBlock* = ref object
    parsed: CaseBlock
    pattern: ResolvedCasePattern
    statements: seq[ResolvedStatement]

  ResolvedMatchExpression* = ref object
    parsed: MatchExpression
    subject: ResolvedExpression
    cases: seq[ResolvedCaseBlock]

  ResolvedExpressionKind* = enum
    rekFunctionCall, rekVariable, rekLiteral, rekInitializer,
    rekGetter, rekMatchExpr
  ResolvedExpression* = ref object
    case kind: ResolvedExpressionKind
    of rekFunctionCall: fncall: ResolvedFunctionCall
    of rekVariable: variable: Identifier
    of rekLiteral: literal: ResolvedLiteral
    of rekInitializer: initializer: ResolvedInitializer
    of rekGetter: getter: ResolvedGetter
    of rekMatchExpr: match: ResolvedMatchExpression

  ResolvedStatement* = ref object
    assignment: ResolvedAssignment

# ---- ResolvedKeywordArgument ----

proc newResolvedKeywordArgument*(parsed: KeywordArgument,
    expression: ResolvedExpression): ResolvedKeywordArgument =
  ResolvedKeywordArgument(parsed: parsed, expression: expression)

proc expression*(kwarg: ResolvedKeywordArgument): ResolvedExpression = kwarg.expression
proc name*(kwarg: ResolvedKeywordArgument): Identifier = kwarg.parsed.name
proc loc*(kwarg: ResolvedKeywordArgument): Location = kwarg.parsed.loc

# ---- ResolvedStructInitializer ----

proc orderedKwargs(kwargs: seq[ResolvedKeywordArgument], findFieldId: proc (name: Identifier): Result[int, string], fieldCount: int, listLoc: Location): Result[seq[ResolvedKeywordArgument], string] =
  ## Shared kwarg validation for struct + union initializers: every
  ## kwarg must name an existing field, no field twice, every field
  ## supplied. Returns the kwargs reordered into canonical field
  ## order.
  var ordered = newSeq[ResolvedKeywordArgument](fieldCount)
  var fieldMap: Table[int, Location]
  for kwarg in kwargs:
    let fieldId = ? findFieldId(kwarg.name)
    if fieldId in fieldMap:
      let prevLoc = fieldMap[fieldId]
      return err(fmt"{kwarg.loc} duplicate field `{kwarg.name.asl}` encountered, see previous instance at {prevLoc}")
    ordered[fieldId] = kwarg
    fieldMap[fieldId] = kwarg.loc
  if fieldMap.len != fieldCount:
    return err(fmt"{listLoc} expected `{fieldCount}` fields but `{fieldMap.len}` were given")
  ok(ordered)

proc newResolvedStructInitializer*(parsed: StructInitializer,
    structRef: ResolvedStructRef,
    kwargs: seq[ResolvedKeywordArgument]): Result[ResolvedStructInitializer, string] =
  ## Front-door: owns the kwarg-set validation against the struct's
  ## fields; stores kwargs in canonical field order.
  let struct = structRef.struct
  let ordered = ? orderedKwargs(kwargs, proc (name: Identifier): Result[int, string] = struct.findFieldId(name), struct.fields.len, parsed.kwargList.loc)
  ok(ResolvedStructInitializer(parsed: parsed, structRef: structRef, kwargs: ordered))

proc structRef*(struct: ResolvedStructInitializer): ResolvedStructRef = struct.structRef
proc kwargs*(struct: ResolvedStructInitializer): seq[ResolvedKeywordArgument] = struct.kwargs
proc loc*(struct: ResolvedStructInitializer): Location = struct.parsed.loc

# ---- ResolvedUnionInitializer ----

proc newResolvedUnionInitializer*(parsed: UnionInitializer,
    unionRef: ResolvedUnionRef,
    kwargs: seq[ResolvedKeywordArgument]): Result[ResolvedUnionInitializer, string] =
  ## Front-door: owns the kwarg-set validation against the variant's
  ## fields; stores kwargs in canonical field order.
  let variant = unionRef.variant
  let ordered = ? orderedKwargs(kwargs, proc (name: Identifier): Result[int, string] = variant.findFieldId(name), variant.fields.len, parsed.kwargList.loc)
  ok(ResolvedUnionInitializer(parsed: parsed, unionRef: unionRef, kwargs: ordered))

proc unionRef*(init: ResolvedUnionInitializer): ResolvedUnionRef = init.unionRef
proc kwargs*(init: ResolvedUnionInitializer): seq[ResolvedKeywordArgument] = init.kwargs
proc loc*(init: ResolvedUnionInitializer): Location = init.parsed.loc
proc variant*(init: ResolvedUnionInitializer): Identifier = init.parsed.variant

# ---- ResolvedInitializer ----

proc newResolvedInitializer*(struct: ResolvedStructInitializer): ResolvedInitializer =
  ResolvedInitializer(kind: rikStruct, struct: struct)

proc newResolvedInitializer*(union: ResolvedUnionInitializer): ResolvedInitializer =
  ResolvedInitializer(kind: rikUnion, union: union)

proc newResolvedInitializer*(literal: ResolvedLiteralInitializer): ResolvedInitializer =
  ResolvedInitializer(kind: rikLiteral, literal: literal)

proc kind*(init: ResolvedInitializer): ResolvedInitializerKind = init.kind
proc literal*(init: ResolvedInitializer): ResolvedLiteralInitializer =
  assert init.kind == rikLiteral,
    fmt"ResolvedInitializer.literal accessed but kind is {init.kind}"
  init.literal
proc union*(init: ResolvedInitializer): ResolvedUnionInitializer =
  assert init.kind == rikUnion,
    fmt"ResolvedInitializer.union accessed but kind is {init.kind}"
  init.union
proc struct*(init: ResolvedInitializer): ResolvedStructInitializer =
  assert init.kind == rikStruct,
    fmt"ResolvedInitializer.struct accessed but kind is {init.kind}"
  init.struct
proc loc*(init: ResolvedInitializer): Location =
  case init.kind:
  of rikLiteral: init.literal.loc
  of rikStruct: init.struct.loc
  of rikUnion: init.union.loc

# ---- ResolvedFunctionCall ----

proc newResolvedFunctionCall*(parsed: FunctionCall,
    typ: parser.LocalType, args: seq[ResolvedExpression]): ResolvedFunctionCall =
  ResolvedFunctionCall(parsed: parsed, typ: typ, args: args)

proc loc*(fncall: ResolvedFunctionCall): Location = fncall.parsed.loc
proc name*(fncall: ResolvedFunctionCall): Identifier = fncall.parsed.name
proc arity*(fncall: ResolvedFunctionCall): int = fncall.parsed.arity
proc kind*(fncall: ResolvedFunctionCall): FunctionCallKind = fncall.parsed.kind
proc typ*(fncall: ResolvedFunctionCall): parser.LocalType = fncall.typ
proc args*(fncall: ResolvedFunctionCall): seq[ResolvedExpression] = fncall.args

proc impls*(fncall: ResolvedFunctionCall): seq[ResolvedArgumentType] =
  ## Empty for the time being — the parser has no impl syntax for
  ## FunctionCall receivers. Kept as a first-class accessor so
  ## downstream code that treats StructInit/UnionInit/FunctionCall
  ## uniformly (an "impl-carrying node") can pattern-match on it.
  ##
  ## Invariant: entries would be arity- and constraint-validated at
  ## resolve time — the current always-empty seq trivially satisfies
  ## that.
  fncall.impls

# ---- ResolvedAssignment ----

proc newResolvedAssignment*(parsed: Statement,
    expression: ResolvedExpression): ResolvedAssignment =
  ResolvedAssignment(kind: rakDefault, parsed: parsed, expression: expression)

proc newResolvedAssignment*(parsed: Statement, getter: ResolvedGetter, expression: ResolvedExpression): ResolvedAssignment =
  ResolvedAssignment(kind: rakGetter, parsed: parsed, getter: getter, expression: expression)

proc expression*(assignment: ResolvedAssignment): ResolvedExpression = assignment.expression
proc loc*(assignment: ResolvedAssignment): Location = assignment.parsed.loc
proc target*(assignment: ResolvedAssignment): Option[Identifier] = assignment.parsed.target

# ---- ResolvedCaseBlock ----

proc newResolvedCaseBlock*(parsed: CaseBlock, pattern: ResolvedCasePattern,
    statements: seq[ResolvedStatement]): ResolvedCaseBlock =
  ResolvedCaseBlock(parsed: parsed, pattern: pattern, statements: statements)

proc pattern*(caseBlock: ResolvedCaseBlock): ResolvedCasePattern = caseBlock.pattern
proc statements*(caseBlock: ResolvedCaseBlock): seq[ResolvedStatement] = caseBlock.statements
proc loc*(caseBlock: ResolvedCaseBlock): Location = caseBlock.parsed.loc

# ---- ResolvedMatchExpression ----

proc newResolvedMatchExpression*(parsed: MatchExpression,
    subject: ResolvedExpression,
    cases: seq[ResolvedCaseBlock]): ResolvedMatchExpression =
  ResolvedMatchExpression(parsed: parsed, subject: subject, cases: cases)

proc subject*(match: ResolvedMatchExpression): ResolvedExpression = match.subject
proc cases*(match: ResolvedMatchExpression): seq[ResolvedCaseBlock] = match.cases
proc loc*(match: ResolvedMatchExpression): Location = match.parsed.loc

# ---- ResolvedExpression ----

proc newResolvedExpression*(fncall: ResolvedFunctionCall): ResolvedExpression =
  ResolvedExpression(kind: rekFunctionCall, fncall: fncall)

proc newResolvedExpression*(initializer: ResolvedInitializer): ResolvedExpression =
  ResolvedExpression(kind: rekInitializer, initializer: initializer)

proc newResolvedExpression*(variable: Identifier): ResolvedExpression =
  ResolvedExpression(kind: rekVariable, variable: variable)

proc newResolvedExpression*(literal: ResolvedLiteral): ResolvedExpression =
  ResolvedExpression(kind: rekLiteral, literal: literal)

proc newResolvedExpression*(getter: ResolvedGetter): ResolvedExpression =
  ResolvedExpression(kind: rekGetter, getter: getter)

proc newResolvedExpression*(match: ResolvedMatchExpression): ResolvedExpression =
  ResolvedExpression(kind: rekMatchExpr, match: match)

proc kind*(expression: ResolvedExpression): ResolvedExpressionKind = expression.kind
proc fncall*(expression: ResolvedExpression): ResolvedFunctionCall =
  assert expression.kind == rekFunctionCall,
    fmt"ResolvedExpression.fncall accessed but kind is {expression.kind}"
  expression.fncall
proc variable*(expression: ResolvedExpression): Identifier =
  assert expression.kind == rekVariable,
    fmt"ResolvedExpression.variable accessed but kind is {expression.kind}"
  expression.variable
proc literal*(expression: ResolvedExpression): ResolvedLiteral =
  assert expression.kind == rekLiteral,
    fmt"ResolvedExpression.literal accessed but kind is {expression.kind}"
  expression.literal
proc match*(expression: ResolvedExpression): ResolvedMatchExpression =
  assert expression.kind == rekMatchExpr,
    fmt"ResolvedExpression.match accessed but kind is {expression.kind}"
  expression.match
proc init*(expression: ResolvedExpression): ResolvedInitializer =
  assert expression.kind == rekInitializer,
    fmt"ResolvedExpression.init accessed but kind is {expression.kind}"
  expression.initializer
proc getter*(expression: ResolvedExpression): ResolvedGetter =
  assert expression.kind == rekGetter,
    fmt"ResolvedExpression.getter accessed but kind is {expression.kind}"
  expression.getter
proc loc*(expression: ResolvedExpression): Location =
  case expression.kind:
  of rekFunctionCall: expression.fncall.loc
  of rekGetter: expression.getter.loc
  of rekInitializer: expression.init.loc
  of rekMatchExpr: expression.match.loc
  of rekVariable: expression.variable.loc
  of rekLiteral: expression.literal.loc

# ---- ResolvedStatement ----

proc newResolvedStatement*(assignment: ResolvedAssignment): ResolvedStatement =
  ResolvedStatement(assignment: assignment)

proc assignment*(statement: ResolvedStatement): ResolvedAssignment = statement.assignment
proc loc*(statement: ResolvedStatement): Location = statement.assignment.loc

# Accessor used by callers to thread bindings into scope.
proc variable*(statement: ResolvedStatement): Option[Identifier] =
  ## Returns the new binding introduced by this statement (if any).
  statement.assignment.target
