## AnalyzedLiteralPatternScope — per-integer-kind duplicate-value check
## across the case blocks of a literal-subject match. Float / string /
## pointer subjects are rejected at construction time (see comments in
## the constructor). The Kind enum lives with the variant type — one
## file for the whole tagged pair.

import results, sets, strformat, options

import ./defanalyzer
import literalparse

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
  case literal.resolved:
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
  of rltkPointer: err("match block does not support pointer values in case patterns")

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
