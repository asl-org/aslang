## AnalyzedUnionPatternScope — accumulates variant coverage across the
## case blocks of a union-subject match so exhaustiveness can be
## checked after the walk. A trailing `variable`-pattern case is legal
## (and only legal) in the last block; other blocks must be variant
## patterns.

import results, sets, strformat

import ./resolver

type AnalyzedUnionPatternScope* = ref object
  variablePatternFound: bool
  totalCases: int
  variants: HashSet[Identifier]

proc newAnalyzedUnionPatternScope*(totalCases: int): AnalyzedUnionPatternScope =
  AnalyzedUnionPatternScope(variablePatternFound: false, totalCases: totalCases, variants: initHashSet[Identifier]())

proc update*(scope: AnalyzedUnionPatternScope, id: int, pattern: ResolvedCasePattern): Result[AnalyzedUnionPatternScope, string] =
  case pattern.kind:
  of rcpkInteger:
    err(fmt"{pattern.loc} expected a union variant but found integer literal")
  of rcpkVariable:
    if id != scope.totalCases - 1:
      err(fmt"{pattern.loc} variable pattern binding is supported only in the last case block")
    else:
      scope.variablePatternFound = true
      ok(scope)
  of rcpkUnion:
    if pattern.variant.name in scope.variants:
      err(fmt"{pattern.variant.loc} found duplicate variant `{pattern.variant.name.asl}`")
    else:
      scope.variants.incl(pattern.variant.name)
      ok(scope)

# NOTE: If there is no variable pattern in union matching then all branches must be covered
proc hasUncoveredCases*(scope: AnalyzedUnionPatternScope, totalVariants: int, loc: Location): Result[void, string] =
  # TODO: improve error message by showing the uncovered variants
  if scope.variablePatternFound:
    if scope.variants.len < totalVariants: ok()
    else: err(fmt"{loc} variable binding is invalid since all the variants are already covered by the case blocks")
  else:
    if scope.variants.len == totalVariants: ok()
    else: err(fmt"{loc} case blocks do not cover all the variants")
