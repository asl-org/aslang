## Phase-A statement tree — the `AnalyzedDef*` twin of the resolver's
## statement cluster (literal → kwarg → fncall → initializer → match →
## expression → assignment/setter → statement), one mutually-recursive
## type block mirroring the resolver shapes 1:1. Each node pairs the
## resolved original with its def-level bindings re-derived from the
## file scope. Built by the `analyzeDef*` body walk on the defanalyzer
## barrel; consumed by phase B.

import strformat

import resolver
import argtype
import structref
import unionref

type
  AnalyzedDefLiteral* = ref object
    resolved: ResolvedLiteral
    default: ResolvedModule
    def: ResolvedLiteralDef

  AnalyzedDefKeywordArgument* = ref object
    resolved: ResolvedKeywordArgument
    expression: AnalyzedDefExpression

  AnalyzedDefFunctionCall* = ref object
    resolved: ResolvedFunctionCall
    # typ stays ResolvedLocalType, not AnalyzedLocalType: the analyzed
    # module/generic bundles contain functions, which contain
    # statements, which contain calls — an AnalyzedLocalType receiver
    # would close that cycle and force every type into a single file.
    typ: ResolvedLocalType
    args: seq[AnalyzedDefExpression]

  AnalyzedDefLiteralInitializer* = ref object
    resolved: ResolvedLiteralInitializer
    argType: AnalyzedModuleArgumentType
    def: ResolvedLiteralDef

  AnalyzedDefStructInitializer* = ref object
    resolved: ResolvedStructInitializer
    structRef: AnalyzedDefStructRef
    kwargs: seq[AnalyzedDefKeywordArgument]

  AnalyzedDefUnionInitializer* = ref object
    resolved: ResolvedUnionInitializer
    unionRef: AnalyzedDefUnionRef
    kwargs: seq[AnalyzedDefKeywordArgument]

  AnalyzedDefInitializerKind* = enum
    adikLiteral, adikStruct, adikUnion
  AnalyzedDefInitializer* = ref object
    case kind: AnalyzedDefInitializerKind
    of adikLiteral: literal: AnalyzedDefLiteralInitializer
    of adikStruct: struct: AnalyzedDefStructInitializer
    of adikUnion: union: AnalyzedDefUnionInitializer

  AnalyzedDefCase* = ref object
    resolved: ResolvedCaseBlock
    statements: seq[AnalyzedDefStatement]

  AnalyzedDefMatch* = ref object
    resolved: ResolvedMatchExpression
    subject: AnalyzedDefExpression
    cases: seq[AnalyzedDefCase]

  AnalyzedDefExpressionKind* = enum
    adekVariable, adekGetter, adekFunctionCall, adekInitializer, adekLiteral, adekMatchExpr
  AnalyzedDefExpression* = ref object
    case kind: AnalyzedDefExpressionKind
    of adekLiteral: literal: AnalyzedDefLiteral
    of adekVariable: variable: Identifier
    of adekGetter: getter: ResolvedGetter
    of adekFunctionCall: fncall: AnalyzedDefFunctionCall
    of adekInitializer: init: AnalyzedDefInitializer
    of adekMatchExpr: match: AnalyzedDefMatch

  AnalyzedDefAssignment* = ref object
    resolved: ResolvedAssignment
    expression: AnalyzedDefExpression

  AnalyzedDefSetter* = ref object
    resolved: ResolvedSetter
    expression: AnalyzedDefExpression

  AnalyzedDefStatementKind* = enum
    adskAssignment, adskExpr, adskSetter
  AnalyzedDefStatement* = ref object
    case kind: AnalyzedDefStatementKind
    of adskAssignment: assignment: AnalyzedDefAssignment
    of adskExpr: expression: AnalyzedDefExpression
    of adskSetter: setter: AnalyzedDefSetter

# AnalyzedDefLiteral
proc newAnalyzedDefLiteral*(resolved: ResolvedLiteral, default: ResolvedModule, def: ResolvedLiteralDef): AnalyzedDefLiteral =
  AnalyzedDefLiteral(resolved: resolved, default: default, def: def)

proc loc*(literal: AnalyzedDefLiteral): Location = literal.resolved.loc
proc value*(literal: AnalyzedDefLiteral): Literal = literal.resolved.value
proc resolved*(literal: AnalyzedDefLiteral): ResolvedLiteral = literal.resolved
proc default*(literal: AnalyzedDefLiteral): ResolvedModule = literal.default

# AnalyzedDefLiteralInitializer
proc newAnalyzedDefLiteralInitializer*(resolved: ResolvedLiteralInitializer, argType: AnalyzedModuleArgumentType, def: ResolvedLiteralDef): AnalyzedDefLiteralInitializer =
  AnalyzedDefLiteralInitializer(resolved: resolved, argType: argType, def: def)

proc loc*(init: AnalyzedDefLiteralInitializer): Location = init.resolved.loc
proc resolved*(init: AnalyzedDefLiteralInitializer): ResolvedLiteralInitializer = init.resolved
proc argType*(init: AnalyzedDefLiteralInitializer): AnalyzedModuleArgumentType = init.argType

# AnalyzedDefKeywordArgument
proc newAnalyzedDefKeywordArgument*(resolved: ResolvedKeywordArgument, expression: AnalyzedDefExpression): AnalyzedDefKeywordArgument =
  AnalyzedDefKeywordArgument(resolved: resolved, expression: expression)

proc name*(kwarg: AnalyzedDefKeywordArgument): Identifier = kwarg.resolved.name
proc resolved*(kwarg: AnalyzedDefKeywordArgument): ResolvedKeywordArgument = kwarg.resolved
proc expression*(kwarg: AnalyzedDefKeywordArgument): AnalyzedDefExpression = kwarg.expression

# AnalyzedDefStructInitializer
proc newAnalyzedDefStructInitializer*(resolved: ResolvedStructInitializer, structRef: AnalyzedDefStructRef, kwargs: seq[AnalyzedDefKeywordArgument]): AnalyzedDefStructInitializer =
  AnalyzedDefStructInitializer(resolved: resolved, structRef: structRef, kwargs: kwargs)

proc loc*(init: AnalyzedDefStructInitializer): Location = init.resolved.loc
proc resolved*(init: AnalyzedDefStructInitializer): ResolvedStructInitializer = init.resolved
proc structRef*(init: AnalyzedDefStructInitializer): AnalyzedDefStructRef = init.structRef
proc kwargs*(init: AnalyzedDefStructInitializer): seq[AnalyzedDefKeywordArgument] = init.kwargs

# AnalyzedDefUnionInitializer
proc newAnalyzedDefUnionInitializer*(resolved: ResolvedUnionInitializer, unionRef: AnalyzedDefUnionRef, kwargs: seq[AnalyzedDefKeywordArgument]): AnalyzedDefUnionInitializer =
  AnalyzedDefUnionInitializer(resolved: resolved, unionRef: unionRef, kwargs: kwargs)

proc loc*(init: AnalyzedDefUnionInitializer): Location = init.resolved.loc
proc resolved*(init: AnalyzedDefUnionInitializer): ResolvedUnionInitializer = init.resolved
proc unionRef*(init: AnalyzedDefUnionInitializer): AnalyzedDefUnionRef = init.unionRef
proc kwargs*(init: AnalyzedDefUnionInitializer): seq[AnalyzedDefKeywordArgument] = init.kwargs

# AnalyzedDefInitializer
proc newAnalyzedDefInitializer*(literal: AnalyzedDefLiteralInitializer): AnalyzedDefInitializer =
  AnalyzedDefInitializer(kind: adikLiteral, literal: literal)

proc newAnalyzedDefInitializer*(struct: AnalyzedDefStructInitializer): AnalyzedDefInitializer =
  AnalyzedDefInitializer(kind: adikStruct, struct: struct)

proc newAnalyzedDefInitializer*(union: AnalyzedDefUnionInitializer): AnalyzedDefInitializer =
  AnalyzedDefInitializer(kind: adikUnion, union: union)

proc kind*(init: AnalyzedDefInitializer): AnalyzedDefInitializerKind = init.kind
proc literal*(init: AnalyzedDefInitializer): AnalyzedDefLiteralInitializer =
  assert init.kind == adikLiteral,
    fmt"AnalyzedDefInitializer.literal accessed but kind is {init.kind}"
  init.literal
proc union*(init: AnalyzedDefInitializer): AnalyzedDefUnionInitializer =
  assert init.kind == adikUnion,
    fmt"AnalyzedDefInitializer.union accessed but kind is {init.kind}"
  init.union
proc struct*(init: AnalyzedDefInitializer): AnalyzedDefStructInitializer =
  assert init.kind == adikStruct,
    fmt"AnalyzedDefInitializer.struct accessed but kind is {init.kind}"
  init.struct

proc loc*(init: AnalyzedDefInitializer): Location =
  case init.kind
  of adikLiteral: init.literal.loc
  of adikStruct: init.struct.loc
  of adikUnion: init.union.loc

# AnalyzedDefFunctionCall
proc newAnalyzedDefFunctionCall*(resolved: ResolvedFunctionCall, typ: ResolvedLocalType, args: seq[AnalyzedDefExpression]): AnalyzedDefFunctionCall =
  AnalyzedDefFunctionCall(resolved: resolved, typ: typ, args: args)

proc loc*(fncall: AnalyzedDefFunctionCall): Location = fncall.resolved.loc
proc name*(fncall: AnalyzedDefFunctionCall): Identifier = fncall.resolved.name
proc arity*(fncall: AnalyzedDefFunctionCall): int = fncall.resolved.arity
proc resolved*(fncall: AnalyzedDefFunctionCall): ResolvedFunctionCall = fncall.resolved
proc typ*(fncall: AnalyzedDefFunctionCall): ResolvedLocalType = fncall.typ
proc args*(fncall: AnalyzedDefFunctionCall): seq[AnalyzedDefExpression] = fncall.args

# AnalyzedDefCase
proc newAnalyzedDefCase*(resolved: ResolvedCaseBlock, statements: seq[AnalyzedDefStatement]): AnalyzedDefCase =
  AnalyzedDefCase(resolved: resolved, statements: statements)

proc loc*(caseBlock: AnalyzedDefCase): Location = caseBlock.resolved.loc
# The pattern stays at the resolved level — validating a union
# pattern's variant/field names needs the match subject's union type,
# which only phase B computes (`analyzeUnionCasePattern` on the body
# barrel owns that check).
proc pattern*(caseBlock: AnalyzedDefCase): ResolvedCasePattern = caseBlock.resolved.pattern
proc resolved*(caseBlock: AnalyzedDefCase): ResolvedCaseBlock = caseBlock.resolved
proc statements*(caseBlock: AnalyzedDefCase): seq[AnalyzedDefStatement] = caseBlock.statements

# AnalyzedDefMatch
proc newAnalyzedDefMatch*(resolved: ResolvedMatchExpression, subject: AnalyzedDefExpression, cases: seq[AnalyzedDefCase]): AnalyzedDefMatch =
  AnalyzedDefMatch(resolved: resolved, subject: subject, cases: cases)

proc loc*(match: AnalyzedDefMatch): Location = match.resolved.loc
proc resolved*(match: AnalyzedDefMatch): ResolvedMatchExpression = match.resolved
proc subject*(match: AnalyzedDefMatch): AnalyzedDefExpression = match.subject
proc cases*(match: AnalyzedDefMatch): seq[AnalyzedDefCase] = match.cases

# AnalyzedDefExpression
proc newAnalyzedDefExpression*(literal: AnalyzedDefLiteral): AnalyzedDefExpression =
  AnalyzedDefExpression(kind: adekLiteral, literal: literal)

proc newAnalyzedDefExpression*(variable: Identifier): AnalyzedDefExpression =
  AnalyzedDefExpression(kind: adekVariable, variable: variable)

proc newAnalyzedDefExpression*(getter: ResolvedGetter): AnalyzedDefExpression =
  AnalyzedDefExpression(kind: adekGetter, getter: getter)

proc newAnalyzedDefExpression*(fncall: AnalyzedDefFunctionCall): AnalyzedDefExpression =
  AnalyzedDefExpression(kind: adekFunctionCall, fncall: fncall)

proc newAnalyzedDefExpression*(init: AnalyzedDefInitializer): AnalyzedDefExpression =
  AnalyzedDefExpression(kind: adekInitializer, init: init)

proc newAnalyzedDefExpression*(match: AnalyzedDefMatch): AnalyzedDefExpression =
  AnalyzedDefExpression(kind: adekMatchExpr, match: match)

proc kind*(expression: AnalyzedDefExpression): AnalyzedDefExpressionKind = expression.kind
proc fncall*(expression: AnalyzedDefExpression): AnalyzedDefFunctionCall =
  assert expression.kind == adekFunctionCall,
    fmt"AnalyzedDefExpression.fncall accessed but kind is {expression.kind}"
  expression.fncall
proc variable*(expression: AnalyzedDefExpression): Identifier =
  assert expression.kind == adekVariable,
    fmt"AnalyzedDefExpression.variable accessed but kind is {expression.kind}"
  expression.variable
proc literal*(expression: AnalyzedDefExpression): AnalyzedDefLiteral =
  assert expression.kind == adekLiteral,
    fmt"AnalyzedDefExpression.literal accessed but kind is {expression.kind}"
  expression.literal
proc match*(expression: AnalyzedDefExpression): AnalyzedDefMatch =
  assert expression.kind == adekMatchExpr,
    fmt"AnalyzedDefExpression.match accessed but kind is {expression.kind}"
  expression.match
proc init*(expression: AnalyzedDefExpression): AnalyzedDefInitializer =
  assert expression.kind == adekInitializer,
    fmt"AnalyzedDefExpression.init accessed but kind is {expression.kind}"
  expression.init
proc getter*(expression: AnalyzedDefExpression): ResolvedGetter =
  assert expression.kind == adekGetter,
    fmt"AnalyzedDefExpression.getter accessed but kind is {expression.kind}"
  expression.getter

proc loc*(expression: AnalyzedDefExpression): Location =
  case expression.kind
  of adekLiteral: expression.literal.loc
  of adekVariable: expression.variable.loc
  of adekGetter: expression.getter.loc
  of adekFunctionCall: expression.fncall.loc
  of adekInitializer: expression.init.loc
  of adekMatchExpr: expression.match.loc

# AnalyzedDefAssignment
proc newAnalyzedDefAssignment*(resolved: ResolvedAssignment, expression: AnalyzedDefExpression): AnalyzedDefAssignment =
  AnalyzedDefAssignment(resolved: resolved, expression: expression)

proc loc*(assignment: AnalyzedDefAssignment): Location = assignment.resolved.loc
proc target*(assignment: AnalyzedDefAssignment): Identifier = assignment.resolved.target
proc resolved*(assignment: AnalyzedDefAssignment): ResolvedAssignment = assignment.resolved
proc expression*(assignment: AnalyzedDefAssignment): AnalyzedDefExpression = assignment.expression

# AnalyzedDefSetter
proc newAnalyzedDefSetter*(resolved: ResolvedSetter, expression: AnalyzedDefExpression): AnalyzedDefSetter =
  AnalyzedDefSetter(resolved: resolved, expression: expression)

proc loc*(setter: AnalyzedDefSetter): Location = setter.resolved.loc
proc getter*(setter: AnalyzedDefSetter): ResolvedGetter = setter.resolved.getter
proc resolved*(setter: AnalyzedDefSetter): ResolvedSetter = setter.resolved
proc expression*(setter: AnalyzedDefSetter): AnalyzedDefExpression = setter.expression

# AnalyzedDefStatement
proc newAnalyzedDefStatement*(assignment: AnalyzedDefAssignment): AnalyzedDefStatement =
  AnalyzedDefStatement(kind: adskAssignment, assignment: assignment)

proc newAnalyzedDefStatement*(expression: AnalyzedDefExpression): AnalyzedDefStatement =
  AnalyzedDefStatement(kind: adskExpr, expression: expression)

proc newAnalyzedDefStatement*(setter: AnalyzedDefSetter): AnalyzedDefStatement =
  AnalyzedDefStatement(kind: adskSetter, setter: setter)

proc kind*(statement: AnalyzedDefStatement): AnalyzedDefStatementKind = statement.kind
proc expression*(statement: AnalyzedDefStatement): AnalyzedDefExpression =
  assert statement.kind == adskExpr,
    fmt"AnalyzedDefStatement.expression accessed but kind is {statement.kind}"
  statement.expression
proc assignment*(statement: AnalyzedDefStatement): AnalyzedDefAssignment =
  assert statement.kind == adskAssignment,
    fmt"AnalyzedDefStatement.assignment accessed but kind is {statement.kind}"
  statement.assignment
proc setter*(statement: AnalyzedDefStatement): AnalyzedDefSetter =
  assert statement.kind == adskSetter,
    fmt"AnalyzedDefStatement.setter accessed but kind is {statement.kind}"
  statement.setter

proc loc*(statement: AnalyzedDefStatement): Location =
  case statement.kind:
  of adskAssignment: statement.assignment.loc
  of adskExpr: statement.expression.loc
  of adskSetter: statement.setter.loc