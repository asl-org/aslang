## Pattern-level analysis: AnalyzedCasePattern plus the
## variant/literal pattern scopes used for exhaustiveness checking.
##
## Independent of the body cluster — the pattern's payload is either
## a parser IntegerLiteral (for literal subjects) or a resolved
## variant pattern (for union subjects). Body-level callers compose
## these via `analyzeCasePattern` / `update` / `hasUncoveredCases`.

import results, sets, strformat, options, sequtils, strscans, parseutils, strutils, math

import tokenizer
import parser
import resolver
import argtypes
import funcdefs
import data
import funcrefs

proc genericIntScanner*[T: SomeInteger](input: string, res: var T, start: int): int =
  # 1. Compile-time branching based on whether T is signed or unsigned
  when T is SomeUnsignedInt:
    var temp: BiggestUInt
    let charsParsed = parseBiggestUInt(input, temp, start)

    # Check bounds against the exact target unsigned limits
    if charsParsed > 0 and temp <= high(T).BiggestUInt:
      res = T(temp)
      return charsParsed
  else:
    var temp: BiggestInt
    let charsParsed = parseBiggestInt(input, temp, start)

    # Check bounds against the exact target signed limits
    if charsParsed > 0 and temp >= low(T).BiggestInt and temp <= high(T).BiggestInt:
      res = T(temp)
      return charsParsed

  return 0 # Mismatch or out of bounds

# Clean generic wrapper function
proc parseInteger*[T: SomeInteger](s: string): Option[T] =
  var res: T
  if scanf(s, "${genericIntScanner}", res):
    return some(res)
  else:
    return none(T)

# True iff the syntactically-validated decimal float literal `text`
# is exactly representable as `mantissa * 2^k` for some non-negative
# integer mantissa with at most `mantissaBits` significant bits (i.e.
# `mantissa <= 2^mantissaBits`) and some integer `k`. The decision
# uses a rational-form decomposition: any literal denotes
# `M * 10^E = M * 2^E * 5^E`, so an exact binary representation
# requires that `5^E` either combine with M without overflow (E >= 0)
# or divide M cleanly (E < 0). Decimal fractions like `0.1` whose
# denominator has a 5-factor that does not cancel are rejected here.
# Used by `parseFloat[T]` to surface precision loss at the literal
# site rather than letting it slip silently into the analyzer's
# stored value.
proc isExactlyRepresentable*(text: string, mantissaBits: int): bool =
  var s = text
  if s.len > 0 and (s[0] == '+' or s[0] == '-'):
    s = s[1..^1]

  var mantText, expText: string
  let eIdx = s.find({'e', 'E'})
  if eIdx >= 0:
    mantText = s[0..<eIdx]
    expText = s[eIdx+1..^1]
  else:
    mantText = s
    expText = "0"

  var intPart, fracPart: string
  let dotIdx = mantText.find('.')
  if dotIdx >= 0:
    intPart = mantText[0..<dotIdx]
    fracPart = mantText[dotIdx+1..^1]
  else:
    intPart = mantText
    fracPart = ""

  # Trailing zeros on the fractional part don't change the value;
  # stripping them keeps E small so `5^|E|` stays in BiggestUInt.
  while fracPart.len > 0 and fracPart[^1] == '0':
    fracPart = fracPart[0..^2]
  # Leading zeros on the integer part are also value-neutral.
  while intPart.len > 1 and intPart[0] == '0':
    intPart = intPart[1..^1]

  var combined = intPart & fracPart
  if combined.len == 0: combined = "0"
  while combined.len > 1 and combined[0] == '0':
    combined = combined[1..^1]

  var M: BiggestUInt
  try:
    M = parseBiggestUInt(combined)
  except ValueError:
    return false  # mantissa string too long for our scratch integer

  if M == 0: return true

  var E: int
  try:
    E = parseInt(expText) - fracPart.len
  except ValueError:
    return false

  let maxMantissa = 1'u64 shl mantissaBits

  if E >= 0:
    # value = M * 10^E. Multiply, watching for overflow.
    var v: BiggestUInt = M
    for _ in 0..<E:
      let next = v * 10
      if next div 10 != v: return false
      v = next
    # Strip factors of 2 — they're absorbed into the binary exponent.
    while (v and 1'u64) == 0 and v != 0:
      v = v shr 1
    return v <= maxMantissa
  else:
    # value = M / 10^|E|. 10^|E| = 2^|E| * 5^|E|. For exact binary
    # representation, 5^|E| must divide M.
    let k = -E
    var fiveK: BiggestUInt = 1
    for _ in 0..<k:
      let next = fiveK * 5
      if next div 5 != fiveK: return false
      fiveK = next
    if M mod fiveK != 0: return false
    var mant: BiggestUInt = M div fiveK
    while (mant and 1'u64) == 0 and mant != 0:
      mant = mant shr 1
    return mant <= maxMantissa

# Sibling of `parseInteger` — same `Option[T]` shape, dispatched at
# compile time on T. The tokenizer has already validated the input as
# a syntactically valid float literal, so failure modes here are
# numeric:
#
#   - out-of-range overflow that `parseutils.parseFloat` reports as
#     0-chars-consumed (literal text too large to fit in `float`);
#   - the parsed value classifies as ±Inf or NaN — currently always
#     rejected (see TODO below);
#   - the literal is not exactly representable in the target float
#     kind — `isExactlyRepresentable` decides on a rational basis.
#
# float32 takes an additional belt-and-braces narrowing test
# (round-trip f64 → f32 → f64) so a value that fits in float64 but
# not float32 is also caught.
#
# TODO(float-special-values): Inf, -Inf, and NaN are deliberately
# rejected today — there is no surface syntax to write them
# (`f64 inf` doesn't parse, since the float-literal spec requires
# digits) and the float modules in base.aslb expose no
# is_finite / is_nan classifiers, so a producer-of-Inf could only
# come from an arithmetic overflow that ASL already reroutes through
# Status[T]. When the language grows special-value literals
# (`f64.inf`, `f64.nan`) and classification predicates, this
# unconditional reject should be relaxed.
proc parseFloat*[T: SomeFloat](s: string): Option[T] =
  var temp: float
  if parseutils.parseFloat(s, temp) == 0: return none(T)
  when T is float32:
    let narrowed = temp.float32
    if narrowed.classify in {fcInf, fcNegInf, fcNan}: return none(T)
    if narrowed.float64 != temp: return none(T)
    if not isExactlyRepresentable(s, 24): return none(T)
    some(narrowed)
  elif T is float64:
    if temp.classify in {fcInf, fcNegInf, fcNan}: return none(T)
    if not isExactlyRepresentable(s, 53): return none(T)
    some(temp)

type AnalyzedVariantPatternScope* = ref object
  variablePatternFound: bool
  totalCases: int
  variants: HashSet[Identifier]

proc newAnalyzedVariantPatternScope*(totalCases: int): AnalyzedVariantPatternScope =
  AnalyzedVariantPatternScope(variablePatternFound: false, totalCases: totalCases, variants: initHashSet[Identifier]())

proc update*(scope: AnalyzedVariantPatternScope, id: int, pattern: ResolvedCasePattern): Result[AnalyzedVariantPatternScope, string] =
  case pattern.kind:
  of rcpkInteger:
    err(fmt"{pattern.loc} expected a union variant but found integer literal")
  of rcpkVariable:
    if id != scope.totalCases - 1:
      err(fmt"{pattern.loc} variable pattern binding is supported only in the last case block")
    else:
      scope.variablePatternFound = true
      ok(scope)
  of rcpkVariant:
    if pattern.variant.name in scope.variants:
      err(fmt"{pattern.variant.loc} found duplicate variant `{pattern.variant.name.asl}`")
    else:
      scope.variants.incl(pattern.variant.name)
      ok(scope)

# NOTE: If there is no variable pattern in union matching then all branches must be covered
proc hasUncoveredCases*(scope: AnalyzedVariantPatternScope, totalVariants: int, loc: Location): Result[void, string] =
  # TODO: improve error message by showing the uncovered variants
  if scope.variablePatternFound:
    if scope.variants.len < totalVariants: ok()
    else: err(fmt"{loc} variable binding is invalid since all the variants are already covered by the case blocks")
  else:
    if scope.variants.len == totalVariants: ok()
    else: err(fmt"{loc} case blocks do not cover all the variants")

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

proc newAnalyzedLiteralPatternScope*(literal: ResolvedLiteralType, totalCases: int): Result[AnalyzedLiteralPatternScope, string] =
  case literal:
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
  of rcpkVariant:
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

type AnalyzedVariantPattern* = ref object
  resolved: VariantPattern
  variant: AnalyzedVariant
  fields: seq[AnalyzedArgumentDefinition]

proc newAnalyzedVariantPattern*(resolved: VariantPattern, variant: AnalyzedVariant, fields: seq[AnalyzedArgumentDefinition]): AnalyzedVariantPattern =
  AnalyzedVariantPattern(resolved: resolved, variant: variant, fields: fields)

proc bindings*(pattern: AnalyzedVariantPattern): seq[AnalyzedArgumentDefinition] =
  var bindings: seq[AnalyzedArgumentDefinition]
  for (field, argDef) in zip(pattern.resolved.fields, pattern.fields):
    let bindingDef = newAnalyzedArgumentDefinition(argDef.argType, field.binding)
    bindings.add(bindingDef)
  return bindings

proc analyzeVariantCasePattern*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, variantPattern: VariantPattern, union: AnalyzedUnion): Result[AnalyzedVariantPattern, string] =
  let variant = ? union.findVariant(variantPattern.name)
  var analyzedFields: seq[AnalyzedArgumentDefinition]
  for field in variantPattern.fields:
    let analyzedField = ? variant.findField(field.name)
    analyzedFields.add(analyzedField)
  ok(newAnalyzedVariantPattern(variantPattern, variant, analyzedFields))

type
  AnalyzedCasePatternKind* = enum
    acpkVariant, acpkInteger, acpkVariable
  AnalyzedCasePattern* = ref object
    case kind: AnalyzedCasePatternKind
    of acpkVariant: variant: AnalyzedVariantPattern
    of acpkInteger: integer: IntegerLiteral
    of acpkVariable: variable: AnalyzedArgumentDefinition

proc newAnalyzedCasePattern*(variant: AnalyzedVariantPattern): AnalyzedCasePattern =
  AnalyzedCasePattern(kind: acpkVariant, variant: variant)

proc newAnalyzedCasePattern*(integer: IntegerLiteral): AnalyzedCasePattern =
  AnalyzedCasePattern(kind: acpkInteger, integer: integer)

proc newAnalyzedCasePattern*(variable: AnalyzedArgumentDefinition): AnalyzedCasePattern =
  AnalyzedCasePattern(kind: acpkVariable, variable: variable)

proc bindings*(pattern: AnalyzedCasePattern): seq[AnalyzedArgumentDefinition] =
  case pattern.kind:
  of acpkVariant: pattern.variant.bindings
  of acpkVariable: @[pattern.variable]
  of acpkInteger: newSeq[AnalyzedArgumentDefinition]()

proc analyzeCasePattern*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, pattern: ResolvedCasePattern, subjectType: AnalyzedArgumentType, union: AnalyzedUnion): Result[AnalyzedCasePattern, string] =
  case pattern.kind:
  of rcpkInteger: err(fmt"{pattern.loc} UNREACHABLE: integer literals are not allowed in union case pattern")
  of rcpkVariable:
    let analyzedArgDef = newAnalyzedArgumentDefinition(subjectType, pattern.variable)
    ok(newAnalyzedCasePattern(analyzedArgDef))
  of rcpkVariant:
    let analyzedPattern = ? analyzeVariantCasePattern(app, file, fileScope, defScope, funcScope, pattern.variant, union)
    ok(newAnalyzedCasePattern(analyzedPattern))

proc analyzeCasePattern*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, pattern: ResolvedCasePattern, subjectType: AnalyzedArgumentType): Result[AnalyzedCasePattern, string] =
  case pattern.kind:
  of rcpkVariant:
    err(fmt"{pattern.loc} UNREACHABLE: union variants are not allowed in literal case pattern")
  of rcpkInteger:
    ok(newAnalyzedCasePattern(pattern.integer))
  of rcpkVariable:
    let analyzedArgDef = newAnalyzedArgumentDefinition(subjectType, pattern.variable)
    ok(newAnalyzedCasePattern(analyzedArgDef))
