## Body-analysis barrel — phase B of the two-pass analyzer, and the
## top of the compiler stack. Consumers say `import analyzer` to get
## everything: the body walkers + public `analyze*` entry here, plus
## the defanalyzer layer beneath (which transitively re-exports
## resolver -> parser -> Location).

import options, results, sequtils, strformat, strutils, tables

import ./analyzer/defanalyzer
export defanalyzer

import ./analyzer/funcscope
import ./analyzer/literalparse
import ./analyzer/unionpatternscope
import ./analyzer/literalpatternscope
import ./analyzer/binding
import ./analyzer/unionpattern
import ./analyzer/casepattern
import ./analyzer/variable
import ./analyzer/literalinit
import ./analyzer/getter
import ./analyzer/statement
import ./analyzer/userfunc
import ./analyzer/externfunc
import ./analyzer/function
import ./analyzer/module
import ./analyzer/filescope
import ./analyzer/importedtype
import ./analyzer/imports
import ./analyzer/file
import ./analyzer/app

proc extractDataDef*(fileScope: AnalyzedFileScope, argType: AnalyzedModuleArgumentType, loc: Location): Result[AnalyzedData, string] =
  let moduleDef = ? fileScope.findModule(argType.module, loc)
  if moduleDef.data.isNone:
    err(fmt"{loc} UNREACHABLE: expression does not return a data type")
  else:
    ok(moduleDef.data.get)

proc extractStructFor*(fileScope: AnalyzedFileScope, argType: AnalyzedModuleArgumentType, loc: Location): Result[AnalyzedStruct, string] =
  let moduleDef = ? fileScope.findModule(argType.module, loc)
  if moduleDef.data.isNone:
    err(fmt"{loc} UNREACHABLE: expression does not return a data type")
  else:
    let dataDef = moduleDef.data.get
    case dataDef.kind:
    of adkStruct: ok(dataDef.struct)
    of adkUnion: err(fmt"{loc} expected module `{moduleDef.name.asl}` to have a struct block but found union")
    of adkLiteral: err(fmt"{loc} expected module `{moduleDef.name.asl}` to have a struct block but found literal")

proc extractUnionFor*(fileScope: AnalyzedFileScope, argType: AnalyzedModuleArgumentType, loc: Location): Result[AnalyzedUnion, string] =
  let moduleDef = ? fileScope.findModule(argType.module, loc)
  if moduleDef.data.isNone:
    err(fmt"{loc} UNREACHABLE: expression does not return a data type")
  else:
    let dataDef = moduleDef.data.get
    case dataDef.kind:
    of adkUnion: ok(dataDef.union)
    of adkStruct: err(fmt"{loc} expected module `{moduleDef.name.asl}` to have a union block but found struct")
    of adkLiteral: err(fmt"{loc} expected module `{moduleDef.name.asl}` to have a union block but found literal")

proc analyzeUnionCasePattern*(appDef: AnalyzedDefApp, fileDef: AnalyzedFileDefinition, module: AnalyzedModuleDefinition, funcScope: AnalyzedFunctionScope, variantPattern: UnionPattern, union: ResolvedUnionDef, subjectImpls: seq[AnalyzedArgumentType]): Result[AnalyzedUnionPattern, string] =
  let variant = ? union.findVariant(variantPattern.name)
  var bindings: seq[AnalyzedBinding]
  for field in variantPattern.fields:
    let resolvedField = ? variant.findField(field.name)
    let analyzedFieldArgType = ? analyzeArgumentType(fileDef.scope, module.resolved, resolvedField.argType)
    let concreteFieldArgType = analyzedFieldArgType.concrete(subjectImpls, union.genericTypeIndex)
    bindings.add((name: field.binding, argType: concreteFieldArgType))
  ok(newAnalyzedUnionPattern(variantPattern, variant, bindings))

proc analyzeCasePattern*(appDef: AnalyzedDefApp, fileDef: AnalyzedFileDefinition, module: AnalyzedModuleDefinition, funcScope: AnalyzedFunctionScope, pattern: ResolvedCasePattern, subjectType: AnalyzedArgumentType, union: ResolvedUnionDef, subjectImpls: seq[AnalyzedArgumentType]): Result[AnalyzedCasePattern, string] =
  case pattern.kind:
  of rcpkInteger: err(fmt"{pattern.loc} UNREACHABLE: integer literals are not allowed in union case pattern")
  of rcpkVariable:
    ok(newAnalyzedCasePattern((name: pattern.variable, argType: subjectType)))
  of rcpkUnion:
    let analyzedPattern = ? analyzeUnionCasePattern(appDef, fileDef, module, funcScope, pattern.variant, union, subjectImpls)
    ok(newAnalyzedCasePattern(analyzedPattern))

proc analyzeCasePattern*(appDef: AnalyzedDefApp, module: AnalyzedModuleDefinition, funcScope: AnalyzedFunctionScope, pattern: ResolvedCasePattern, subjectType: AnalyzedArgumentType): Result[AnalyzedCasePattern, string] =
  case pattern.kind:
  of rcpkUnion:
    err(fmt"{pattern.loc} UNREACHABLE: union variants are not allowed in literal case pattern")
  of rcpkInteger:
    ok(newAnalyzedCasePattern(pattern.integer))
  of rcpkVariable:
    ok(newAnalyzedCasePattern((name: pattern.variable, argType: subjectType)))

proc analyzeIntegerLiteral[T: SomeInteger](literal: Literal, expected: string): Result[void, string] =
  case literal.kind:
  of lkFloat: err(fmt"{literal.loc} expected a valid {expected} but found float")
  of lkString: err(fmt"{literal.loc} expected a valid {expected} but found string")
  of lkInteger:
    let maybeParsedInt = parseInteger[T](literal.asl)
    if maybeParsedInt.isSome: ok()
    else: err(fmt"{literal.loc} expected a valid {expected} but found `{literal.asl}`")

proc analyzeStringLiteral(literal: Literal): Result[void, string] =
  case literal.kind:
  of lkFloat: err(fmt"{literal.loc} expected a valid string literal but found float")
  of lkInteger: err(fmt"{literal.loc} expected a valid string literal but found integer")
  of lkString: ok()

proc analyzeFloatLiteral[T: SomeFloat](literal: Literal, expected: string): Result[void, string] =
  case literal.kind:
  of lkInteger: err(fmt"{literal.loc} expected a valid {expected} but found integer")
  of lkString: err(fmt"{literal.loc} expected a valid {expected} but found string")
  of lkFloat:
    if literal.asl in ["nan", "inf", "+inf", "-inf"]:
      return ok()
    let maybeParsedFloat = parseFloat[T](literal.asl)
    if maybeParsedFloat.isNone:
      return err(fmt"{literal.loc} expected a valid {expected} but found `{literal.asl}`")
    # Exact-representability is a warning, not an error: the closest
    # approximation stored in the parsed value is still returned as
    # the literal's value. Emit to stderr with the source location
    # so users can find and (if they choose) rewrite lossy literals
    # as runtime quotients of exact-integer literals.
    # TODO(diagnostics): thread warnings through the analyzer as a
    # collected seq rather than writing to stderr from deep inside
    # the pass.
    const mantissaBits =
      when T is float32: 24
      elif T is float64: 53
    if not isExactlyRepresentable(literal.asl, mantissaBits):
      stderr.writeLine(fmt"[WARN] {literal.loc} literal `{literal.asl}` cannot be exactly represented in {expected}; using closest approximation")
    ok()

proc analyzeLiteral(literalDef: ResolvedLiteralDef, literal: Literal): Result[void, string] =
  case literalDef:
  of rltkF32: analyzeFloatLiteral[float32](literal, "32-bit float")
  of rltkF64: analyzeFloatLiteral[float64](literal, "64-bit float")
  of rltkPointer: err(fmt"{literal.loc} todo: analyze literal Pointer literal argument")
  of rltkU8: analyzeIntegerLiteral[uint8](literal, "8-bit unsigned integer")
  of rltkU16: analyzeIntegerLiteral[uint16](literal, "16-bit unsigned integer")
  of rltkU32: analyzeIntegerLiteral[uint32](literal, "32-bit unsigned integer")
  of rltkU64: analyzeIntegerLiteral[uint64](literal, "64-bit unsigned integer")
  of rltkI8: analyzeIntegerLiteral[int8](literal, "8-bit signed integer")
  of rltkI16: analyzeIntegerLiteral[int16](literal, "16-bit signed integer")
  of rltkI32: analyzeIntegerLiteral[int32](literal, "32-bit signed integer")
  of rltkI64: analyzeIntegerLiteral[int64](literal, "64-bit signed integer")
  of rltkString: literal.analyzeStringLiteral()

proc analyzeVariable*(scope: AnalyzedFunctionScope, variable: Identifier): Result[AnalyzedVariable, string] =
  if variable in scope: ok(newAnalyzedVariable(variable, scope[variable]))
  else: err(fmt"{variable.loc} variable `{variable.asl}` does not exist in scope")

proc analyzeGetter*(appDef: AnalyzedDefApp, fileDef: AnalyzedFileDefinition, fileScope: AnalyzedFileScope, module: AnalyzedModuleDefinition, funcScope: AnalyzedFunctionScope, getter: ResolvedGetter): Result[AnalyzedGetter, string] =
  if getter.source notin funcScope:
    err(fmt"{getter.loc} variable `{getter.source.asl}` is not present in scope")
  else:
    let analyzedSourceArgType = funcScope[getter.source]
    case analyzedSourceArgType.kind:
    of aatkGeneric:
      err(fmt"{getter.loc} expected `{getter.source.asl}` to be a module but found generic ")
    of aatkModule:
      let struct = ? fileScope.extractStructFor(analyzedSourceArgType.module, getter.loc)
      let property = ? struct.findField(getter.property)
      # TODO: coerce the property type from the generic to concrete
      ok(newAnalyzedGetter(getter, analyzedSourceArgType, property.resolved, property.argType))

proc analyzeLiteralInitializer*(appDef: AnalyzedDefApp, fileDef: AnalyzedFileDefinition, fileScope: AnalyzedFileScope, module: AnalyzedModuleDefinition, funcScope: AnalyzedFunctionScope, init: ResolvedLiteralInitializer): Result[AnalyzedLiteralInitializer, string] =
  let analyzedArgType = ? analyzeArgumentType(fileDef.scope, module.resolved, init.argType)
  case analyzedArgType.kind:
  of aatkGeneric:
    err(fmt"{init.loc} expected `{analyzedArgType.module.name.asl}` to be a module found generic")
  of aatkModule:
    let argDefModule = ? fileScope.findModule(analyzedArgType.module.module, init.loc)
    if argDefModule.data.isNone:
      err(fmt"{init.loc} UNREACHABLE: expression does not return a data type")
    else:
      let argDefData = argDefModule.data.get
      case argDefData.kind:
      of adkStruct: err(fmt"{init.loc} statement expects a literal initializer `{argDefModule.name.asl}`")
      of adkUnion: err(fmt"{init.loc} statement expects a literal initializer `{argDefModule.name.asl}`")
      of adkLiteral:
        let maybeValidLiteral = analyzeLiteral(argDefData.literal.resolved, init.literal)
        if maybeValidLiteral.isOk: ok(newAnalyzedLiteralInitializer(init.literal, analyzedArgType))
        else: err(maybeValidLiteral.error)

# Forward declarations for the analyzeX procs in the cluster.
proc analyzeExpression*(appDef: AnalyzedDefApp, fileDef: AnalyzedFileDefinition, fileScope: AnalyzedFileScope, module: AnalyzedModuleDefinition, funcScope: AnalyzedFunctionScope, expression: ResolvedExpression, expected: Option[AnalyzedArgumentType]): Result[AnalyzedExpression, string]
proc analyzeStatement*(appDef: AnalyzedDefApp, fileDef: AnalyzedFileDefinition, fileScope: AnalyzedFileScope, module: AnalyzedModuleDefinition, funcScope: AnalyzedFunctionScope, statement: ResolvedStatement): Result[AnalyzedStatement, string]
proc analyzeValueTypeAgainstDefType(defType: AnalyzedArgumentType, valType: AnalyzedArgumentType, loc: Location): Result[GenericImplMap, string]

proc analyzeValueTypeAgainstDefType(defType: AnalyzedModuleArgumentType, valType: AnalyzedModuleArgumentType, loc: Location): Result[GenericImplMap, string] =
  if defType.module != valType.module:
    err(fmt"{loc} expected `{defType.name.asl}` but found `{valType.name.asl}`")
  else:
    var genericImplMap: GenericImplMap
    for (defImpl, valImpl) in zip(defType.impls, valType.impls):
      let valGenericImplMap = ? analyzeValueTypeAgainstDefType(defImpl, valImpl, loc)
      genericImplMap = ? genericImplMap.merge(valGenericImplMap)
    ok(genericImplMap)

proc analyzeValueTypeAgainstDefType(defType: AnalyzedModuleArgumentType, valType: AnalyzedArgumentType, loc: Location): Result[GenericImplMap, string] =
  case valType.kind:
  of aatkGeneric:
    err(fmt"{loc} expected a module {defType.asl} type but found generic type {valType.asl}")
  of aatkModule:
    analyzeValueTypeAgainstDefType(defType, valType.module, loc)

proc analyzeValueTypeAgainstDefType(defType: AnalyzedGenericArgumentType, valType: AnalyzedArgumentType, loc: Location): Result[GenericImplMap, string] =
  let funcDefs = defType.resolved.concreteImpls(valType.self)
  for funcDef in funcDefs:
    case valType.kind:
    of aatkGeneric:
      let maybeConcreteFuncDef = valType.generic.resolved.findFunctionDef(funcDef)
      if maybeConcreteFuncDef.isNone:
        return err(fmt"{loc} type `{valType.name.asl}` does not implement function `{funcDef.name.asl}` to support `{defType.resolved.name.asl}`")
    of aatkModule:
      let maybeConcreteFuncDef = valType.module.module.findFunctionDef(funcDef)
      if maybeConcreteFuncDef.isNone:
        return err(fmt"{loc} type `{valType.name.asl}` does not implement function `{funcDef.name.asl}` to support `{defType.resolved.name.asl}`")
  var genericImplMap: GenericImplMap
  genericImplMap[defType.resolved] = valType
  ok(genericImplMap)

# TODO: Return a map of generic -> argType from the recursive analysis
proc analyzeValueTypeAgainstDefType(defType: AnalyzedArgumentType, valType: AnalyzedArgumentType, loc: Location): Result[GenericImplMap, string] =
  case defType.kind:
  of aatkModule: analyzeValueTypeAgainstDefType(defType.module, valType, loc)
  of aatkGeneric: analyzeValueTypeAgainstDefType(defType.generic, valType, loc)

proc analyzeArgumentList*(appDef: AnalyzedDefApp, fileDef: AnalyzedFileDefinition, module: AnalyzedModuleDefinition, funcScope: AnalyzedFunctionScope, argValues: seq[AnalyzedExpression], analyzedFuncDef: AnalyzedFunctionDefinition): Result[GenericImplMap, string] =
  # Reads pre-analyzed args directly from the AnalyzedFunctionDefinition
  # — no lookup, no re-analysis. Every analyzed expression carries a
  # concrete argType post-Approach C; bare literals adopt the caller's
  # expected type or default to i32/f32/String at the
  # analyzeBareLiteral site. Per-candidate type context is threaded
  # from `analyzeFunctionCall`.
  assert(analyzedFuncDef.args.len == argValues.len,
    fmt"BUG: analyzeArgumentList arity mismatch — funcDef has {analyzedFuncDef.args.len} args, call site passed {argValues.len}. zip would silently truncate; fix by erroring (or relying on resolver / overload selection).")
  var genericImplMap: GenericImplMap
  for (analyzedArgDef, argValue) in zip(analyzedFuncDef.args, argValues):
    let argGenericImplMap = ? analyzeValueTypeAgainstDefType(analyzedArgDef.argType, argValue.argType, argValue.loc)
    genericImplMap = ? genericImplMap.merge(argGenericImplMap)
  ok(genericImplMap)

proc analyzeArgumentList(appDef: AnalyzedDefApp, fileDef: AnalyzedFileDefinition, fileScope: AnalyzedFileScope, module: AnalyzedModuleDefinition, funcScope: AnalyzedFunctionScope, fncall: ResolvedFunctionCall, funcDefs: seq[AnalyzedFunctionDefinition]): Result[(AnalyzedFunctionDefinition, seq[AnalyzedExpression], GenericImplMap), string] =
  # Per-candidate analysis over pre-analyzed AnalyzedFunctionDefinition
  # candidates: for each candidate, walk the call's raw arguments and
  # analyze each with the candidate's declared arg type (pre-analyzed)
  # as the expected context. Bare literals adopt the declared type when
  # concrete, or default to i32/f32/String otherwise
  # (`analyzeBareLiteral`). First candidate whose args analyze +
  # type-check wins; ambiguity fires the existing multi-match error
  # path.
  var matches: seq[(AnalyzedFunctionDefinition, seq[AnalyzedExpression], GenericImplMap)]
  var errors: seq[string]
  for index, analyzedFuncDef in funcDefs:
    var analyzedArgs: seq[AnalyzedExpression]
    var candidateErr = ""
    for i in 0..<fncall.args.len:
      let maybeAnalyzed = analyzeExpression(appDef, fileDef, fileScope, module, funcScope, fncall.args[i], some(analyzedFuncDef.args[i].argType))
      if maybeAnalyzed.isErr:
        candidateErr = maybeAnalyzed.error
        break
      analyzedArgs.add(maybeAnalyzed.get)
    if candidateErr.len > 0:
      errors.add(fmt"[{index + 1}] - {candidateErr}")
      errors.add("\t" & fmt"{analyzedFuncDef.loc}: {analyzedFuncDef.asl}")
      continue
    let maybeGenericImplMap = analyzeArgumentList(appDef, fileDef, module, funcScope, analyzedArgs, analyzedFuncDef)
    if maybeGenericImplMap.isOk:
      matches.add((analyzedFuncDef, analyzedArgs, maybeGenericImplMap.get))
    else:
      errors.add(fmt"[{index + 1}] - " & maybeGenericImplMap.error)
      errors.add("\t" & fmt"{analyzedFuncDef.loc}: {analyzedFuncDef.asl}")

  if matches.len == 1:
    ok(matches[0])
  else:
    var message: seq[string]
    if matches.len == 0:
      message.add(fmt"{fncall.loc} failed to find matching function:")
    else:
      message.add(fmt"{fncall.loc} ambiguous function call — multiple candidates match:")
    message.add(errors)
    err(message.join("\n"))

proc analyzeFunctionCall*(appDef: AnalyzedDefApp, fileDef: AnalyzedFileDefinition, fileScope: AnalyzedFileScope, module: AnalyzedModuleDefinition, funcScope: AnalyzedFunctionScope, fncall: ResolvedFunctionCall): Result[AnalyzedFunctionCall, string] =
  let typ = ? fileDef.scope.findType(fncall.typ, fncall.loc)
  let public =
    case typ.kind:
    of rtkModule: (module.resolved != typ.module)
    of rtkGeneric: true
  let definedType = ? fileScope.findType(typ, fncall.loc)
  let funcDefs = ? definedType.findFunctionDefs(fncall.parsed.name, fncall.parsed.args.len, public)

  let (matchingFuncDef, analyzedArgs, genericImpls) = ? analyzeArgumentList(appDef, fileDef, fileScope, module, funcScope, fncall, funcDefs)
  # Return type comes pre-analyzed from the AnalyzedFunctionDefinition;
  # apply the caller's inferred generic-impl substitution to concretize
  # any free generics the return type touches.
  let concreteReturns = matchingFuncDef.returns.concrete(genericImpls)
  ok(newAnalyzedFunctionCall(fncall, matchingFuncDef.resolved, analyzedArgs, concreteReturns))

proc analyzeCaseBlock*(appDef: AnalyzedDefApp, fileDef: AnalyzedFileDefinition, fileScope: AnalyzedFileScope, module: AnalyzedModuleDefinition, funcScope: AnalyzedFunctionScope, caseBlock: ResolvedCaseBlock, subjectType: AnalyzedArgumentType, union: ResolvedUnionDef, subjectImpls: seq[AnalyzedArgumentType]): Result[AnalyzedCaseBlock, string] =
  var caseScope = funcScope

  let analyzedCasePattern = ? analyzeCasePattern(appDef, fileDef, module, funcScope, caseBlock.pattern, subjectType, union, subjectImpls)
  caseScope = caseScope.update(analyzedCasePattern)

  var analyzedStatements: seq[AnalyzedStatement]
  for statement in caseBlock.statements:
    let analyzedStatement = ? analyzeStatement(appDef, fileDef, fileScope, module, caseScope, statement)
    analyzedStatements.add(analyzedStatement)
    caseScope = caseScope.update(analyzedStatement)
  ok(newAnalyzedCaseBlock(caseBlock, analyzedCasePattern, analyzedStatements))

proc analyzeCaseBlock*(appDef: AnalyzedDefApp, fileDef: AnalyzedFileDefinition, fileScope: AnalyzedFileScope, module: AnalyzedModuleDefinition, funcScope: AnalyzedFunctionScope, caseBlock: ResolvedCaseBlock, subjectType: AnalyzedArgumentType): Result[AnalyzedCaseBlock, string] =
  var caseScope = funcScope

  let analyzedCasePattern = ? analyzeCasePattern(appDef, module, funcScope, caseBlock.pattern, subjectType)
  caseScope = caseScope.update(analyzedCasePattern)

  var analyzedStatements: seq[AnalyzedStatement]
  for statement in caseBlock.statements:
    let analyzedStatement = ? analyzeStatement(appDef, fileDef, fileScope, module, caseScope, statement)
    analyzedStatements.add(analyzedStatement)
    caseScope = caseScope.update(analyzedStatement)
  ok(newAnalyzedCaseBlock(caseBlock, analyzedCasePattern, analyzedStatements))

proc verifyUniformReturnType(cases: seq[AnalyzedCaseBlock]): Result[void, string] =
  let expected = cases[0].argType
  for c in cases:
    if c.argType != expected:
      return err(fmt"{c.loc} todo: return an error message telling that the case block return types are not same")
  ok()

proc analyzeCases*(appDef: AnalyzedDefApp, fileDef: AnalyzedFileDefinition, fileScope: AnalyzedFileScope, module: AnalyzedModuleDefinition, funcScope: AnalyzedFunctionScope, cases: seq[ResolvedCaseBlock], subjectType: AnalyzedArgumentType, union: ResolvedUnionDef, subjectImpls: seq[AnalyzedArgumentType], loc: Location): Result[seq[AnalyzedCaseBlock], string] =
  var patternScope = newAnalyzedUnionPatternScope(cases.len)
  for id, caseBlock in cases:
    patternScope = ? patternScope.update(id, caseBlock.pattern)

  ? hasUncoveredCases(patternScope, union.variants.len, loc)

  assert(cases.len > 0, "UNREACHABLE: zero-case match should have been caught by the resolver")

  var analyzedCaseBlocks: seq[AnalyzedCaseBlock]
  for caseBlock in cases:
    let analyzedCaseBlock = ? analyzeCaseBlock(appDef, fileDef, fileScope, module, funcScope, caseBlock, subjectType, union, subjectImpls)
    analyzedCaseBlocks.add(analyzedCaseBlock)
  ? verifyUniformReturnType(analyzedCaseBlocks)
  ok(analyzedCaseBlocks)

proc analyzeCases*(appDef: AnalyzedDefApp, fileDef: AnalyzedFileDefinition, fileScope: AnalyzedFileScope, module: AnalyzedModuleDefinition, funcScope: AnalyzedFunctionScope, cases: seq[ResolvedCaseBlock], subjectType: AnalyzedArgumentType, literal: ResolvedLiteralDef, loc: Location): Result[seq[AnalyzedCaseBlock], string] =
  var patternScope = ? newAnalyzedLiteralPatternScope(literal, cases.len)
  for id, caseBlock in cases:
    patternScope = ? patternScope.update(id, caseBlock.pattern)

  ? hasUncoveredCases(patternScope, loc)

  assert(cases.len > 0, "UNREACHABLE: zero-case match should have been caught by the resolver")

  var analyzedCaseBlocks: seq[AnalyzedCaseBlock]
  for caseBlock in cases:
    let analyzedCaseBlock = ? analyzeCaseBlock(appDef, fileDef, fileScope, module, funcScope, caseBlock, subjectType)
    analyzedCaseBlocks.add(analyzedCaseBlock)
  ? verifyUniformReturnType(analyzedCaseBlocks)
  ok(analyzedCaseBlocks)

proc analyzeMatchExpression*(appDef: AnalyzedDefApp, fileDef: AnalyzedFileDefinition, fileScope: AnalyzedFileScope, module: AnalyzedModuleDefinition, funcScope: AnalyzedFunctionScope, match: ResolvedMatchExpression): Result[AnalyzedMatchExpression, string] =
  let analyzedSubjectExpr = ? analyzeExpression(appDef, fileDef, fileScope, module, funcScope, match.subject, none(AnalyzedArgumentType))
  let subjectArgType = analyzedSubjectExpr.argType
  case subjectArgType.kind:
  of aatkGeneric:
    err(fmt"{match.subject.loc} expected subject expression to return a module but found generic")
  of aatkModule:
    let analyzedSubjectDataType = ? fileScope.extractDataDef(subjectArgType.module, analyzedSubjectExpr.loc)
    case analyzedSubjectDataType.kind:
    of adkStruct:
      err(fmt"{match.loc} match block only supports literal and union types but subject expression returns `{subjectArgType.name.asl}` a struct type")
    of adkLiteral:
      if match.cases.len == 0:
        err(fmt"{match.loc} UNREACHABLE: match block does not contain any case blocks")
      else:
        let analyzedCases = ? analyzeCases(appDef, fileDef, fileScope, module, funcScope, match.cases, subjectArgType, analyzedSubjectDataType.literal.resolved, match.loc)
        ok(newAnalyzedMatchExpression(match, analyzedSubjectExpr, analyzedCases, analyzedCases[0].argType))
    of adkUnion:
      if match.cases.len == 0:
        err(fmt"{match.loc} UNREACHABLE: match block does not contain any case blocks")
      else:
        case subjectArgType.kind:
        of aatkGeneric:
          err(fmt"{match.loc} UNREACHABLE: match block does not support generic types in subject expression")
        of aatkModule:
          let impls = subjectArgType.module.impls
          let analyzedCases = ? analyzeCases(appDef, fileDef, fileScope, module, funcScope, match.cases, subjectArgType, analyzedSubjectDataType.union.resolved, impls, match.loc)
          ok(newAnalyzedMatchExpression(match, analyzedSubjectExpr, analyzedCases, analyzedCases[0].argType))

proc analyzeKeywordArgument*(appDef: AnalyzedDefApp, fileDef: AnalyzedFileDefinition, fileScope: AnalyzedFileScope, module: AnalyzedModuleDefinition, funcScope: AnalyzedFunctionScope, kwarg: ResolvedKeywordArgument, analyzedField: ResolvedArgumentDef, analyzedFieldArgType: AnalyzedArgumentType): Result[AnalyzedKeywordArgument, string] =
  # Field's declared type is the expected context — bare literals in
  # kwarg values adapt when concrete, default when generic.
  let analyzedExpression = ? analyzeExpression(appDef, fileDef, fileScope, module, funcScope, kwarg.expression, some(analyzedFieldArgType))
  # TODO: Utilize the returned generic impl map
  discard ? analyzeValueTypeAgainstDefType(analyzedFieldArgType, analyzedExpression.argType, analyzedExpression.loc)
  ok(newAnalyzedKeywordArgument(kwarg, analyzedField, analyzedExpression))

proc analyzeUnionRef(appDef: AnalyzedDefApp, fileDef: AnalyzedFileDefinition, module: AnalyzedModuleDefinition, unionRef: ResolvedUnionRef): Result[AnalyzedUnionRef, string] =
  ## Walks the resolver's already-checked `impls` seq once and
  ## produces the analyzer-side equivalents. Empty in → empty out.
  ## Parser-Module → ResolvedModule via identity lookup on fileScope —
  ## immune to aliased-import name mismatch.
  let resolvedModule = ? fileDef.scope.findModule(unionRef.module, unionRef.loc)
  var analyzedImpls = newSeq[AnalyzedArgumentType](unionRef.impls.len)
  for i, resolvedImpl in unionRef.impls:
    analyzedImpls[i] = ? analyzeArgumentType(fileDef.scope, module.resolved, resolvedImpl)
  ok(newAnalyzedUnionRef(unionRef, resolvedModule, analyzedImpls))

proc analyzeUnionInitializer*(appDef: AnalyzedDefApp, fileDef: AnalyzedFileDefinition, fileScope: AnalyzedFileScope, module: AnalyzedModuleDefinition, funcScope: AnalyzedFunctionScope, init: ResolvedUnionInitializer): Result[AnalyzedUnionInitializer, string] =
  ## Single code path over the union initializer:
  ## - If the surface form supplied explicit impls, the resolver has
  ##   already threaded them into `analyzedImpls`. We seed implMap
  ##   positionally from that seq up front, then skip the merge-from-
  ##   kwarg step so no inference happens.
  ## - If the surface form was bare, `analyzedImpls` is empty. The seed
  ##   loop is a no-op and the kwarg walk accumulates the implMap via
  ##   value-vs-field type matches (leave-as-is).
  ## Result-type construction is a single loop over the union's
  ## genericTypeIndex: fill bound positions from implMap, leave uncovered
  ## positions as free generics for downstream unification.
  let analyzedUnionRef = ? analyzeUnionRef(appDef, fileDef, module, init.unionRef)
  let receiver = analyzedUnionRef.module
  if receiver.data.isNone:
    return err(fmt"{init.loc} module `{receiver.name.asl}` is not a union")
  let dataDef = receiver.data.get
  case dataDef.kind:
  of rdkLiteral: return err(fmt"{init.loc} module `{receiver.name.asl}` is a literal")
  of rdkStruct: return err(fmt"{init.loc} module `{receiver.name.asl}` is a struct")
  of rdkUnion: discard
  let resolvedUnion = dataDef.union
  let resolvedVariant = ? resolvedUnion.findVariant(init.variant)
  let analyzedImpls = analyzedUnionRef.analyzedImpls
  let hasExplicitImpls = analyzedImpls.len > 0

  # Seed implMap positionally from the resolver-checked explicit impls
  # (empty seq → no-op, preserving the bare/leave-as-is path).
  var implMap: GenericImplMap
  for genericArgType, position in resolvedUnion.genericTypeIndex:
    if position < analyzedImpls.len:
      # `genericArgType.parsed` is the parser-side Generic;
      # GenericImplMap keys on ResolvedGeneric. Translate through
      # analyzeArgumentType so the resolved generic is looked up via
      # the file scope.
      let analyzedGeneric = ? analyzeArgumentType(fileDef.scope, module.resolved, newResolvedArgumentType(genericArgType))
      implMap[analyzedGeneric.generic.resolved] = analyzedImpls[position]

  # Walk kwargs. Substitute the variant's field type via implMap before
  # type-checking — equivalent to direct match on the bare path
  # (implMap seeded from kwargs), full concretization on the explicit-
  # impls path (implMap already seeded, merge-from-kwarg skipped so no
  # inference happens).
  var analyzedKwargs: seq[AnalyzedKeywordArgument]
  for kwarg in init.kwargs:
    let resolvedField = ? resolvedVariant.findField(kwarg.name)
    let analyzedFieldArgType = ? analyzeArgumentType(fileDef.scope, module.resolved, resolvedField.argType)
    # Concretize the field type via the current implMap before analyzing
    # the value so bare-literal kwargs adopt the concrete instantiation
    # when known, and default (i32/f32/String) when the field is still
    # a free generic on the bare path.
    let fieldType = analyzedFieldArgType.concrete(implMap)
    let analyzedExpression = ? analyzeExpression(appDef, fileDef, fileScope, module, funcScope, kwarg.expression, some(fieldType))
    let local = ? analyzeValueTypeAgainstDefType(fieldType, analyzedExpression.argType, analyzedExpression.loc)
    if not hasExplicitImpls:
      implMap = ? implMap.merge(local)
    analyzedKwargs.add(newAnalyzedKeywordArgument(kwarg, resolvedField, analyzedExpression))

  # Build the result type. One loop over the union's genericTypeIndex
  # positions: bound positions read from implMap (seeded from explicit
  # impls or accumulated via kwargs), free positions get a fresh
  # AnalyzedGenericArgumentType for downstream unification.
  var impls = newSeq[AnalyzedArgumentType](resolvedUnion.genericTypeIndex.len)
  for genericArgType, position in resolvedUnion.genericTypeIndex:
    let analyzedGeneric = ? analyzeArgumentType(fileDef.scope, module.resolved, newResolvedArgumentType(genericArgType))
    if analyzedGeneric.generic.resolved in implMap:
      impls[position] = implMap[analyzedGeneric.generic.resolved]
    else:
      impls[position] = analyzedGeneric
  let resolvedSelfArg = receiver.self
  let analyzedModuleArg = newAnalyzedModuleArgumentType(resolvedSelfArg, receiver, impls)
  let argType = newAnalyzedArgumentType(analyzedModuleArg)

  ok(newAnalyzedUnionInitializer(init, analyzedUnionRef, argType, resolvedVariant, analyzedKwargs))

proc analyzeStructRef(appDef: AnalyzedDefApp, fileDef: AnalyzedFileDefinition, module: AnalyzedModuleDefinition, structRef: ResolvedStructRef): Result[AnalyzedStructRef, string] =
  ## Walks the resolver's already-checked `impls` seq once and
  ## produces the analyzer-side equivalents. Empty in → empty out.
  ## The parser Module carried on `structRef.module` is looked up here
  ## into a ResolvedModule via `fileDef.scope.findModule` (identity-keyed) — the
  ## resolver keeps struct/union refs parser-level to break the ref
  ## cycle; analyzer types can hold the resolved view freely.
  let resolvedModule = ? fileDef.scope.findModule(structRef.module, structRef.loc)
  var analyzedImpls = newSeq[AnalyzedArgumentType](structRef.impls.len)
  for i, resolvedImpl in structRef.impls:
    analyzedImpls[i] = ? analyzeArgumentType(fileDef.scope, module.resolved, resolvedImpl)
  ok(newAnalyzedStructRef(structRef, resolvedModule, analyzedImpls))

proc analyzeStructInitializer*(appDef: AnalyzedDefApp, fileDef: AnalyzedFileDefinition, fileScope: AnalyzedFileScope, module: AnalyzedModuleDefinition, funcScope: AnalyzedFunctionScope, init: ResolvedStructInitializer): Result[AnalyzedStructInitializer, string] =
  ## Single code path over the struct initializer. Receiver is the
  ## resolver's already-resolved module; result argType wraps the
  ## analyzedImpls seq (empty when the surface form was bare — matches
  ## the receiverArgType() no-impls shape; non-empty when explicit
  ## impls were supplied and arity+constraint-checked at resolve time).
  ## TODO: Inference for uncovered generic positions on the bare path
  ## still lives with the caller of receiverArgType — folded into the
  ## same seq-based build here.
  let analyzedStructRef = ? analyzeStructRef(appDef, fileDef, module, init.structRef)
  let receiver = analyzedStructRef.module
  if receiver.data.isNone:
    return err(fmt"{init.loc} module `{receiver.name.asl}` is not a struct")
  let dataDef = receiver.data.get
  case dataDef.kind:
  of rdkLiteral: err(fmt"{init.loc} module `{receiver.name.asl}` is a literal")
  of rdkUnion: err(fmt"{init.loc} module `{receiver.name.asl}` is a union")
  of rdkStruct:
    var analyzedKwargs: seq[AnalyzedKeywordArgument]
    for kwarg in init.kwargs:
      let resolvedField = ? dataDef.struct.findField(kwarg.name)
      let analyzedFieldArgType = ? analyzeArgumentType(fileDef.scope, module.resolved, resolvedField.argType)
      let analyzedKwarg = ? analyzeKeywordArgument(appDef, fileDef, fileScope, module, funcScope, kwarg, resolvedField, analyzedFieldArgType)
      analyzedKwargs.add(analyzedKwarg)
    let argType =
      if analyzedStructRef.analyzedImpls.len == 0:
        newAnalyzedArgumentType(receiver)
      else:
        let resolvedSelfArg = receiver.self
        let analyzedModuleArg = newAnalyzedModuleArgumentType(resolvedSelfArg, receiver, analyzedStructRef.analyzedImpls)
        newAnalyzedArgumentType(analyzedModuleArg)
    ok(newAnalyzedStructInitializer(init, analyzedStructRef, argType, analyzedKwargs))

proc analyzeInitializer*(appDef: AnalyzedDefApp, fileDef: AnalyzedFileDefinition, fileScope: AnalyzedFileScope, module: AnalyzedModuleDefinition, funcScope: AnalyzedFunctionScope, init: ResolvedInitializer): Result[AnalyzedInitializer, string] =
  case init.kind:
  of rikLiteral:
    let analyzedLiteralInit = ? analyzeLiteralInitializer(appDef, fileDef, fileScope, module, funcScope, init.literal)
    ok(newAnalyzedInitializer(analyzedLiteralInit))
  of rikStruct:
    let analyzedStructInit = ? analyzeStructInitializer(appDef, fileDef, fileScope, module, funcScope, init.struct)
    ok(newAnalyzedInitializer(analyzedStructInit))
  of rikUnion:
    let analyzedUnionInit = ? analyzeUnionInitializer(appDef, fileDef, fileScope, module, funcScope, init.union)
    ok(newAnalyzedInitializer(analyzedUnionInit))

proc analyzeBareLiteral(appDef: AnalyzedDefApp, fileDef: AnalyzedFileDefinition, fileScope: AnalyzedFileScope, module: AnalyzedModuleDefinition, funcScope: AnalyzedFunctionScope, literal: Literal, expected: Option[AnalyzedArgumentType]): Result[AnalyzedLiteralInitializer, string] =
  ## Approach C — pick a concrete type for the bare literal.
  ##   - `expected = some(module)`  → adopt the module type. If the
  ##     module's data def is struct/union the caller wrote a literal
  ##     where an initializer was expected → error with a clear message.
  ##   - `expected = some(generic)` → default (the binding contributes
  ##     to the generic-impl map at the call site).
  ##   - `expected = none`          → default (bare assignment / bare
  ##     statement).
  ## Then fit-check the value against the chosen module's literal spec.
  let concreteArgType =
    if expected.isSome:
      case expected.get.kind:
      of aatkModule: expected.get
      of aatkGeneric: ? fileDef.defaultLiteralType(literal)
    else:
      ? fileDef.defaultLiteralType(literal)

  case concreteArgType.kind:
  of aatkGeneric:
    err(fmt"{literal.loc} expected a module `{concreteArgType.name.asl}` but found generic")
  of aatkModule:
    let argDefModule = ? fileScope.findModule(concreteArgType.module.module, literal.loc)
    if argDefModule.data.isNone:
      err(fmt"{literal.loc} UNREACHABLE: expression does not return a data type")
    else:
      let argDefData = argDefModule.data.get
      case argDefData.kind:
      of adkStruct: err(fmt"{literal.loc} expected a struct initializer of type `{argDefModule.name.asl}` but found bare literal")
      of adkUnion: err(fmt"{literal.loc} expected a union initializer of type `{argDefModule.name.asl}` but found bare literal")
      of adkLiteral:
        ? analyzeLiteral(argDefData.literal.resolved, literal)
        ok(newAnalyzedLiteralInitializer(literal, concreteArgType))

proc analyzeExpression*(appDef: AnalyzedDefApp, fileDef: AnalyzedFileDefinition, fileScope: AnalyzedFileScope, module: AnalyzedModuleDefinition, funcScope: AnalyzedFunctionScope, expression: ResolvedExpression, expected: Option[AnalyzedArgumentType]): Result[AnalyzedExpression, string] =
  case expression.kind:
  of rekLiteral:
    let bareLit = ? analyzeBareLiteral(appDef, fileDef, fileScope, module, funcScope, expression.literal, expected)
    ok(newAnalyzedExpression(newAnalyzedInitializer(bareLit)))
  of rekVariable:
    let analyzedVariable = ? analyzeVariable(funcScope, expression.variable)
    ok(newAnalyzedExpression(analyzedVariable))
  of rekGetter:
    let analyzedGetter = ? analyzeGetter(appDef, fileDef, fileScope, module, funcScope, expression.getter)
    ok(newAnalyzedExpression(analyzedGetter))
  of rekInitializer:
    let analyzedInit = ? analyzeInitializer(appDef, fileDef, fileScope, module, funcScope, expression.init)
    ok(newAnalyzedExpression(analyzedInit))
  of rekFunctionCall:
    let analyzedFunctionCall = ? analyzeFunctionCall(appDef, fileDef, fileScope, module, funcScope, expression.fncall)
    ok(newAnalyzedExpression(analyzedFunctionCall))
  of rekMatchExpr:
    let analyzedMatchExpr = ? analyzeMatchExpression(appDef, fileDef, fileScope, module, funcScope, expression.match)
    ok(newAnalyzedExpression(analyzedMatchExpr))

proc analyzeAssignment*(appDef: AnalyzedDefApp, fileDef: AnalyzedFileDefinition, fileScope: AnalyzedFileScope, module: AnalyzedModuleDefinition, funcScope: AnalyzedFunctionScope, assignment: ResolvedAssignment): Result[AnalyzedAssignment, string] =
  let analyzedExpr = ? analyzeExpression(appDef, fileDef, fileScope, module, funcScope, assignment.expression, none(AnalyzedArgumentType))
  ok(newAnalyzedAssignment(assignment, analyzedExpr))

proc analyzeSetter*(appDef: AnalyzedDefApp, fileDef: AnalyzedFileDefinition, fileScope: AnalyzedFileScope, module: AnalyzedModuleDefinition, funcScope: AnalyzedFunctionScope, setter: ResolvedSetter): Result[AnalyzedSetter, string] =
  let analyzedGetter = ? analyzeGetter(appDef, fileDef, fileScope, module, funcScope, setter.getter)
  let analyzedExpression = ? analyzeExpression(appDef, fileDef, fileScope, module, funcScope, setter.expression, some(analyzedGetter.argType))
  if analyzedGetter.argType != analyzedExpression.argType:
    err(fmt"{setter.loc} argument type mismatch") # TODO: improve error message
  else:
    ok(newAnalyzedSetter(setter, analyzedGetter, analyzedExpression))

proc analyzeStatement*(appDef: AnalyzedDefApp, fileDef: AnalyzedFileDefinition, fileScope: AnalyzedFileScope, module: AnalyzedModuleDefinition, funcScope: AnalyzedFunctionScope, statement: ResolvedStatement): Result[AnalyzedStatement, string] =
  case statement.kind:
  of rskExpr:
    let analyzedExpr = ? analyzeExpression(appDef, fileDef, fileScope, module, funcScope, statement.expression, none(AnalyzedArgumentType))
    ok(newAnalyzedStatement(analyzedExpr))
  of rskAssignment:
    let analyzedAssignment = ? analyzeAssignment(appDef, fileDef, fileScope, module, funcScope, statement.assignment)
    ok(newAnalyzedStatement(analyzedAssignment))
  of rskSetter:
    let analyzedMutation = ? analyzeSetter(appDef, fileDef, fileScope, module, funcScope, statement.setter)
    ok(newAnalyzedStatement(analyzedMutation))

proc analyzeUserFunction*(appDef: AnalyzedDefApp, fileDef: AnalyzedFileDefinition, fileScope: AnalyzedFileScope, module: AnalyzedModuleDefinition, function: ResolvedUserFunction): Result[AnalyzedUserFunction, string] =
  let analyzedFunctionDef = ? module.findFunctionDef(function.def)
  var funcScope = newAnalyzedFunctionScope(analyzedFunctionDef)
  assert(function.statements.len > 0, fmt"{function.loc} [BUG] empty user function must have been caught by the resolver")

  var analyzedStatements: seq[AnalyzedStatement]
  for statement in function.statements:
    let analyzedStatement = ? analyzeStatement(appDef, fileDef, fileScope, module, funcScope, statement)
    analyzedStatements.add(analyzedStatement)
    funcScope = funcScope.update(analyzedStatement)

  if analyzedStatements[^1].argType != analyzedFunctionDef.returns:
    err(fmt"{function.statements[^1].loc} function does not return the expected return type")
  else:
    ok(newAnalyzedUserFunction(function, analyzedFunctionDef, analyzedStatements))

proc analyzeExternFunction(moduleDef: AnalyzedModuleDefinition, function: ResolvedExternFunction): Result[AnalyzedExternFunction, string] =
  let analyzedFunctionDef = ? moduleDef.findFunctionDef(function.def)
  ok(newAnalyzedExternFunction(function, analyzedFunctionDef))

proc analyzeFunction(appDef: AnalyzedDefApp, fileDef: AnalyzedFileDefinition, fileScope: AnalyzedFileScope, module: AnalyzedModuleDefinition, function: ResolvedFunction): Result[AnalyzedFunction, string] =
  case function.kind:
  of rfkExtern:
    let analyzedExternFunction = ? module.analyzeExternFunction(function.extern)
    ok(newAnalyzedFunction(analyzedExternFunction))
  of rfkUser:
    let analyzedUserFunction = ? analyzeUserFunction(appDef, fileDef, fileScope, module, function.user)
    ok(newAnalyzedFunction(analyzedUserFunction))

proc analyzeModule*(appDef: AnalyzedDefApp, fileDef: AnalyzedFileDefinition, fileScope: AnalyzedFileScope, module: AnalyzedModuleDefinition): Result[AnalyzedModule, string] =
  var analyzedFunctions: seq[AnalyzedFunction]
  for function in module.resolved.functions:
    let analyzedFunction = ? analyzeFunction(appDef, fileDef, fileScope, module, function)
    analyzedFunctions.add(analyzedFunction)
  ok(newAnalyzedModule(module, analyzedFunctions))

proc analyzeImportedType*(impFile: AnalyzedFileDefinition, impType: AnalyzedImportedTypeDef): Result[AnalyzedImportedType, string] =
  let analyzedImpType = ? impFile.findType(impType.typ, impType.loc)
  ok(newAnalyzedImportedType(impType, analyzedImpType))

proc analyzeImport*(appDef: AnalyzedDefApp, imp: AnalyzedImportDefinition): Result[AnalyzedImport, string] =
  let impFile = ? appDef.findFileDef(imp.path)
  var analyzedImpTypes: seq[AnalyzedImportedType]
  for impType in imp.importedTypes:
    let analyzedImportedType = ? analyzeImportedType(impFile, impType)
    analyzedImpTypes.add(analyzedImportedType)
  ok(newAnalyzedImport(imp, analyzedImpTypes))

proc analyzeFile(appDef: AnalyzedDefApp, fileDef: AnalyzedFileDefinition): Result[AnalyzedFile, string] =
  var analyzedImports: seq[AnalyzedImport]
  for imp in fileDef.imports:
    let analyzedImport = ? analyzeImport(appDef, imp)
    analyzedImports.add(analyzedImport)

  let fileScope = ? newAnalyzedFileScope(analyzedImports, fileDef.types)
  var analyzedModules: seq[AnalyzedModule]
  for module in fileDef.resolved.modules:
    let analyzedModuleDef = ? fileScope.findModule(module, module.loc)
    let analyzedModule = ? analyzeModule(appDef, fileDef, fileScope, analyzedModuleDef)
    analyzedModules.add(analyzedModule)
  ok(newAnalyzedFile(fileDef, fileDef.imports, analyzedModules))

proc analyze*(app: ResolvedApp): Result[AnalyzedApp, string] =
  let appDef = ? analyzeAppDefinition(app)
  var analyzedFiles: seq[AnalyzedFile]
  for fileDef in appDef.fileDefs:
    let analyzedFile = ? analyzeFile(appDef, fileDef)
    analyzedFiles.add(analyzedFile)
  ok(newAnalyzedApp(app, analyzedFiles))
