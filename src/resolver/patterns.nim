## Pattern-level resolution: ResolvedCasePattern.
##
## Independent of the body cluster — pattern fields are parser AST
## types (IntegerLiteral / Identifier / UnionPattern).

import results, strformat

import tokenizer
import parser

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

proc resolveCasePattern*(casePattern: CasePattern): Result[
    ResolvedCasePattern, string] =
  case casePattern.kind:
  of cpkIntegerLiteral:
    ok(newResolvedCasePattern(casePattern.intLit))
  of cpkVariable:
    ok(newResolvedCasePattern(casePattern.variable))
  of cpkUnion:
    ok(newResolvedCasePattern(casePattern.variant))
