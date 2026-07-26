## AnalyzedCasePattern — the tagged-union shape a case block's pattern
## can take: a union variant match, an integer literal match, or a
## trailing variable-binding (wildcard). Enum + variant type live
## together — one file for the whole tagged pair.

import ./defanalyzer
import binding
import unionpattern

type
  AnalyzedCasePatternKind* = enum
    acpkUnion, acpkInteger, acpkVariable
  AnalyzedCasePattern* = ref object
    case kind: AnalyzedCasePatternKind
    of acpkUnion: variant: AnalyzedUnionPattern
    of acpkInteger: integer: IntegerLiteral
    of acpkVariable: variable: AnalyzedBinding

proc newAnalyzedCasePattern*(variant: AnalyzedUnionPattern): AnalyzedCasePattern =
  AnalyzedCasePattern(kind: acpkUnion, variant: variant)

proc newAnalyzedCasePattern*(integer: IntegerLiteral): AnalyzedCasePattern =
  AnalyzedCasePattern(kind: acpkInteger, integer: integer)

proc newAnalyzedCasePattern*(variable: AnalyzedBinding): AnalyzedCasePattern =
  AnalyzedCasePattern(kind: acpkVariable, variable: variable)

proc bindings*(pattern: AnalyzedCasePattern): seq[AnalyzedBinding] =
  case pattern.kind:
  of acpkUnion: pattern.variant.bindings
  of acpkVariable: @[pattern.variable]
  of acpkInteger: newSeq[AnalyzedBinding]()
