## Body-level statement cluster — the self-mutually-recursive
## expression / statement / initializer web that walks a function
## body. Nim requires mutually-referencing `ref object` types to share
## one `type` block, so every node in the cycle lives here:
##
##   ResolvedKeywordArgument, ResolvedStructInitializer,
##   ResolvedUnionInitializer, ResolvedInitializer,
##   ResolvedFunctionCall, ResolvedAssignment, ResolvedSetter,
##   ResolvedCaseBlock, ResolvedMatchExpression,
##   ResolvedExpression, ResolvedStatement
##
## Leaf nodes that carry no back-reference into the cycle
## (ResolvedGetter, ResolvedLiteralInitializer, ResolvedStructRef,
## ResolvedUnionRef) live in their own files and are imported here.

import strformat, options

import ./parser
import argtype
import patterns  # ResolvedCasePattern
import getter
import literalinit
import structref
import unionref

type ResolvedLiteral* = ref object
  parsed: Literal
  default: Module
  def: LiteralDef

proc newResolvedLiteral*(parsed: Literal, module: Module, def: LiteralDef): ResolvedLiteral =
  ResolvedLiteral(parsed: parsed, default: module, def: def)

proc loc*(literal: ResolvedLiteral): Location = literal.parsed.loc
proc parsed*(literal: ResolvedLiteral): Literal = literal.parsed
proc default*(literal: ResolvedLiteral): Module = literal.default
proc kind*(literal: ResolvedLiteral): LiteralKind = literal.parsed.kind
proc def*(literal: ResolvedLiteral): LiteralDef = literal.def
proc asl*(literal: ResolvedLiteral): string = literal.parsed.asl

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
    typ: parser.Type
    args: seq[ResolvedExpression]

  ResolvedAssignment* = ref object
    parsed: Assignment
    expression: ResolvedExpression

  ResolvedSetter* = ref object
    parsed: Setter
    getter: ResolvedGetter
    expression: ResolvedExpression

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

  ResolvedStatementKind* = enum
    rskAssignment, rskExpr, rskSetter
  ResolvedStatement* = ref object
    case kind: ResolvedStatementKind
    of rskAssignment: assignment: ResolvedAssignment
    of rskExpr: expression: ResolvedExpression
    of rskSetter: setter: ResolvedSetter

# ---- ResolvedKeywordArgument ----

proc newResolvedKeywordArgument*(parsed: KeywordArgument,
    expression: ResolvedExpression): ResolvedKeywordArgument =
  ResolvedKeywordArgument(parsed: parsed, expression: expression)

proc parsed*(kwarg: ResolvedKeywordArgument): KeywordArgument = kwarg.parsed
proc expression*(kwarg: ResolvedKeywordArgument): ResolvedExpression = kwarg.expression
proc name*(kwarg: ResolvedKeywordArgument): Identifier = kwarg.parsed.name
proc loc*(kwarg: ResolvedKeywordArgument): Location = kwarg.parsed.loc

# ---- ResolvedStructInitializer ----

proc newResolvedStructInitializer*(parsed: StructInitializer,
    structRef: ResolvedStructRef,
    kwargs: seq[ResolvedKeywordArgument]): ResolvedStructInitializer =
  ResolvedStructInitializer(parsed: parsed, structRef: structRef, kwargs: kwargs)

proc parsed*(struct: ResolvedStructInitializer): StructInitializer = struct.parsed
proc structRef*(struct: ResolvedStructInitializer): ResolvedStructRef = struct.structRef
proc kwargs*(struct: ResolvedStructInitializer): seq[ResolvedKeywordArgument] = struct.kwargs
proc loc*(struct: ResolvedStructInitializer): Location = struct.parsed.loc

# ---- ResolvedUnionInitializer ----

proc newResolvedUnionInitializer*(parsed: UnionInitializer,
    unionRef: ResolvedUnionRef,
    kwargs: seq[ResolvedKeywordArgument]): ResolvedUnionInitializer =
  ResolvedUnionInitializer(parsed: parsed, unionRef: unionRef, kwargs: kwargs)

proc parsed*(init: ResolvedUnionInitializer): UnionInitializer = init.parsed
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
    typ: parser.Type, args: seq[ResolvedExpression]): ResolvedFunctionCall =
  ResolvedFunctionCall(parsed: parsed, typ: typ, args: args)

proc parsed*(fncall: ResolvedFunctionCall): FunctionCall = fncall.parsed
proc typ*(fncall: ResolvedFunctionCall): parser.Type = fncall.typ
proc args*(fncall: ResolvedFunctionCall): seq[ResolvedExpression] = fncall.args
proc loc*(fncall: ResolvedFunctionCall): Location = fncall.parsed.loc

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

proc newResolvedAssignment*(parsed: Assignment,
    expression: ResolvedExpression): ResolvedAssignment =
  ResolvedAssignment(parsed: parsed, expression: expression)

proc parsed*(assignment: ResolvedAssignment): Assignment = assignment.parsed
proc expression*(assignment: ResolvedAssignment): ResolvedExpression = assignment.expression
proc loc*(assignment: ResolvedAssignment): Location = assignment.parsed.loc
proc target*(assignment: ResolvedAssignment): Identifier = assignment.parsed.target

# ---- ResolvedSetter ----

proc newResolvedSetter*(parsed: Setter, getter: ResolvedGetter,
    expression: ResolvedExpression): ResolvedSetter =
  ResolvedSetter(parsed: parsed, getter: getter, expression: expression)

proc parsed*(setter: ResolvedSetter): Setter = setter.parsed
proc getter*(setter: ResolvedSetter): ResolvedGetter = setter.getter
proc expression*(setter: ResolvedSetter): ResolvedExpression = setter.expression
proc loc*(setter: ResolvedSetter): Location = setter.parsed.loc

# ---- ResolvedCaseBlock ----

proc newResolvedCaseBlock*(parsed: CaseBlock, pattern: ResolvedCasePattern,
    statements: seq[ResolvedStatement]): ResolvedCaseBlock =
  ResolvedCaseBlock(parsed: parsed, pattern: pattern, statements: statements)

proc parsed*(caseBlock: ResolvedCaseBlock): CaseBlock = caseBlock.parsed
proc pattern*(caseBlock: ResolvedCaseBlock): ResolvedCasePattern = caseBlock.pattern
proc statements*(caseBlock: ResolvedCaseBlock): seq[ResolvedStatement] = caseBlock.statements
proc loc*(caseBlock: ResolvedCaseBlock): Location = caseBlock.parsed.loc

# ---- ResolvedMatchExpression ----

proc newResolvedMatchExpression*(parsed: MatchExpression,
    subject: ResolvedExpression,
    cases: seq[ResolvedCaseBlock]): ResolvedMatchExpression =
  ResolvedMatchExpression(parsed: parsed, subject: subject, cases: cases)

proc parsed*(match: ResolvedMatchExpression): MatchExpression = match.parsed
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
  ResolvedStatement(kind: rskAssignment, assignment: assignment)

proc newResolvedStatement*(expression: ResolvedExpression): ResolvedStatement =
  ResolvedStatement(kind: rskExpr, expression: expression)

proc newResolvedStatement*(setter: ResolvedSetter): ResolvedStatement =
  ResolvedStatement(kind: rskSetter, setter: setter)

proc kind*(statement: ResolvedStatement): ResolvedStatementKind = statement.kind
proc expression*(statement: ResolvedStatement): ResolvedExpression =
  assert statement.kind == rskExpr,
    fmt"ResolvedStatement.expression accessed but kind is {statement.kind}"
  statement.expression
proc assignment*(statement: ResolvedStatement): ResolvedAssignment =
  assert statement.kind == rskAssignment,
    fmt"ResolvedStatement.assignment accessed but kind is {statement.kind}"
  statement.assignment
proc setter*(statement: ResolvedStatement): ResolvedSetter =
  assert statement.kind == rskSetter,
    fmt"ResolvedStatement.setter accessed but kind is {statement.kind}"
  statement.setter
proc loc*(statement: ResolvedStatement): Location =
  case statement.kind:
  of rskAssignment: statement.assignment.loc
  of rskExpr: statement.expression.loc
  of rskSetter: statement.setter.loc

# Accessor used by callers to thread bindings into scope.
proc variable*(statement: ResolvedStatement): Option[Identifier] =
  ## Returns the new binding introduced by this statement (if any).
  case statement.kind:
  of rskAssignment: some(statement.assignment.target)
  of rskExpr: none(Identifier)
  of rskSetter: none(Identifier)
