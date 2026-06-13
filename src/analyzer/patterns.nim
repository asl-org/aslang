## Pattern-level analysis: AnalyzedCasePattern plus the
## variant/literal pattern scopes used for exhaustiveness checking.
##
## Independent of the body cluster — the pattern's payload is either
## a parser IntegerLiteral (for literal subjects) or a resolved
## variant pattern (for union subjects). Body-level callers compose
## these via `analyzeCasePattern` / `update` / `hasUncoveredCases`.

import results, sets, strformat, options, sequtils, strscans, parseutils, strutils

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
proc hasUncoveredCases*(scope: AnalyzedVariantPatternScope, totalVariants: int): Result[void, string] =
  # TODO: improve error message by showing the uncovered variants
  if scope.variablePatternFound:
    if scope.variants.len < totalVariants: ok()
    else: err(fmt"variable binding is invalid since all the variants are already covered by the case blocks")
  else:
    if scope.variants.len == totalVariants: ok()
    else: err(fmt"case blocks do not cover all the variants")

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

proc checkDuplicate(scope: AnalyzedLiteralPatternScope, integer: IntegerLiteral): Result[AnalyzedLiteralPatternScope, string] =
  case scope.kind:
  of alpskU8:
    case integer.kind:
    of ilkSigned:
      err(fmt"{integer.loc} expected value to be a valid 8-bit unsigned integer")
    of ilkUnsigned:
      let maybeU8 = parseInteger[uint8](integer.asl)
      if maybeU8.isNone: err(fmt"{integer.loc} expected value to be a valid 8-bit unsigned integer")
      else:
        let u8Value = maybeU8.get
        if u8Value in scope.u8Values: err(fmt"{integer.loc} duplicated integer pattern encountered")
        else: scope.u8Values.incl(u8Value); ok(scope)
  of alpskU16: err(fmt"{integer.loc} todo: analyze U16 literal case pattern")
  of alpskU32: err(fmt"{integer.loc} todo: analyze U32 literal case pattern")
  of alpskU64: err(fmt"{integer.loc} todo: analyze U64 literal case pattern")
  of alpskI16: err(fmt"{integer.loc} todo: analyze I16 literal case pattern")
  of alpskI32: err(fmt"{integer.loc} todo: analyze I32 literal case pattern")
  of alpskI64: err(fmt"{integer.loc} todo: analyze I64 literal case pattern")
  of alpskI8:
    let maybeI8 = parseInteger[int8](integer.asl)
    if maybeI8.isNone: err(fmt"{integer.loc} expected value to be a valid 8-bit signed integer")
    else:
      let i8Value = maybeI8.get
      if i8Value in scope.i8Values: err(fmt"{integer.loc} duplicated integer pattern encountered")
      else: scope.i8Values.incl(i8Value); ok(scope)

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
proc hasUncoveredCases*(scope: AnalyzedLiteralPatternScope): Result[void, string] =
  # TODO: improve error message by showing the uncovered variants
  if scope.variablePatternFound: ok()
  else: err(fmt"variable case pattern binding is required for integer literal pattern")

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

proc analyzeVariantCasePattern*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, variantPattern: VariantPattern, union: AnalyzedUnion): Result[AnalyzedVariantPattern, string] =
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

proc analyzeCasePattern*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, pattern: ResolvedCasePattern, union: AnalyzedUnion): Result[AnalyzedCasePattern, string] =
  case pattern.kind:
  of rcpkInteger: err(fmt"{pattern.loc} UNREACHABLE: integer literals are not allowed in union case pattern")
  of rcpkVariable: err(fmt"{pattern.loc} todo: analyze variable case pattern")
  of rcpkVariant:
    let analyzedPattern = ? analyzeVariantCasePattern(app, file, fileScope, module, defScope, funcScope, pattern.variant, union)
    ok(newAnalyzedCasePattern(analyzedPattern))

proc analyzeCasePattern*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, pattern: ResolvedCasePattern, subjectType: AnalyzedArgumentType): Result[AnalyzedCasePattern, string] =
  case pattern.kind:
  of rcpkVariant:
    err(fmt"{pattern.loc} UNREACHABLE: union variants are not allowed in literal case pattern")
  of rcpkInteger:
    ok(newAnalyzedCasePattern(pattern.integer))
  of rcpkVariable:
    let analyzedArgDef = newAnalyzedArgumentDefinition(subjectType, pattern.variable)
    ok(newAnalyzedCasePattern(analyzedArgDef))
