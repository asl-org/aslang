import results, tables, strformat, sequtils, options, strutils, sets, strscans, parseutils, strutils

import tokenizer
import parser
import resolver
import argtypes
import literals
import data
import funcdefs
import modules

proc genericIntScanner[T: SomeInteger](input: string, res: var T, start: int): int =
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
proc parseInteger[T: SomeInteger](s: string): Option[T] =
  var res: T
  if scanf(s, "${genericIntScanner}", res):
    return some(res)
  else:
    return none(T)

type AnalyzedDefinedTypeScope* = Table[Identifier, AnalyzedDefinedType]
proc findModuleDef(defScope: AnalyzedDefinedTypeScope, name: Identifier, loc: Location): Result[AnalyzedModuleDefinition, string] =
  if name notin defScope:
    err(fmt"{loc} UNREACHABLE: module `{name.asl}` is not defined")
  else:
    let entry = defScope[name]
    case entry.kind:
    of adtkModule: ok(entry.module)
    of adtkGeneric:
      err(fmt"{loc} UNREACHABLE: scope entry `{name.asl}` is a generic but caller expected module")

proc findModuleDef(defScope: AnalyzedDefinedTypeScope, argType: AnalyzedArgumentType, loc: Location): Result[AnalyzedModuleDefinition, string] =
  case argType.kind:
  of aatkImported:
    err(fmt"{loc} todo: analyze case blocks for imported subject type")
  of aatkDefined:
    let definedArgType = argType.definedType
    case definedArgType.kind:
    of adatkGeneric:
      err(fmt"{loc} todo: analyze case blocks for generic subject type")
    of adatkModule:
      let moduleArgType = definedArgType.module
      if moduleArgType.name notin defScope:
        err(fmt"{loc} UNREACHABLE: module `{moduleArgType.name.asl}` is not defined")
      else:
        let entry = defScope[moduleArgType.name]
        case entry.kind:
        of adtkModule: ok(entry.module)
        of adtkGeneric:
          err(fmt"{loc} UNREACHABLE: scope entry `{moduleArgType.name.asl}` is a generic but argType claims module")

proc extractDataBlock(defScope: AnalyzedDefinedTypeScope, module: AnalyzedModuleDefinition, loc: Location): Result[AnalyzedData, string] =
  if module.data.isNone:
    err(fmt"{loc} UNREACHABLE: expression does not return a data type")
  else:
    ok(module.data.get)

proc extractDataBlock(defScope: AnalyzedDefinedTypeScope, argType: AnalyzedArgumentType, loc: Location): Result[AnalyzedData, string] =
  let argModule = ? defScope.findModuleDef(argType, loc)
  defScope.extractDataBlock(argModule, loc)

proc extractStructFor(defScope: AnalyzedDefinedTypeScope, argType: AnalyzedArgumentType, loc: Location): Result[AnalyzedStruct, string] =
  let argModule = ? defScope.findModuleDef(argType, loc)
  let dataBlock = ? defScope.extractDataBlock(argModule, loc)
  case dataBlock.kind:
  of adkStruct: ok(dataBlock.struct)
  of adkUnion: err(fmt"{loc} expected module `{argModule.name.asl}` to have a struct block but found union")
  of adkLiteral: err(fmt"{loc} expected module `{argModule.name.asl}` to have a struct block but found literal")

proc extractUnionFor(defScope: AnalyzedDefinedTypeScope, argType: AnalyzedArgumentType, loc: Location): Result[AnalyzedUnion, string] =
  let argModule = ? defScope.findModuleDef(argType, loc)
  let dataBlock = ? defScope.extractDataBlock(argModule, loc)
  case dataBlock.kind:
  of adkUnion: ok(dataBlock.union)
  of adkStruct: err(fmt"{loc} expected module `{argModule.name.asl}` to have a union block but found struct")
  of adkLiteral: err(fmt"{loc} expected module `{argModule.name.asl}` to have a union block but found literal")

type AnalyzedFunctionScope = Table[Identifier, AnalyzedArgumentType]
proc clone(scope: AnalyzedFunctionScope): AnalyzedFunctionScope =
  var updated: AnalyzedFunctionScope
  for key, value in scope: updated[key] = value
  return updated

type AnalyzedVariantPatternScope = ref object
  variablePatternFound: bool
  totalCases: int
  variants: HashSet[Identifier]

proc newAnalyzedVariantPatternScope(totalCases: int): AnalyzedVariantPatternScope =
  AnalyzedVariantPatternScope(variablePatternFound: false, totalCases: totalCases, variants: initHashSet[Identifier]())

proc update(scope: AnalyzedVariantPatternScope, id: int, pattern: ResolvedCasePattern): Result[AnalyzedVariantPatternScope, string] =
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
proc hasUncoveredCases(scope: AnalyzedVariantPatternScope, totalVariants: int): Result[void, string] =
  # TODO: improve error message by showing the uncovered variants
  if scope.variablePatternFound:
    if scope.variants.len < totalVariants: ok()
    else: err(fmt"variable binding is invalid since all the variants are already covered by the case blocks")
  else:
    if scope.variants.len == totalVariants: ok()
    else: err(fmt"case blocks do not cover all the variants")

type
  AnalyzedLiteralPatternScopeKind = enum
    alpskU8, alpskU16, alpskU32, alpskU64,
    alpskI8, alpskI16, alpskI32, alpskI64
  AnalyzedLiteralPatternScope = ref object
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

proc newAnalyzedLiteralPatternScope(literal: ResolvedLiteralType, totalCases: int): Result[AnalyzedLiteralPatternScope, string] =
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

proc update(scope: AnalyzedLiteralPatternScope, id: int, pattern: ResolvedCasePattern): Result[AnalyzedLiteralPatternScope, string] =
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
proc hasUncoveredCases(scope: AnalyzedLiteralPatternScope): Result[void, string] =
  # TODO: improve error message by showing the uncovered variants
  if scope.variablePatternFound: ok()
  else: err(fmt"variable case pattern binding is required for integer literal pattern")

type AnalyzedVariantPattern = ref object
  resolved: VariantPattern
  variant: AnalyzedVariant
  fields: seq[AnalyzedArgumentDefinition]

proc newAnalyzedVariantPattern(resolved: VariantPattern, variant: AnalyzedVariant, fields: seq[AnalyzedArgumentDefinition]): AnalyzedVariantPattern =
  AnalyzedVariantPattern(resolved: resolved, variant: variant, fields: fields)

proc bindings(pattern: AnalyzedVariantPattern): seq[AnalyzedArgumentDefinition] =
  var bindings: seq[AnalyzedArgumentDefinition]
  for (field, argDef) in zip(pattern.resolved.fields, pattern.fields):
    let bindingDef = newAnalyzedArgumentDefinition(argDef.argType, field.binding)
    bindings.add(bindingDef)
  return bindings

proc analyzeVariantCasePattern*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, variantPattern: VariantPattern, union: AnalyzedUnion): Result[AnalyzedVariantPattern, string] =
  let variant = ? union.findVariant(variantPattern.name)
  var analyzedFields: seq[AnalyzedArgumentDefinition]
  for field in variantPattern.fields:
    let analyzedField = ? variant.findField(field.name)
    analyzedFields.add(analyzedField)
  ok(newAnalyzedVariantPattern(variantPattern, variant, analyzedFields))

type
  AnalyzedCasePatternKind = enum
    acpkVariant, acpkInteger, acpkVariable
  AnalyzedCasePattern = ref object
    case kind: AnalyzedCasePatternKind
    of acpkVariant: variant: AnalyzedVariantPattern
    of acpkInteger: integer: IntegerLiteral
    of acpkVariable: variable: AnalyzedArgumentDefinition

proc newAnalyzedCasePattern(variant: AnalyzedVariantPattern): AnalyzedCasePattern =
  AnalyzedCasePattern(kind: acpkVariant, variant: variant)

proc newAnalyzedCasePattern(integer: IntegerLiteral): AnalyzedCasePattern =
  AnalyzedCasePattern(kind: acpkInteger, integer: integer)

proc newAnalyzedCasePattern(variable: AnalyzedArgumentDefinition): AnalyzedCasePattern =
  AnalyzedCasePattern(kind: acpkVariable, variable: variable)

proc bindings(pattern: AnalyzedCasePattern): seq[AnalyzedArgumentDefinition] =
  case pattern.kind:
  of acpkVariant: pattern.variant.bindings
  of acpkVariable: @[pattern.variable]
  of acpkInteger: newSeq[AnalyzedArgumentDefinition]()

proc analyzeCasePattern*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, pattern: ResolvedCasePattern, union: AnalyzedUnion): Result[AnalyzedCasePattern, string] =
  case pattern.kind:
  of rcpkInteger: err(fmt"{pattern.loc} UNREACHABLE: integer literals are not allowed in union case pattern")
  of rcpkVariable: err(fmt"{pattern.loc} todo: analyze variable case pattern")
  of rcpkVariant:
    let analyzedPattern = ? analyzeVariantCasePattern(app, file, fileScope, module, defScope, funcScope, pattern.variant, union)
    ok(newAnalyzedCasePattern(analyzedPattern))

proc analyzeCasePattern*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, pattern: ResolvedCasePattern, subjectType: AnalyzedArgumentType): Result[AnalyzedCasePattern, string] =
  case pattern.kind:
  of rcpkVariant:
    err(fmt"{pattern.loc} UNREACHABLE: union variants are not allowed in literal case pattern")
  of rcpkInteger:
    ok(newAnalyzedCasePattern(pattern.integer))
  of rcpkVariable:
    let analyzedArgDef = newAnalyzedArgumentDefinition(subjectType, pattern.variable)
    ok(newAnalyzedCasePattern(analyzedArgDef))

type AnalyzedFunctionRef = ref object
  argType: AnalyzedArgumentType
  funcDefs: seq[AnalyzedFunctionDefinition]

proc newAnalyzedFunctionRef(argType: AnalyzedArgumentType, funcDefs: seq[AnalyzedFunctionDefinition]): AnalyzedFunctionRef =
  AnalyzedFunctionRef(argType: argType, funcDefs: funcDefs)

proc analyzeFunctionRef*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, fnref: ResolvedFunctionRef): Result[AnalyzedFunctionRef, string] =
  let argType = ? analyzeArgumentType(app, file, fileScope, module, fnref.argType)
  case argType.kind:
  of aatkImported: err(fmt"{fnref.loc} todo: analyze imported type function ref")
  of aatkDefined:
    let definedType = argType.definedType
    case definedType.kind:
    of adatkGeneric:
      let genericType = definedType.generic
      if genericType.name notin defScope:
        err(fmt"{fnref.loc} [UNREACHABLE] module `{genericType.name.asl}` does not exist in scope")
      else:
        let genericDef = defScope[genericType.name].generic
        # NOTE: if the function call is to other module then only it should have public accessor
        let funcDefs = ? genericDef.findFunctionDefs(fnref.name, fnref.arity)
        ok(newAnalyzedFunctionRef(argType, funcDefs))
    of adatkModule:
      let moduleType = definedType.module
      if moduleType.module.name notin defScope:
        err(fmt"{fnref.loc} [UNREACHABLE] module `{moduleType.module.name.asl}` does not exist in scope")
      else:
        let moduleDef = defScope[moduleType.module.name].module
        # NOTE: if the function call is to other module then only it should have public accessor
        let funcDefs = ? moduleDef.findFunctionDefs(fnref.name, fnref.arity, module != moduleDef.resolved)
        ok(newAnalyzedFunctionRef(argType, funcDefs))

type AnalyzedVariable = ref object
  name: Identifier
  argType: AnalyzedArgumentType

proc newAnalyzedVariable(name: Identifier, argType: AnalyzedArgumentType): AnalyzedVariable =
  AnalyzedVariable(name: name, argType: argType)

proc loc(variable: AnalyzedVariable): Location = variable.name.loc

proc analyzeVariable(scope: AnalyzedFunctionScope, variable: Identifier): Result[AnalyzedVariable, string] =
  if variable in scope: ok(newAnalyzedVariable(variable, scope[variable]))
  else: err(fmt"{variable.loc} variable `{variable.asl}` does not exist in scope")

type AnalyzedGetter = ref object
  resolved: ResolvedGetter
  argType: AnalyzedArgumentType
  property: AnalyzedArgumentDefinition

proc newAnalyzedGetter(resolved: ResolvedGetter, argType: AnalyzedArgumentType, property: AnalyzedArgumentDefinition): AnalyzedGetter =
  AnalyzedGetter(resolved: resolved, argType: argType, property: property)

proc loc(getter: AnalyzedGetter): Location = getter.resolved.loc

proc analyzeGetter*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, getter: ResolvedGetter): Result[AnalyzedGetter, string] =
  if getter.source notin funcScope:
    err(fmt"{getter.loc} variable `{getter.source.asl}` is not present in scope")
  else:
    let analyzedArgType = funcScope[getter.source]
    let struct = ? defScope.extractStructFor(analyzedArgType, getter.loc)
    let analyzedProperty = ? struct.findField(getter.property)
    # TODO: coerce the property type from the generic to concrete
    ok(newAnalyzedGetter(getter, analyzedArgType, analyzedProperty))

type
  AnalyzedFunctionCall = ref object
    resolved: ResolvedFunctionCall
    fnref: AnalyzedFunctionRef
    args: seq[AnalyzedExpression]
    returns: AnalyzedArgumentType

  AnalyzedKeywordArgument = ref object
    # todo: add a concrete type
    resolved: ResolvedKeywordArgument
    field: AnalyzedArgumentDefinition
    expression: AnalyzedExpression

  AnalyzedStructInitializer = ref object
    resolved: ResolvedStructInitializer
    argType: AnalyzedArgumentType
    kwargs: seq[AnalyzedKeywordArgument]

  AnalyzedUnionInitializer = ref object
    resolved: ResolvedUnionInitializer
    argType: AnalyzedArgumentType
    variant: AnalyzedVariant
    kwargs: seq[AnalyzedKeywordArgument]

  AnalyzedInitializerKind = enum
    aikUnion, aikStruct
  AnalyzedInitializer = ref object
    case kind: AnalyzedInitializerKind
    of aikUnion: union: AnalyzedUnionInitializer
    of aikStruct: struct: AnalyzedStructInitializer

  AnalyzedCaseBlock = ref object
    resolved: ResolvedCaseBlock
    pattern: AnalyzedCasePattern
    statements: seq[AnalyzedStatement]

  AnalyzedMatchExpression = ref object
    resolved: ResolvedMatchExpression
    subject: AnalyzedExpression
    cases: seq[AnalyzedCaseBlock]
    returns: AnalyzedArgumentType

  AnalyzedAssignment = ref object
    resolved: ResolvedAssignment
    expression: AnalyzedExpression

  AnalyzedMutation = ref object
    resolved: ResolvedMutation
    getter: AnalyzedGetter
    expression: AnalyzedExpression

  AnalyzedExpressionKind = enum
    aekVariable, aekFunctionCall, aekLiteral, aekMatchExpr, aekInitializer, aekGetter
  AnalyzedExpression = ref object
    case kind: AnalyzedExpressionKind
    of aekVariable: variable: AnalyzedVariable
    of aekFunctionCall: fncall: AnalyzedFunctionCall
    of aekLiteral: literal: Literal
    of aekMatchExpr: match: AnalyzedMatchExpression
    of aekInitializer: init: AnalyzedInitializer
    of aekGetter: getter: AnalyzedGetter

  AnalyzedStatementKind = enum
    askExpr, askAssignment, askMutation
  AnalyzedStatement = ref object
    case kind: AnalyzedStatementKind
    of askExpr: expression: AnalyzedExpression
    of askAssignment: assignment: AnalyzedAssignment
    of askMutation: mutation: AnalyzedMutation

proc argType(expression: AnalyzedExpression): Option[AnalyzedArgumentType]
proc argType(statement: AnalyzedStatement): Option[AnalyzedArgumentType]

# TODO: accepts returns field once function call resolution is complete
proc newAnalyzedFunctionCall(resolved: ResolvedFunctionCall, fnref: AnalyzedFunctionRef, args: seq[AnalyzedExpression], returns: AnalyzedArgumentType): AnalyzedFunctionCall =
  AnalyzedFunctionCall(resolved: resolved, fnref: fnref, args: args, returns: returns)

proc loc(fncall: AnalyzedFunctionCall): Location = fncall.resolved.loc

proc newAnalyzedKeywordArgument(resolved: ResolvedKeywordArgument, field: AnalyzedArgumentDefinition, expression: AnalyzedExpression): AnalyzedKeywordArgument =
  AnalyzedKeywordArgument(resolved: resolved, field: field, expression: expression)

proc newAnalyzedStructInitializer(resolved: ResolvedStructInitializer, argType: AnalyzedArgumentType, kwargs: seq[AnalyzedKeywordArgument]): AnalyzedStructInitializer =
  AnalyzedStructInitializer(resolved: resolved, argType: argType, kwargs: kwargs)

proc newAnalyzedUnionInitializer(resolved: ResolvedUnionInitializer, argType: AnalyzedArgumentType, variant: AnalyzedVariant, kwargs: seq[AnalyzedKeywordArgument]): AnalyzedUnionInitializer =
  AnalyzedUnionInitializer(resolved: resolved, argType: argType, variant: variant, kwargs: kwargs)

proc newAnalyzedInitializer(union: AnalyzedUnionInitializer): AnalyzedInitializer =
  AnalyzedInitializer(kind: aikUnion, union: union)

proc newAnalyzedInitializer(struct: AnalyzedStructInitializer): AnalyzedInitializer =
  AnalyzedInitializer(kind: aikStruct, struct: struct)

proc argType(init: AnalyzedInitializer): AnalyzedArgumentType =
  case init.kind:
  of aikUnion: init.union.argType
  of aikStruct: init.struct.argType

proc loc(init: AnalyzedInitializer): Location =
  case init.kind:
  of aikUnion: init.union.resolved.loc
  of aikStruct: init.struct.resolved.loc

proc newAnalyzedCaseBlock(resolved: ResolvedCaseBlock, pattern: AnalyzedCasePattern, statements: seq[AnalyzedStatement]): AnalyzedCaseBlock =
  AnalyzedCaseBlock(resolved: resolved, pattern: pattern, statements: statements)

proc loc(caseBlock: AnalyzedCaseBlock): Location = caseBlock.resolved.loc

proc argType(caseBlock: AnalyzedCaseBlock): Option[AnalyzedArgumentType] =
  assert(caseBlock.statements.len > 0, "UNREACHABLE: should have been caught by resolver")
  caseBlock.statements[^1].argType

proc newAnalyzedMatchExpression(resolved: ResolvedMatchExpression, subject: AnalyzedExpression, cases: seq[AnalyzedCaseBlock], returns: AnalyzedArgumentType): AnalyzedMatchExpression =
  AnalyzedMatchExpression(resolved: resolved, subject: subject, cases: cases, returns: returns)

proc loc(m: AnalyzedMatchExpression): Location = m.resolved.loc

proc newAnalyzedAssignment(resolved: ResolvedAssignment, expression: AnalyzedExpression): AnalyzedAssignment =
  AnalyzedAssignment(resolved: resolved, expression: expression)

proc loc(assignment: AnalyzedAssignment): Location = assignment.resolved.loc
proc target(assignment: AnalyzedAssignment): Identifier = assignment.resolved.target
proc argType(assignment: AnalyzedAssignment): Option[AnalyzedArgumentType] = assignment.expression.argType

proc newAnalyzedMutation(resolved: ResolvedMutation, getter: AnalyzedGetter, expression: AnalyzedExpression): AnalyzedMutation =
  AnalyzedMutation(resolved: resolved, getter: getter, expression: expression)

proc loc(mutation: AnalyzedMutation): Location = mutation.resolved.loc
proc argType(mutation: AnalyzedMutation): Option[AnalyzedArgumentType] = mutation.expression.argType

proc newAnalyzedExpression(variable: AnalyzedVariable): AnalyzedExpression =
  AnalyzedExpression(kind: aekVariable, variable: variable)

proc newAnalyzedExpression(fncall: AnalyzedFunctionCall): AnalyzedExpression =
  AnalyzedExpression(kind: aekFunctionCall, fncall: fncall)

proc newAnalyzedExpression(literal: Literal): AnalyzedExpression =
  AnalyzedExpression(kind: aekLiteral, literal: literal)

proc newAnalyzedExpression(match: AnalyzedMatchExpression): AnalyzedExpression =
  AnalyzedExpression(kind: aekMatchExpr, match: match)

proc newAnalyzedExpression(init: AnalyzedInitializer): AnalyzedExpression =
  AnalyzedExpression(kind: aekInitializer, init: init)

proc newAnalyzedExpression(getter: AnalyzedGetter): AnalyzedExpression =
  AnalyzedExpression(kind: aekGetter, getter: getter)

proc loc(expression: AnalyzedExpression): Location =
  case expression.kind:
  of aekFunctionCall: return expression.fncall.loc
  of aekVariable: return expression.variable.loc
  of aekLiteral: return expression.literal.loc
  of aekGetter: return expression.getter.loc
  of aekMatchExpr: return expression.match.loc
  of aekInitializer: return expression.init.loc

proc argType(expression: AnalyzedExpression): Option[AnalyzedArgumentType] =
  case expression.kind:
  of aekLiteral: return none(AnalyzedArgumentType)
  of aekFunctionCall: return some(expression.fncall.returns)
  of aekVariable: return some(expression.variable.argType)
  of aekMatchExpr: return some(expression.match.returns)
  of aekInitializer: return some(expression.init.argType)
  of aekGetter: return some(expression.getter.argType)

proc newAnalyzedStatement(expression: AnalyzedExpression): AnalyzedStatement =
  AnalyzedStatement(kind: askExpr, expression: expression)

proc newAnalyzedStatement(assignment: AnalyzedAssignment): AnalyzedStatement =
  AnalyzedStatement(kind: askAssignment, assignment: assignment)

proc newAnalyzedStatement(mutation: AnalyzedMutation): AnalyzedStatement =
  AnalyzedStatement(kind: askMutation, mutation: mutation)

proc loc(statement: AnalyzedStatement): Location =
  case statement.kind:
  of askExpr: statement.expression.loc
  of askAssignment: statement.assignment.loc
  of askMutation: statement.mutation.loc

proc argType(statement: AnalyzedStatement): Option[AnalyzedArgumentType] =
  case statement.kind:
  of askExpr: statement.expression.argType
  of askAssignment: statement.assignment.argType
  of askMutation: statement.mutation.argType

proc arg(statement: AnalyzedStatement): Option[AnalyzedArgumentDefinition] =
  let maybeArgType = statement.argType
  if maybeArgType.isNone:
    assert(maybeArgType.isSome, fmt"{statement.loc} todo: support argType for statement")
  else:
    case statement.kind:
    of askExpr: return none(AnalyzedArgumentDefinition)
    of askMutation: return none(AnalyzedArgumentDefinition)
    of askAssignment: return some(newAnalyzedArgumentDefinition(maybeArgType.get, statement.assignment.target))

proc analyzeExpression*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, expression: ResolvedExpression): Result[AnalyzedExpression, string]

proc analyzeStatement*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, statement: ResolvedStatement): Result[AnalyzedStatement, string]

proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, defType: AnalyzedArgumentType, valType: AnalyzedArgumentType): Result[void, string]

proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, defType: AnalyzedModuleArgumentType, valType: AnalyzedModuleArgumentType): Result[void, string] =
  if defType.module != valType.module:
    err(fmt"{valType.loc} expected `{defType.name.asl}` but found `{valType.name.asl}`")
  else:
    for (defImpl, valImpl) in zip(defType.impls, valType.impls):
      ? analyzeValueTypeAgainstDefinitionType(app, file, fileScope, module, defScope, defImpl, valImpl)
    ok()

proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, defType: AnalyzedModuleArgumentType, valType: AnalyzedDefinedArgumentType): Result[void, string] =
  case valType.kind:
  of adatkModule:
    ? analyzeValueTypeAgainstDefinitionType(app, file, fileScope, module, defScope, defType, valType.module)
    ok()
  of adatkGeneric:
    err(fmt"{valType.loc} todo: analyze generic value type against module argument type")

proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, defType: AnalyzedModuleArgumentType, valType: AnalyzedArgumentType): Result[void, string] =
  case valType.kind:
  of aatkImported:
    err(fmt"{valType.loc} todo: analyze imported value type against module argument type")
  of aatkDefined:
    ? analyzeValueTypeAgainstDefinitionType(app, file, fileScope, module, defScope, defType, valType.definedType)
    ok()

proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, defType: AnalyzedGenericArgumentType, valType: AnalyzedArgumentType): Result[void, string] =
  let funcDefs = defType.resolved.concreteImpls(valType.self)
  for funcDef in funcDefs:
    case valType.kind:
    of aatkImported:
      return err(fmt"{valType.loc} todo: analyze imported impl type")
    of aatkDefined:
      case valType.definedType.kind:
      of adatkGeneric:
        let maybeConcreteFuncDef = valType.definedType.generic.resolved.findFunctionDef(funcDef)
        if maybeConcreteFuncDef.isNone:
          return err(fmt"{valType.loc} type `{valType.name.asl}` does not implement function `{funcDef.name.asl}` to support `{defType.resolved.name.asl}`")
      of adatkModule:
        let maybeConcreteFuncDef = valType.definedType.module.module.findFunctionDef(funcDef)
        if maybeConcreteFuncDef.isNone:
          return err(fmt"{valType.loc} type `{valType.name.asl}` does not implement function `{funcDef.name.asl}` to support `{defType.resolved.name.asl}`")
  ok()

proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, defType: AnalyzedDefinedArgumentType, valType: AnalyzedArgumentType): Result[void, string] =
  case defType.kind:
  of adatkModule:
    ? analyzeValueTypeAgainstDefinitionType(app, file, fileScope, module, defScope, defType.module, valType)
    ok()
  of adatkGeneric:
    ? analyzeValueTypeAgainstDefinitionType(app, file, fileScope, module, defScope, defType.generic, valType)
    ok()

# TODO: Return a map of generic -> argType from the recursive analysis
proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, defType: AnalyzedArgumentType, valType: AnalyzedArgumentType): Result[void, string] =
  case defType.kind:
  of aatkImported:
    err(fmt"{valType.loc} todo: analyze value type against imported argument type")
  of aatkDefined:
    ? analyzeValueTypeAgainstDefinitionType(app, file, fileScope, module, defScope, defType.definedType, valType)
    ok()

proc analyzeArgumentList*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, argValues: seq[AnalyzedExpression], funcDef: AnalyzedFunctionDefinition): Result[void, string] =
  # BUG: `zip` below silently truncates to the shorter sequence — if
  # funcDef.args.len != argValues.len the type-check walks only the common
  # prefix and reports success. Today the resolver's arity check prevents
  # this from being reachable, but the defensive assert traps the mismatch
  # if overload selection is ever wired wrong upstream.
  assert(funcDef.args.len == argValues.len,
    fmt"BUG: analyzeArgumentList arity mismatch — funcDef has {funcDef.args.len} args, call site passed {argValues.len}. zip would silently truncate; fix by erroring (or relying on resolver / overload selection).")
  for (argDef, argValue) in zip(funcDef.args, argValues):
    if argValue.argType.isNone:
      return err(fmt"{argValue.loc} todo: analyze function call literal argument")
    else:
      ? analyzeValueTypeAgainstDefinitionType(app, file, fileScope, module, defScope, argDef.argType, argValue.argType.get)
  ok()

proc resolveOverload(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, fncall: ResolvedFunctionCall, funcRef: AnalyzedFunctionRef, analyzedArgs: seq[AnalyzedExpression]): Result[AnalyzedFunctionDefinition, string] =
  var matches: seq[AnalyzedFunctionDefinition]
  for funcDef in funcRef.funcDefs:
    if analyzeArgumentList(app, file, fileScope, module, defScope, funcScope, analyzedArgs, funcDef).isOk:
      matches.add(funcDef)

  if matches.len == 1:
    ok(matches[0])
  else:
    var message: seq[string]
    if matches.len == 0:
      message.add(fmt"{fncall.loc} failed to find matching function:")
      for funcDef in funcRef.funcDefs:
        message.add(fmt"\t\t{funcDef.loc}")
    else:
      message.add(fmt"{fncall.loc} ambiguous function call — multiple candidates match:")
      for funcDef in matches:
        message.add(fmt"\t\t{funcDef.loc}")
    err(message.join("\n"))

proc analyzeFunctionCall*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, fncall: ResolvedFunctionCall): Result[AnalyzedFunctionCall, string] =
  let funcRef = ? analyzeFunctionRef(app, file, fileScope, module, defScope, fncall.funcRef)
  var analyzedArgs: seq[AnalyzedExpression]
  for arg in fncall.args:
    let analyzedArg = ? analyzeExpression(app, file, fileScope, module, defScope, funcScope, arg)
    analyzedArgs.add(analyzedArg)

  let matchingFuncDef = ? resolveOverload(app, file, fileScope, module, defScope, funcScope, fncall, funcRef, analyzedArgs)
  # TODO: find a way to compute concrete return type for now just passing along the funcDef.returns
  ok(newAnalyzedFunctionCall(fncall, funcRef, analyzedArgs, matchingFuncDef.returns))

proc analyzeCaseBlock*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, caseBlock: ResolvedCaseBlock, union: AnalyzedUnion): Result[AnalyzedCaseBlock, string] =
  let analyzedCasePattern = ? analyzeCasePattern(app, file, fileScope, module, defScope, funcScope, caseBlock.pattern, union)
  var caseScope = funcScope.clone()
  for binding in analyzedCasePattern.bindings:
    caseScope[binding.name] = binding.argType
  var analyzedStatements: seq[AnalyzedStatement]
  for statement in caseBlock.statements:
    let analyzedStatement = ? analyzeStatement(app, file, fileScope, module, defScope, caseScope, statement)
    analyzedStatements.add(analyzedStatement)
    if analyzedStatement.arg.isSome:
      let newArg = analyzedStatement.arg.get
      caseScope[newArg.name] = newArg.argType
  ok(newAnalyzedCaseBlock(caseBlock, analyzedCasePattern, analyzedStatements))

proc analyzeCaseBlock*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, caseBlock: ResolvedCaseBlock, subjectType: AnalyzedArgumentType): Result[AnalyzedCaseBlock, string] =
  let analyzedCasePattern = ? analyzeCasePattern(app, file, fileScope, module, defScope, funcScope, caseBlock.pattern, subjectType)
  var caseScope = funcScope.clone()
  for binding in analyzedCasePattern.bindings:
    caseScope[binding.name] = binding.argType
  var analyzedStatements: seq[AnalyzedStatement]
  for statement in caseBlock.statements:
    let analyzedStatement = ? analyzeStatement(app, file, fileScope, module, defScope, caseScope, statement)
    analyzedStatements.add(analyzedStatement)
    if analyzedStatement.arg.isSome:
      let newArg = analyzedStatement.arg.get
      caseScope[newArg.name] = newArg.argType
  ok(newAnalyzedCaseBlock(caseBlock, analyzedCasePattern, analyzedStatements))

proc verifyUniformReturnType(cases: seq[AnalyzedCaseBlock]): Result[void, string] =
  let expected = cases[0].argType
  if expected.isNone:
    return err(fmt"{cases[0].loc} todo: handle case block returning literal type")
  for c in cases:
    if c.argType.isNone:
      return err(fmt"{c.loc} todo: handle case block returning literal type")
    if c.argType.get != expected.get:
      return err(fmt"{c.loc} todo: return an error message telling that the case block return types are not same")
  ok()

proc analyzeCases*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, cases: seq[ResolvedCaseBlock], union: AnalyzedUnion): Result[seq[AnalyzedCaseBlock], string] =
  var patternScope = newAnalyzedVariantPatternScope(cases.len)
  for id, caseBlock in cases:
    patternScope = ? patternScope.update(id, caseBlock.pattern)

  ? hasUncoveredCases(patternScope, union.variants.len)

  assert(cases.len > 0, "UNREACHABLE: zero-case match should have been caught by the resolver")

  var analyzedCaseBlocks: seq[AnalyzedCaseBlock]
  for caseBlock in cases:
    let analyzedCaseBlock = ? analyzeCaseBlock(app, file, fileScope, module, defScope, funcScope, caseBlock, union)
    analyzedCaseBlocks.add(analyzedCaseBlock)
  ? verifyUniformReturnType(analyzedCaseBlocks)
  ok(analyzedCaseBlocks)

proc analyzeCases*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, cases: seq[ResolvedCaseBlock], subjectType: AnalyzedArgumentType, literal: AnalyzedLiteralBlock): Result[seq[AnalyzedCaseBlock], string] =
  var patternScope = ? newAnalyzedLiteralPatternScope(literal.resolved, cases.len)
  for id, caseBlock in cases:
    patternScope = ? patternScope.update(id, caseBlock.pattern)

  ? hasUncoveredCases(patternScope)

  assert(cases.len > 0, "UNREACHABLE: zero-case match should have been caught by the resolver")

  var analyzedCaseBlocks: seq[AnalyzedCaseBlock]
  for caseBlock in cases:
    let analyzedCaseBlock = ? analyzeCaseBlock(app, file, fileScope, module, defScope, funcScope, caseBlock, subjectType)
    analyzedCaseBlocks.add(analyzedCaseBlock)
  ? verifyUniformReturnType(analyzedCaseBlocks)
  ok(analyzedCaseBlocks)

proc analyzeMatchExpression*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, match: ResolvedMatchExpression): Result[AnalyzedMatchExpression, string] =
  let analyzedSubjectExpr = ? analyzeExpression(app, file, fileScope, module, defScope, funcScope, match.subject)
  if analyzedSubjectExpr.argType.isNone:
    err(fmt"{analyzedSubjectExpr.loc} todo: analyze case blocks for literal expression")
  else:
    let analyzedSubjectDataType = ? defScope.extractDataBlock(analyzedSubjectExpr.argType.get, analyzedSubjectExpr.loc)
    case analyzedSubjectDataType.kind:
    of adkStruct:
      let moduleName = analyzedSubjectExpr.argType.get.name
      err(fmt"{match.loc} match block only supports literal and union types but subject expression returns `{moduleName.asl}` a struct type")
    of adkLiteral:
      if match.cases.len == 0:
        err(fmt"{match.loc} UNREACHABLE: match block does not contain any case blocks")
      else:
        let analyzedCases = ? analyzeCases(app, file, fileScope, module, defScope, funcScope, match.cases, analyzedSubjectExpr.argType.get, analyzedSubjectDataType.literal)
        ok(newAnalyzedMatchExpression(match, analyzedSubjectExpr, analyzedCases, analyzedCases[0].argType.get))
    of adkUnion:
      if match.cases.len == 0:
        err(fmt"{match.loc} UNREACHABLE: match block does not contain any case blocks")
      else:
        let analyzedCases = ? analyzeCases(app, file, fileScope, module, defScope, funcScope, match.cases, analyzedSubjectDataType.union)
        ok(newAnalyzedMatchExpression(match, analyzedSubjectExpr, analyzedCases, analyzedCases[0].argType.get))

proc analyzeKeywordArgument*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, kwarg: ResolvedKeywordArgument, analyzedField: AnalyzedArgumentDefinition): Result[AnalyzedKeywordArgument, string] =
  let analyzedExpression = ? analyzeExpression(app, file, fileScope, module, defScope, funcScope, kwarg.expression)
  if analyzedExpression.argType.isNone:
    let fieldModule = ? defScope.findModuleDef(analyzedField.argType, kwarg.expression.loc)
    let fieldModuleData = ? defScope.extractDataBlock(fieldModule, kwarg.expression.loc)
    case fieldModuleData.kind:
    of adkStruct:
      err(fmt"{kwarg.expression.loc} field `{kwarg.name.asl}` expected a struct value but found literal")
    of adkUnion:
      err(fmt"{kwarg.expression.loc} field `{kwarg.name.asl}` expected a union value but found literal")
    of adkLiteral:
      let literalField = fieldModuleData.literal
      case literalField.resolved:
      of rltkU8: err(fmt"{kwarg.expression.loc} todo: analyze union initializer U8 literal argument")
      of rltkU16: err(fmt"{kwarg.expression.loc} todo: analyze union initializer U16 literal argument")
      of rltkU32: err(fmt"{kwarg.expression.loc} todo: analyze union initializer U32 literal argument")
      of rltkU64: err(fmt"{kwarg.expression.loc} todo: analyze union initializer U64 literal argument")
      of rltkI8: err(fmt"{kwarg.expression.loc} todo: analyze union initializer I8 literal argument")
      of rltkI16: err(fmt"{kwarg.expression.loc} todo: analyze union initializer I16 literal argument")
      of rltkI64: err(fmt"{kwarg.expression.loc} todo: analyze union initializer I64 literal argument")
      of rltkF32: err(fmt"{kwarg.expression.loc} todo: analyze union initializer F32 literal argument")
      of rltkF64: err(fmt"{kwarg.expression.loc} todo: analyze union initializer F64 literal argument")
      of rltkPointer: err(fmt"{kwarg.expression.loc} todo: analyze union initializer Pointer literal argument")
      of rltkString:
        case analyzedExpression.literal.kind:
        of lkFloat: err(fmt"{kwarg.expression.loc} expected a valid string literal but found float")
        of lkInteger: err(fmt"{kwarg.expression.loc} expected a valid string literal but found integer")
        of lkString: ok(newAnalyzedKeywordArgument(kwarg, analyzedField, analyzedExpression))
      of rltkI32:
        case analyzedExpression.literal.kind:
        of lkFloat: err(fmt"{kwarg.expression.loc} expected a valid 32-bit signed integer but found float")
        of lkString: err(fmt"{kwarg.expression.loc} expected a valid 32-bit signed integer but found string")
        of lkInteger:
          let maybeParsedInt = parseInteger[int32](analyzedExpression.literal.asl)
          if maybeParsedInt.isNone:
            err(fmt"{kwarg.expression.loc} expected a valid 32-bit signed integer but found `{analyzedExpression.literal.asl}`")
          else:
            ok(newAnalyzedKeywordArgument(kwarg, analyzedField, analyzedExpression))
  else:
    ? analyzeValueTypeAgainstDefinitionType(app, file, fileScope, module, defScope, analyzedField.argType, analyzedExpression.argType.get)
    ok(newAnalyzedKeywordArgument(kwarg, analyzedField, analyzedExpression))

proc analyzeUnionInitializer*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, init: ResolvedUnionInitializer): Result[AnalyzedUnionInitializer, string] =
  let analyzedArgType = ? analyzeArgumentType(app, file, fileScope, module, init.argType)
  let union = ? defScope.extractUnionFor(analyzedArgType, init.loc)
  let analyzedVariant = ? union.findVariant(init.variant)
  var analyzedKwargs: seq[AnalyzedKeywordArgument]
  for kwarg in init.kwargs:
    let analyzedField: AnalyzedArgumentDefinition = ? analyzedVariant.findField(kwarg.name)
    let analyzedKwarg = ? analyzeKeywordArgument(app, file, fileScope, module, defScope, funcScope, kwarg, analyzedField)
    analyzedKwargs.add(analyzedKwarg)
  ok(newAnalyzedUnionInitializer(init, analyzedArgType, analyzedVariant, analyzedKwargs))

proc analyzeStructInitializer*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, init: ResolvedStructInitializer): Result[AnalyzedStructInitializer, string] =
  let analyzedArgType = ? analyzeArgumentType(app, file, fileScope, module, init.argType)
  let struct = ? defScope.extractStructFor(analyzedArgType, init.loc)
  var analyzedKwargs: seq[AnalyzedKeywordArgument]
  for kwarg in init.kwargs:
    let analyzedField = ? struct.findField(kwarg.name)
    let analyzedKwarg = ? analyzeKeywordArgument(app, file, fileScope, module, defScope, funcScope, kwarg, analyzedField)
    analyzedKwargs.add(analyzedKwarg)
  ok(newAnalyzedStructInitializer(init, analyzedArgType, analyzedKwargs))

proc analyzeInitializer*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, init: ResolvedInitializer): Result[AnalyzedInitializer, string] =
  case init.kind:
  of rikLiteral:
    err(fmt"{init.loc} todo: analyze literal initializer")
  of rikStruct:
    let analyzedStructInit = ? analyzeStructInitializer(app, file, fileScope, module, defScope, funcScope, init.struct)
    ok(newAnalyzedInitializer(analyzedStructInit))
  of rikUnion:
    let analyzedUnionInit = ? analyzeUnionInitializer(app, file, fileScope, module, defScope, funcScope, init.union)
    ok(newAnalyzedInitializer(analyzedUnionInit))

proc analyzeExpression*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, expression: ResolvedExpression): Result[AnalyzedExpression, string] =
  case expression.kind:
  of rekLiteral: ok(newAnalyzedExpression(expression.literal))
  of rekVariable:
    let analyzedVariable = ? analyzeVariable(funcScope, expression.variable)
    ok(newAnalyzedExpression(analyzedVariable))
  of rekGetter:
    let analyzedGetter = ? analyzeGetter(app, file, fileScope, module, defScope, funcScope, expression.getter)
    ok(newAnalyzedExpression(analyzedGetter))
  of rekInitializer:
    let analyzedInit = ? analyzeInitializer(app, file, fileScope, module, defScope, funcScope, expression.init)
    ok(newAnalyzedExpression(analyzedInit))
  of rekFunctionCall:
    let analyzedFunctionCall = ? analyzeFunctionCall(app, file, fileScope, module, defScope, funcScope, expression.fncall)
    ok(newAnalyzedExpression(analyzedFunctionCall))
  of rekMatchExpr:
    let analyzedMatchExpr = ? analyzeMatchExpression(app, file, fileScope, module, defScope, funcScope, expression.match)
    ok(newAnalyzedExpression(analyzedMatchExpr))

proc analyzeAssignment*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, assignment: ResolvedAssignment): Result[AnalyzedAssignment, string] =
  let analyzedExpr = ? analyzeExpression(app, file, fileScope, module, defScope, funcScope, assignment.expression)
  ok(newAnalyzedAssignment(assignment, analyzedExpr))

proc analyzeMutation*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, mutation: ResolvedMutation): Result[AnalyzedMutation, string] =
  let analyzedGetter = ? analyzeGetter(app, file, fileScope, module, defScope, funcScope, mutation.getter)
  let analyzedExpression = ? analyzeExpression(app, file, fileScope, module, defScope, funcScope, mutation.expression)
  # TODO: Ensure that the getter field type and the expression type are same
  ok(newAnalyzedMutation(mutation, analyzedGetter, analyzedExpression))

proc analyzeStatement*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, statement: ResolvedStatement): Result[AnalyzedStatement, string] =
  case statement.kind:
  of rskExpr:
    let analyzedExpr = ? analyzeExpression(app, file, fileScope, module, defScope, funcScope, statement.expression)
    ok(newAnalyzedStatement(analyzedExpr))
  of rskAssignment:
    let analyzedAssignment = ? analyzeAssignment(app, file, fileScope, module, defScope, funcScope, statement.assignment)
    ok(newAnalyzedStatement(analyzedAssignment))
  of rskMutation:
    let analyzedMutation = ? analyzeMutation(app, file, fileScope, module, defScope, funcScope, statement.mutation)
    ok(newAnalyzedStatement(analyzedMutation))

type AnalyzedUserFunction = ref object
  resolved: ResolvedUserFunction
  def: AnalyzedFunctionDefinition
  statements: seq[AnalyzedStatement]

proc newAnalyzedUserFunction(resolved: ResolvedUserFunction, def: AnalyzedFunctionDefinition, statements: seq[AnalyzedStatement]): AnalyzedUserFunction =
  AnalyzedUserFunction(resolved: resolved, def: def, statements: statements)

proc analyzeUserFunction*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, function: ResolvedUserFunction): Result[AnalyzedUserFunction, string] =
  var funcScope: AnalyzedFunctionScope
  let analyzedModuleDef = ? defScope.findModuleDef(module.name, function.loc)
  let analyzedFuncDef = ? analyzedModuleDef.findFunctionDef(function.def)
  for argDef in analyzedFuncDef.args:
    funcScope[argDef.name] = argDef.argType

  var analyzedStatements: seq[AnalyzedStatement]
  for statement in function.statements:
    let analyzedStatement = ? analyzeStatement(app, file, fileScope, module, defScope, funcScope, statement)
    analyzedStatements.add(analyzedStatement)
    if analyzedStatement.arg.isSome:
      let newArg = analyzedStatement.arg.get
      funcScope[newArg.name] = newArg.argType

  #TODO: ensure that last statement always returns a type that matches with the function defintion's return type
  if function.statements.len == 0:
    err(fmt"{function.loc} UNREACHABLE: should have been caught by the resolver")
  else:
    if analyzedStatements[^1].argType.isNone:
      err(fmt"{function.loc} todo: analyze function that returns a literal")
    else:
      if analyzedStatements[^1].argType.get != analyzedFuncDef.returns:
        err(fmt"{function.statements[^1].loc} function does not return the expected return type")
      else:
        ok(newAnalyzedUserFunction(function, analyzedFuncDef, analyzedStatements))

type AnalyzedExternFunction = ref object
  resolved: ResolvedExternFunction
  def: AnalyzedFunctionDefinition

proc newAnalyzedExternFunction(resolved: ResolvedExternFunction, def: AnalyzedFunctionDefinition): AnalyzedExternFunction =
  AnalyzedExternFunction(resolved: resolved, def: def)

type
  AnalyzedFunctionKind = enum
    afkUser, afkExtern
  AnalyzedFunction = ref object
    case kind: AnalyzedFunctionKind
    of afkUser: user: AnalyzedUserFunction
    of afkExtern: extern: AnalyzedExternFunction

proc newAnalyzedFunction(user: AnalyzedUserFunction): AnalyzedFunction =
  AnalyzedFunction(kind: afkUser, user: user)

proc newAnalyzedFunction(extern: AnalyzedExternFunction): AnalyzedFunction =
  AnalyzedFunction(kind: afkExtern, extern: extern)

type AnalyzedModule* = ref object
  def: AnalyzedModuleDefinition
  functions: seq[AnalyzedFunction]

proc newAnalyzedModule(def: AnalyzedModuleDefinition, functions: seq[AnalyzedFunction]): AnalyzedModule =
  AnalyzedModule(def: def, functions: functions)

proc analyzeModule*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope): Result[AnalyzedModule, string] =
  let analyzedModuleDef = ? defScope.findModuleDef(module.name, module.loc)
  var analyzedFunctions: seq[AnalyzedFunction]
  for function in module.functions:
    case function.kind:
    of rfkExtern:
      let analyzedFuncDef = ? analyzedModuleDef.findFunctionDef(function.def)
      analyzedFunctions.add(newAnalyzedFunction(newAnalyzedExternFunction(function.extern, analyzedFuncDef)))
    of rfkUser:
      let analyzedUserFunction = ? analyzeUserFunction(app, file, fileScope, module, defScope, function.user)
      analyzedFunctions.add(newAnalyzedFunction(analyzedUserFunction))
  ok(newAnalyzedModule(analyzedModuleDef, analyzedFunctions))
