## Phase-A statement tree — the `AnalyzedDef*` twin of the resolver's
## statement cluster (literal → kwarg → fncall → initializer → match →
## expression → assignment/setter → statement), one mutually-recursive
## type block mirroring the resolver shapes 1:1. Each node pairs the
## resolved original with its def-level bindings re-derived from the
## file scope. Built by the `analyzeDef*` body walk on the defanalyzer
## barrel; consumed by phase B.

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
    # typ stays ResolvedType, not AnalyzedType: the analyzed
    # module/generic bundles contain functions, which contain
    # statements, which contain calls — an AnalyzedType receiver
    # would close that cycle and force every type into a single file.
    typ: ResolvedType
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

# AnalyzedDefLiteralInitializer
proc newAnalyzedDefLiteralInitializer*(resolved: ResolvedLiteralInitializer, argType: AnalyzedModuleArgumentType, def: ResolvedLiteralDef): AnalyzedDefLiteralInitializer =
  AnalyzedDefLiteralInitializer(resolved: resolved, argType: argType, def: def)

# AnalyzedDefKeywordArgument
proc newAnalyzedDefKeywordArgument*(resolved: ResolvedKeywordArgument, expression: AnalyzedDefExpression): AnalyzedDefKeywordArgument =
  AnalyzedDefKeywordArgument(resolved: resolved, expression: expression)

# AnalyzedDefStructInitializer
proc newAnalyzedDefStructInitializer*(resolved: ResolvedStructInitializer, structRef: AnalyzedDefStructRef, kwargs: seq[AnalyzedDefKeywordArgument]): AnalyzedDefStructInitializer =
  AnalyzedDefStructInitializer(resolved: resolved, structRef: structRef, kwargs: kwargs)

# AnalyzedDefUnionInitializer
proc newAnalyzedDefUnionInitializer*(resolved: ResolvedUnionInitializer, unionRef: AnalyzedDefUnionRef, kwargs: seq[AnalyzedDefKeywordArgument]): AnalyzedDefUnionInitializer =
  AnalyzedDefUnionInitializer(resolved: resolved, unionRef: unionRef, kwargs: kwargs)

# AnalyzedDefInitializer
proc newAnalyzedDefInitializer*(literal: AnalyzedDefLiteralInitializer): AnalyzedDefInitializer =
  AnalyzedDefInitializer(kind: adikLiteral, literal: literal)

proc newAnalyzedDefInitializer*(struct: AnalyzedDefStructInitializer): AnalyzedDefInitializer =
  AnalyzedDefInitializer(kind: adikStruct, struct: struct)

proc newAnalyzedDefInitializer*(union: AnalyzedDefUnionInitializer): AnalyzedDefInitializer =
  AnalyzedDefInitializer(kind: adikUnion, union: union)

# AnalyzedDefFunctionCall
proc newAnalyzedDefFunctionCall*(resolved: ResolvedFunctionCall, typ: ResolvedType, args: seq[AnalyzedDefExpression]): AnalyzedDefFunctionCall =
  AnalyzedDefFunctionCall(resolved: resolved, typ: typ, args: args)

# AnalyzedDefCase
proc newAnalyzedDefCase*(resolved: ResolvedCaseBlock, statements: seq[AnalyzedDefStatement]): AnalyzedDefCase =
  AnalyzedDefCase(resolved: resolved, statements: statements)

proc loc*(caseBlock: AnalyzedDefCase): Location = caseBlock.resolved.loc
# The pattern stays at the resolved level — validating a union
# pattern's variant/field names needs the match subject's union type,
# which only phase B computes (`analyzeUnionCasePattern` on the body
# barrel owns that check).
proc pattern*(caseBlock: AnalyzedDefCase): ResolvedCasePattern = caseBlock.resolved.pattern
proc statements*(caseBlock: AnalyzedDefCase): seq[AnalyzedDefStatement] = caseBlock.statements

# AnalyzedDefMatch
proc newAnalyzedDefMatch*(resolved: ResolvedMatchExpression, subject: AnalyzedDefExpression, cases: seq[AnalyzedDefCase]): AnalyzedDefMatch =
  AnalyzedDefMatch(resolved: resolved, subject: subject, cases: cases)

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

# AnalyzedDefAssignment
proc newAnalyzedDefAssignment*(resolved: ResolvedAssignment, expression: AnalyzedDefExpression): AnalyzedDefAssignment =
  AnalyzedDefAssignment(resolved: resolved, expression: expression)

# AnalyzedDefSetter
proc newAnalyzedDefSetter*(resolved: ResolvedSetter, expression: AnalyzedDefExpression): AnalyzedDefSetter =
  AnalyzedDefSetter(resolved: resolved, expression: expression)

# AnalyzedDefStatement
proc newAnalyzedDefStatement*(assignment: AnalyzedDefAssignment): AnalyzedDefStatement =
  AnalyzedDefStatement(kind: adskAssignment, assignment: assignment)

proc newAnalyzedDefStatement*(expression: AnalyzedDefExpression): AnalyzedDefStatement =
  AnalyzedDefStatement(kind: adskExpr, expression: expression)

proc newAnalyzedDefStatement*(setter: AnalyzedDefSetter): AnalyzedDefStatement =
  AnalyzedDefStatement(kind: adskSetter, setter: setter)
