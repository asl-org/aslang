## Pattern-level resolution: ResolvedCasePattern.
##
## Independent of the body cluster — pattern fields are parser AST
## types (IntegerLiteral / Identifier / VariantPattern).

import results

import parser

type
  ResolvedCasePatternKind* = enum
    rcpkInteger, rcpkVariable, rcpkVariant
  ResolvedCasePattern* = ref object
    case kind: ResolvedCasePatternKind
    of rcpkInteger: integer: IntegerLiteral
    of rcpkVariable: variable: Identifier
    of rcpkVariant: variant: VariantPattern

proc newResolvedCasePattern*(integer: IntegerLiteral): ResolvedCasePattern =
  ResolvedCasePattern(kind: rcpkInteger, integer: integer)

proc newResolvedCasePattern*(variable: Identifier): ResolvedCasePattern =
  ResolvedCasePattern(kind: rcpkVariable, variable: variable)

proc newResolvedCasePattern*(variant: VariantPattern): ResolvedCasePattern =
  ResolvedCasePattern(kind: rcpkVariant, variant: variant)

proc resolveCasePattern*(casePattern: CasePattern): Result[
    ResolvedCasePattern, string] =
  case casePattern.kind:
  of cpkIntegerLiteral:
    ok(newResolvedCasePattern(casePattern.intLit))
  of cpkVariable:
    ok(newResolvedCasePattern(casePattern.variable))
  of cpkVariant:
    ok(newResolvedCasePattern(casePattern.variant))
