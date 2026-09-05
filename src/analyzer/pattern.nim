## Analyzed pattern cluster — the case-pattern shapes and their scopes:
## AnalyzedBinding (a name+type a pattern/assignment introduces),
## AnalyzedUnionPattern (a variant match + its field bindings),
## AnalyzedCasePattern (union | integer | variable), and the two
## exhaustiveness/duplicate scopes that accumulate coverage across a
## match's case blocks (union-subject and literal-subject).

import results, sets, strformat, options

import ../defanalyzer/index as defanalyzer

# ============================================================
# AnalyzedBinding
# ============================================================
# The (name, argType) pair a binding introduces (a case pattern's
# variable, an assignment's target). The generic bindings a later match
# needs are intrinsic to `argType` (every module argtype carries its
# slot→impl map), so no separate map rides on the binding.

# ---- AnalyzedVariable (identifier bound to an argtype via scope) ----

type AnalyzedVariable* = ref object
  name: Identifier
  argType: AnalyzedArgumentType

proc newAnalyzedVariable*(name: Identifier, argType: AnalyzedArgumentType): AnalyzedVariable =
  AnalyzedVariable(name: name, argType: argType)

proc loc*(variable: AnalyzedVariable): Location = variable.name.loc
proc name*(variable: AnalyzedVariable): Identifier = variable.name
proc argType*(variable: AnalyzedVariable): AnalyzedArgumentType = variable.argType

type AnalyzedVariantField* = ref object
  name: Identifier
  field: AnalyzedArgumentDef
  impls: AnalyzedImplMap

proc newAnalyzedVariantField*(name: Identifier, field: AnalyzedArgumentDef, impls: AnalyzedImplMap): AnalyzedVariantField =
  AnalyzedVariantField(name: name, field: field, impls: impls)

proc name*(variantField: AnalyzedVariantField): Identifier = variantField.name
proc field*(variantField: AnalyzedVariantField): AnalyzedArgumentDef = variantField.field
proc argType*(variantField: AnalyzedVariantField): AnalyzedArgumentType = variantField.field.argType.concrete(variantField.impls)
# proc baseArgType*(variantField: AnalyzedVariantField): AnalyzedArgumentType = variantField.field.argType

type
  AnalyzedBindingKind* = enum
    abkVariantField, abkVariable
  AnalyzedBinding* = ref object
    case kind: AnalyzedBindingKind
    of abkVariantField: variantField: AnalyzedVariantField
    of abkVariable: variable: AnalyzedVariable

proc newAnalyzedBinding*(name: Identifier, argType: AnalyzedArgumentType): AnalyzedBinding =
  let variable = newAnalyzedVariable(name, argType)
  AnalyzedBinding(kind: abkVariable, variable: variable)

proc newAnalyzedBinding*(name: Identifier, field: AnalyzedArgumentDef, impls: AnalyzedImplMap): AnalyzedBinding =
  let variantField = newAnalyzedVariantField(name, field, impls)
  AnalyzedBinding(kind: abkVariantField, variantField: variantField)

proc kind*(binding: AnalyzedBinding): AnalyzedBindingKind = binding.kind
proc variable*(binding: AnalyzedBinding): AnalyzedVariable =
  assert binding.kind == abkVariable,
    fmt"AnalyzedBinding.variable accessed but kind is {binding.kind}"
  binding.variable
proc variantField*(binding: AnalyzedBinding): AnalyzedVariantField =
  assert binding.kind == abkVariantField,
    fmt"AnalyzedBinding.variantField accessed but kind is {binding.kind}"
  binding.variantField

proc name*(binding: AnalyzedBinding): Identifier =
  case binding.kind:
  of abkVariable: binding.variable.name
  of abkVariantField: binding.variantField.name

proc argType*(binding: AnalyzedBinding): AnalyzedArgumentType =
  case binding.kind:
  of abkVariable: binding.variable.argType
  of abkVariantField: binding.variantField.argType

# proc baseArgType*(binding: AnalyzedBinding): AnalyzedArgumentType =
#   case binding.kind:
#   of abkVariable: binding.variable.argType
#   of abkVariantField: binding.variantField.baseArgType

# ============================================================
# AnalyzedUnionPattern
# ============================================================
# A resolved union-variant pattern + the bindings its fields introduce.

type AnalyzedUnionPattern* = ref object
  resolved: UnionPattern
  variant: AnalyzedVariantDef
  bindings: seq[AnalyzedBinding]

proc newAnalyzedUnionPattern*(resolved: UnionPattern, variant: AnalyzedVariantDef, bindings: seq[AnalyzedBinding]): AnalyzedUnionPattern =
  AnalyzedUnionPattern(resolved: resolved, variant: variant, bindings: bindings)

proc bindings*(pattern: AnalyzedUnionPattern): seq[AnalyzedBinding] = pattern.bindings
proc variant*(pattern: AnalyzedUnionPattern): AnalyzedVariantDef = pattern.variant

# ============================================================
# AnalyzedCasePattern
# ============================================================
# The tagged-union shape a case block's pattern can take: a union
# variant match, an integer literal match, or a trailing variable
# binding (wildcard).

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

proc kind*(pattern: AnalyzedCasePattern): AnalyzedCasePatternKind = pattern.kind
proc variant*(pattern: AnalyzedCasePattern): AnalyzedUnionPattern =
  assert pattern.kind == acpkUnion,
    fmt"AnalyzedCasePattern.variant accessed but kind is {pattern.kind}"
  pattern.variant
proc integer*(pattern: AnalyzedCasePattern): IntegerLiteral =
  assert pattern.kind == acpkInteger,
    fmt"AnalyzedCasePattern.integer accessed but kind is {pattern.kind}"
  pattern.integer
proc variable*(pattern: AnalyzedCasePattern): AnalyzedBinding =
  assert pattern.kind == acpkVariable,
    fmt"AnalyzedCasePattern.variable accessed but kind is {pattern.kind}"
  pattern.variable

proc bindings*(pattern: AnalyzedCasePattern): seq[AnalyzedBinding] =
  case pattern.kind:
  of acpkUnion: pattern.variant.bindings
  of acpkVariable: @[pattern.variable]
  of acpkInteger: newSeq[AnalyzedBinding]()

# ============================================================
# AnalyzedUnionPatternScope
# ============================================================
# Accumulates variant coverage across the case blocks of a
# union-subject match so exhaustiveness can be checked after the walk.
# A trailing `variable`-pattern case is legal (and only legal) in the
# last block; other blocks must be variant patterns.

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

# ============================================================
# AnalyzedLiteralPatternScope
# ============================================================
# Per-integer-kind duplicate-value check across the case blocks of a
# literal-subject match. Float / string / pointer subjects are rejected
# at construction time.

type
  AnalyzedLiteralPatternScopeKind* = enum
    alpskU8, alpskU16, alpskU32, alpskU64,
    alpskI8, alpskI16, alpskI32, alpskI64
  AnalyzedLiteralPatternScope* = ref object
    totalCases: int
    variablePatternFound: bool
    case kind: AnalyzedLiteralPatternScopeKind
    of alpskU8: u8Values:  HashSet[uint8]
    of alpskU16: u16Values: HashSet[uint16]
    of alpskU32: u32Values: HashSet[uint32]
    of alpskU64: u64Values: HashSet[uint64]
    of alpskI8: i8Values:  HashSet[int8]
    of alpskI16: i16Values: HashSet[int16]
    of alpskI32: i32Values: HashSet[int32]
    of alpskI64: i64Values: HashSet[int64]

proc newAnalyzedLiteralPatternScope*(literal: AnalyzedLiteralDef, totalCases: int): Result[AnalyzedLiteralPatternScope, string] =
  case literal.resolved.kind:
  of rltkU8: ok(AnalyzedLiteralPatternScope(kind: alpskU8,  totalCases: totalCases, variablePatternFound: false, u8Values:  initHashSet[uint8]()))
  of rltkU16: ok(AnalyzedLiteralPatternScope(kind: alpskU16, totalCases: totalCases, variablePatternFound: false, u16Values: initHashSet[uint16]()))
  of rltkU32: ok(AnalyzedLiteralPatternScope(kind: alpskU32, totalCases: totalCases, variablePatternFound: false, u32Values: initHashSet[uint32]()))
  of rltkU64: ok(AnalyzedLiteralPatternScope(kind: alpskU64, totalCases: totalCases, variablePatternFound: false, u64Values: initHashSet[uint64]()))
  of rltkI8: ok(AnalyzedLiteralPatternScope(kind: alpskI8,  totalCases: totalCases, variablePatternFound: false, i8Values:  initHashSet[int8]()))
  of rltkI16: ok(AnalyzedLiteralPatternScope(kind: alpskI16, totalCases: totalCases, variablePatternFound: false, i16Values: initHashSet[int16]()))
  of rltkI32: ok(AnalyzedLiteralPatternScope(kind: alpskI32, totalCases: totalCases, variablePatternFound: false, i32Values: initHashSet[int32]()))
  of rltkI64: ok(AnalyzedLiteralPatternScope(kind: alpskI64, totalCases: totalCases, variablePatternFound: false, i64Values: initHashSet[int64]()))
  of rltkF32: err("match block does not support f32 values in case patterns")
  of rltkF64: err("match block does not support f64 values in case patterns")
  of rltkString: err("match block does not support string values in case patterns")

proc checkDuplicate[T: SomeInteger](values: var HashSet[T], integer: IntegerLiteral, expected: string): Result[void, string] =
  let maybeInt = parseInteger[T](integer.asl)
  if maybeInt.isNone:
    err(fmt"{integer.loc} expected value to be a valid {expected}")
  elif maybeInt.get in values:
    err(fmt"{integer.loc} duplicated integer pattern encountered")
  else:
    values.incl(maybeInt.get)
    ok()

proc checkDuplicate(scope: AnalyzedLiteralPatternScope, integer: IntegerLiteral): Result[AnalyzedLiteralPatternScope, string] =
  case scope.kind:
  of alpskU8: ? checkDuplicate[uint8](scope.u8Values, integer, "valid 8-bit unsigned integer")
  of alpskU16: ? checkDuplicate[uint16](scope.u16Values, integer, "valid 16-bit unsigned integer")
  of alpskU32: ? checkDuplicate[uint32](scope.u32Values, integer, "valid 32-bit unsigned integer")
  of alpskU64: ? checkDuplicate[uint64](scope.u64Values, integer, "valid 64-bit unsigned integer")
  of alpskI8: ? checkDuplicate[int8](scope.i8Values, integer, "valid 8-bit signed integer")
  of alpskI16: ? checkDuplicate[int16](scope.i16Values, integer, "valid 16-bit signed integer")
  of alpskI32: ? checkDuplicate[int32](scope.i32Values, integer, "valid 32-bit signed integer")
  of alpskI64: ? checkDuplicate[int64](scope.i64Values, integer, "valid 64-bit signed integer")
  ok(scope)

proc update*(scope: AnalyzedLiteralPatternScope, id: int, pattern: ResolvedCasePattern): Result[AnalyzedLiteralPatternScope, string] =
  case pattern.kind:
  of rcpkUnion:
    err(fmt"{pattern.loc} expected a literal pattern but found variant pattern")
  of rcpkVariable:
    if id != scope.totalCases - 1:
      err(fmt"{pattern.loc} variable pattern binding is supported only in the last case block")
    else:
      scope.variablePatternFound = true
      ok(scope)
  of rcpkInteger:
    scope.checkDuplicate(pattern.integer)

# NOTE: If there is no variable pattern in union matching then all branches must be covered
proc hasUncoveredCases*(scope: AnalyzedLiteralPatternScope, loc: Location): Result[void, string] =
  # TODO: improve error message by showing the uncovered variants
  if scope.variablePatternFound: ok()
  else: err(fmt"{loc} variable case pattern binding is required for integer literal pattern")
