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
import ./analyzer/file
import ./analyzer/app

proc findModuleDef*(appDef: AnalyzedAppDefinition, argType: AnalyzedArgumentType, loc: Location): Result[AnalyzedModuleDefinition, string] =
  case argType.kind:
  of aatkGeneric:
    err(fmt"{loc} todo: extract module def for a generic subject type")
  of aatkModule:
    let definedType = ? appDef.findDefinedType(newResolvedType(argType.module.module))
    case definedType.kind:
    of adtkModule: ok(definedType.module)
    of adtkGeneric:
      err(fmt"{loc} UNREACHABLE: argType is aatkModule but definedType is adtkGeneric")

proc extractDataDef*(moduleDef: AnalyzedModuleDefinition, loc: Location): Result[AnalyzedData, string] =
  if moduleDef.data.isNone:
    err(fmt"{loc} UNREACHABLE: expression does not return a data type")
  else:
    ok(moduleDef.data.get)

proc extractDataDef*(appDef: AnalyzedAppDefinition, argType: AnalyzedArgumentType, loc: Location): Result[AnalyzedData, string] =
  let moduleDef = ? findModuleDef(appDef, argType, loc)
  extractDataDef(moduleDef, loc)

proc extractStructFor*(appDef: AnalyzedAppDefinition, argType: AnalyzedArgumentType, loc: Location): Result[AnalyzedStruct, string] =
  let moduleDef = ? findModuleDef(appDef, argType, loc)
  let dataDef = ? extractDataDef(moduleDef, loc)
  case dataDef.kind:
  of adkStruct: ok(dataDef.struct)
  of adkUnion: err(fmt"{loc} expected module `{moduleDef.name.asl}` to have a struct block but found union")
  of adkLiteral: err(fmt"{loc} expected module `{moduleDef.name.asl}` to have a struct block but found literal")

proc extractUnionFor*(appDef: AnalyzedAppDefinition, argType: AnalyzedArgumentType, loc: Location): Result[AnalyzedUnion, string] =
  let moduleDef = ? findModuleDef(appDef, argType, loc)
  let dataDef = ? extractDataDef(moduleDef, loc)
  case dataDef.kind:
  of adkUnion: ok(dataDef.union)
  of adkStruct: err(fmt"{loc} expected module `{moduleDef.name.asl}` to have a union block but found struct")
  of adkLiteral: err(fmt"{loc} expected module `{moduleDef.name.asl}` to have a union block but found literal")

proc analyzeUnionCasePattern*(appDef: AnalyzedAppDefinition, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, variantPattern: UnionPattern, union: ResolvedUnionDef, subjectImpls: seq[AnalyzedArgumentType]): Result[AnalyzedUnionPattern, string] =
  let variant = ? union.findVariant(variantPattern.name)
  var bindings: seq[AnalyzedBinding]
  for field in variantPattern.fields:
    let resolvedField = ? variant.findField(field.name)
    let analyzedFieldArgType = ? analyzeArgumentType(fileScope, module, resolvedField.argType)
    let concreteFieldArgType = analyzedFieldArgType.concrete(subjectImpls, union.genericTypeIndex)
    bindings.add((name: field.binding, argType: concreteFieldArgType))
  ok(newAnalyzedUnionPattern(variantPattern, variant, bindings))

proc analyzeCasePattern*(appDef: AnalyzedAppDefinition, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, pattern: ResolvedCasePattern, subjectType: AnalyzedArgumentType, union: ResolvedUnionDef, subjectImpls: seq[AnalyzedArgumentType]): Result[AnalyzedCasePattern, string] =
  case pattern.kind:
  of rcpkInteger: err(fmt"{pattern.loc} UNREACHABLE: integer literals are not allowed in union case pattern")
  of rcpkVariable:
    ok(newAnalyzedCasePattern((name: pattern.variable, argType: subjectType)))
  of rcpkUnion:
    let analyzedPattern = ? analyzeUnionCasePattern(appDef, fileScope, module, funcScope, pattern.variant, union, subjectImpls)
    ok(newAnalyzedCasePattern(analyzedPattern))

proc analyzeCasePattern*(appDef: AnalyzedAppDefinition, module: ResolvedModule, funcScope: AnalyzedFunctionScope, pattern: ResolvedCasePattern, subjectType: AnalyzedArgumentType): Result[AnalyzedCasePattern, string] =
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

proc analyzeGetter*(appDef: AnalyzedAppDefinition, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, getter: ResolvedGetter): Result[AnalyzedGetter, string] =
  if getter.source notin funcScope:
    err(fmt"{getter.loc} variable `{getter.source.asl}` is not present in scope")
  else:
    let analyzedSourceArgType = funcScope[getter.source]
    let struct = ? extractStructFor(appDef, analyzedSourceArgType, getter.loc)
    let property = ? struct.findField(getter.property)
    # TODO: coerce the property type from the generic to concrete
    ok(newAnalyzedGetter(getter, analyzedSourceArgType, property.resolved, property.argType))

proc analyzeLiteralInitializer*(appDef: AnalyzedAppDefinition, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, init: ResolvedLiteralInitializer): Result[AnalyzedLiteralInitializer, string] =
  let analyzedArgType = ? analyzeArgumentType(fileScope, module, init.argType)
  let argDefModule = ? findModuleDef(appDef, analyzedArgType, init.loc)
  let argDefData = ? extractDataDef(argDefModule, init.loc)
  case argDefData.kind:
  of adkStruct: err(fmt"{init.loc} statement expects a literal initializer `{argDefModule.name.asl}`")
  of adkUnion: err(fmt"{init.loc} statement expects a literal initializer `{argDefModule.name.asl}`")
  of adkLiteral:
    let maybeValidLiteral = analyzeLiteral(argDefData.literal.resolved, init.literal)
    if maybeValidLiteral.isOk: ok(newAnalyzedLiteralInitializer(init.literal, analyzedArgType))
    else: err(maybeValidLiteral.error)

# Forward declarations for the analyzeX procs in the cluster.
proc analyzeExpression*(appDef: AnalyzedAppDefinition, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, expression: ResolvedExpression, expected: Option[AnalyzedArgumentType]): Result[AnalyzedExpression, string]
proc analyzeStatement*(appDef: AnalyzedAppDefinition, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, statement: ResolvedStatement): Result[AnalyzedStatement, string]
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

proc analyzeArgumentList*(appDef: AnalyzedAppDefinition, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, argValues: seq[AnalyzedExpression], analyzedFuncDef: AnalyzedFunctionDefinition): Result[GenericImplMap, string] =
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

proc analyzeArgumentList(appDef: AnalyzedAppDefinition, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, fncall: ResolvedFunctionCall, funcDefs: seq[AnalyzedFunctionDefinition]): Result[(AnalyzedFunctionDefinition, seq[AnalyzedExpression], GenericImplMap), string] =
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
      let maybeAnalyzed = analyzeExpression(appDef, file, fileScope, module, funcScope, fncall.args[i], some(analyzedFuncDef.args[i].argType))
      if maybeAnalyzed.isErr:
        candidateErr = maybeAnalyzed.error
        break
      analyzedArgs.add(maybeAnalyzed.get)
    if candidateErr.len > 0:
      errors.add(fmt"[{index + 1}] - {candidateErr}")
      errors.add("\t" & fmt"{analyzedFuncDef.loc}: {analyzedFuncDef.asl}")
      continue
    let maybeGenericImplMap = analyzeArgumentList(appDef, fileScope, module, funcScope, analyzedArgs, analyzedFuncDef)
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

proc analyzeFunctionCall*(appDef: AnalyzedAppDefinition, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, fncall: ResolvedFunctionCall): Result[AnalyzedFunctionCall, string] =
  let typ = ? fileScope.findType(fncall.typ, fncall.loc)
  let public =
    case typ.kind:
    of rtkModule: (module != typ.module)
    of rtkGeneric: true
  let definedType = ? appDef.findDefinedType(typ)
  let funcDefs = ? definedType.findFunctionDefs(fncall.parsed.name, fncall.parsed.args.len, public)

  let (matchingFuncDef, analyzedArgs, genericImpls) = ? analyzeArgumentList(appDef, file, fileScope, module, funcScope, fncall, funcDefs)
  # Return type comes pre-analyzed from the AnalyzedFunctionDefinition;
  # apply the caller's inferred generic-impl substitution to concretize
  # any free generics the return type touches.
  let concreteReturns = matchingFuncDef.returns.concrete(genericImpls)
  ok(newAnalyzedFunctionCall(fncall, matchingFuncDef.resolved, analyzedArgs, concreteReturns))

proc analyzeCaseBlock*(appDef: AnalyzedAppDefinition, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, caseBlock: ResolvedCaseBlock, subjectType: AnalyzedArgumentType, union: ResolvedUnionDef, subjectImpls: seq[AnalyzedArgumentType]): Result[AnalyzedCaseBlock, string] =
  let analyzedCasePattern = ? analyzeCasePattern(appDef, fileScope, module, funcScope, caseBlock.pattern, subjectType, union, subjectImpls)
  var caseScope = funcScope.clone()
  for binding in analyzedCasePattern.bindings:
    caseScope[binding.name] = binding.argType
  var analyzedStatements: seq[AnalyzedStatement]
  for statement in caseBlock.statements:
    let analyzedStatement = ? analyzeStatement(appDef, file, fileScope, module, caseScope, statement)
    analyzedStatements.add(analyzedStatement)
    if analyzedStatement.arg.isSome:
      let newArg = analyzedStatement.arg.get
      caseScope[newArg.name] = newArg.argType
  ok(newAnalyzedCaseBlock(caseBlock, analyzedCasePattern, analyzedStatements))

proc analyzeCaseBlock*(appDef: AnalyzedAppDefinition, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, caseBlock: ResolvedCaseBlock, subjectType: AnalyzedArgumentType): Result[AnalyzedCaseBlock, string] =
  let analyzedCasePattern = ? analyzeCasePattern(appDef, module, funcScope, caseBlock.pattern, subjectType)
  var caseScope = funcScope.clone()
  for binding in analyzedCasePattern.bindings:
    caseScope[binding.name] = binding.argType
  var analyzedStatements: seq[AnalyzedStatement]
  for statement in caseBlock.statements:
    let analyzedStatement = ? analyzeStatement(appDef, file, fileScope, module, caseScope, statement)
    analyzedStatements.add(analyzedStatement)
    if analyzedStatement.arg.isSome:
      let newArg = analyzedStatement.arg.get
      caseScope[newArg.name] = newArg.argType
  ok(newAnalyzedCaseBlock(caseBlock, analyzedCasePattern, analyzedStatements))

proc verifyUniformReturnType(cases: seq[AnalyzedCaseBlock]): Result[void, string] =
  let expected = cases[0].argType
  for c in cases:
    if c.argType != expected:
      return err(fmt"{c.loc} todo: return an error message telling that the case block return types are not same")
  ok()

proc analyzeCases*(appDef: AnalyzedAppDefinition, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, cases: seq[ResolvedCaseBlock], subjectType: AnalyzedArgumentType, union: ResolvedUnionDef, subjectImpls: seq[AnalyzedArgumentType], loc: Location): Result[seq[AnalyzedCaseBlock], string] =
  var patternScope = newAnalyzedUnionPatternScope(cases.len)
  for id, caseBlock in cases:
    patternScope = ? patternScope.update(id, caseBlock.pattern)

  ? hasUncoveredCases(patternScope, union.variants.len, loc)

  assert(cases.len > 0, "UNREACHABLE: zero-case match should have been caught by the resolver")

  var analyzedCaseBlocks: seq[AnalyzedCaseBlock]
  for caseBlock in cases:
    let analyzedCaseBlock = ? analyzeCaseBlock(appDef, file, fileScope, module, funcScope, caseBlock, subjectType, union, subjectImpls)
    analyzedCaseBlocks.add(analyzedCaseBlock)
  ? verifyUniformReturnType(analyzedCaseBlocks)
  ok(analyzedCaseBlocks)

proc analyzeCases*(appDef: AnalyzedAppDefinition, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, cases: seq[ResolvedCaseBlock], subjectType: AnalyzedArgumentType, literal: ResolvedLiteralDef, loc: Location): Result[seq[AnalyzedCaseBlock], string] =
  var patternScope = ? newAnalyzedLiteralPatternScope(literal, cases.len)
  for id, caseBlock in cases:
    patternScope = ? patternScope.update(id, caseBlock.pattern)

  ? hasUncoveredCases(patternScope, loc)

  assert(cases.len > 0, "UNREACHABLE: zero-case match should have been caught by the resolver")

  var analyzedCaseBlocks: seq[AnalyzedCaseBlock]
  for caseBlock in cases:
    let analyzedCaseBlock = ? analyzeCaseBlock(appDef, file, fileScope, module, funcScope, caseBlock, subjectType)
    analyzedCaseBlocks.add(analyzedCaseBlock)
  ? verifyUniformReturnType(analyzedCaseBlocks)
  ok(analyzedCaseBlocks)

proc analyzeMatchExpression*(appDef: AnalyzedAppDefinition, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, match: ResolvedMatchExpression): Result[AnalyzedMatchExpression, string] =
  let analyzedSubjectExpr = ? analyzeExpression(appDef, file, fileScope, module, funcScope, match.subject, none(AnalyzedArgumentType))
  let subjectArgType = analyzedSubjectExpr.argType
  let analyzedSubjectDataType = ? extractDataDef(appDef, subjectArgType, analyzedSubjectExpr.loc)
  case analyzedSubjectDataType.kind:
  of adkStruct:
    err(fmt"{match.loc} match block only supports literal and union types but subject expression returns `{subjectArgType.name.asl}` a struct type")
  of adkLiteral:
    if match.cases.len == 0:
      err(fmt"{match.loc} UNREACHABLE: match block does not contain any case blocks")
    else:
      let analyzedCases = ? analyzeCases(appDef, file, fileScope, module, funcScope, match.cases, subjectArgType, analyzedSubjectDataType.literal.resolved, match.loc)
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
        let analyzedCases = ? analyzeCases(appDef, file, fileScope, module, funcScope, match.cases, subjectArgType, analyzedSubjectDataType.union.resolved, impls, match.loc)
        ok(newAnalyzedMatchExpression(match, analyzedSubjectExpr, analyzedCases, analyzedCases[0].argType))

proc analyzeKeywordArgument*(appDef: AnalyzedAppDefinition, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, kwarg: ResolvedKeywordArgument, analyzedField: ResolvedArgumentDef, analyzedFieldArgType: AnalyzedArgumentType): Result[AnalyzedKeywordArgument, string] =
  # Field's declared type is the expected context — bare literals in
  # kwarg values adapt when concrete, default when generic.
  let analyzedExpression = ? analyzeExpression(appDef, file, fileScope, module, funcScope, kwarg.expression, some(analyzedFieldArgType))
  # TODO: Utilize the returned generic impl map
  discard ? analyzeValueTypeAgainstDefType(analyzedFieldArgType, analyzedExpression.argType, analyzedExpression.loc)
  ok(newAnalyzedKeywordArgument(kwarg, analyzedField, analyzedExpression))

proc analyzeUnionRef(appDef: AnalyzedAppDefinition, fileScope: ResolvedFileScope, module: ResolvedModule, unionRef: ResolvedUnionRef): Result[AnalyzedUnionRef, string] =
  ## Walks the resolver's already-checked `impls` seq once and
  ## produces the analyzer-side equivalents. Empty in → empty out.
  ## Parser-Module → ResolvedModule via identity lookup on fileScope —
  ## immune to aliased-import name mismatch.
  let resolvedModule = ? fileScope.findModule(unionRef.module, unionRef.loc)
  var analyzedImpls = newSeq[AnalyzedArgumentType](unionRef.impls.len)
  for i, resolvedImpl in unionRef.impls:
    analyzedImpls[i] = ? analyzeArgumentType(fileScope, module, resolvedImpl)
  ok(newAnalyzedUnionRef(unionRef, resolvedModule, analyzedImpls))

proc analyzeUnionInitializer*(appDef: AnalyzedAppDefinition, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, init: ResolvedUnionInitializer): Result[AnalyzedUnionInitializer, string] =
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
  let analyzedUnionRef = ? analyzeUnionRef(appDef, fileScope, module, init.unionRef)
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
      let analyzedGeneric = ? analyzeArgumentType(fileScope, module, newResolvedArgumentType(genericArgType))
      implMap[analyzedGeneric.generic.resolved] = analyzedImpls[position]

  # Walk kwargs. Substitute the variant's field type via implMap before
  # type-checking — equivalent to direct match on the bare path
  # (implMap seeded from kwargs), full concretization on the explicit-
  # impls path (implMap already seeded, merge-from-kwarg skipped so no
  # inference happens).
  var analyzedKwargs: seq[AnalyzedKeywordArgument]
  for kwarg in init.kwargs:
    let resolvedField = ? resolvedVariant.findField(kwarg.name)
    let analyzedFieldArgType = ? analyzeArgumentType(fileScope, module, resolvedField.argType)
    # Concretize the field type via the current implMap before analyzing
    # the value so bare-literal kwargs adopt the concrete instantiation
    # when known, and default (i32/f32/String) when the field is still
    # a free generic on the bare path.
    let fieldType = analyzedFieldArgType.concrete(implMap)
    let analyzedExpression = ? analyzeExpression(appDef, file, fileScope, module, funcScope, kwarg.expression, some(fieldType))
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
    let analyzedGeneric = ? analyzeArgumentType(fileScope, module, newResolvedArgumentType(genericArgType))
    if analyzedGeneric.generic.resolved in implMap:
      impls[position] = implMap[analyzedGeneric.generic.resolved]
    else:
      impls[position] = analyzedGeneric
  let resolvedSelfArg = receiver.self
  let analyzedModuleArg = newAnalyzedModuleArgumentType(resolvedSelfArg, receiver, impls)
  let argType = newAnalyzedArgumentType(analyzedModuleArg)

  ok(newAnalyzedUnionInitializer(init, analyzedUnionRef, argType, resolvedVariant, analyzedKwargs))

proc analyzeStructRef(appDef: AnalyzedAppDefinition, fileScope: ResolvedFileScope, module: ResolvedModule, structRef: ResolvedStructRef): Result[AnalyzedStructRef, string] =
  ## Walks the resolver's already-checked `impls` seq once and
  ## produces the analyzer-side equivalents. Empty in → empty out.
  ## The parser Module carried on `structRef.module` is looked up here
  ## into a ResolvedModule via `fileScope.findModule` (identity-keyed) — the
  ## resolver keeps struct/union refs parser-level to break the ref
  ## cycle; analyzer types can hold the resolved view freely.
  let resolvedModule = ? fileScope.findModule(structRef.module, structRef.loc)
  var analyzedImpls = newSeq[AnalyzedArgumentType](structRef.impls.len)
  for i, resolvedImpl in structRef.impls:
    analyzedImpls[i] = ? analyzeArgumentType(fileScope, module, resolvedImpl)
  ok(newAnalyzedStructRef(structRef, resolvedModule, analyzedImpls))

proc analyzeStructInitializer*(appDef: AnalyzedAppDefinition, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, init: ResolvedStructInitializer): Result[AnalyzedStructInitializer, string] =
  ## Single code path over the struct initializer. Receiver is the
  ## resolver's already-resolved module; result argType wraps the
  ## analyzedImpls seq (empty when the surface form was bare — matches
  ## the receiverArgType() no-impls shape; non-empty when explicit
  ## impls were supplied and arity+constraint-checked at resolve time).
  ## TODO: Inference for uncovered generic positions on the bare path
  ## still lives with the caller of receiverArgType — folded into the
  ## same seq-based build here.
  let analyzedStructRef = ? analyzeStructRef(appDef, fileScope, module, init.structRef)
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
      let analyzedFieldArgType = ? analyzeArgumentType(fileScope, module, resolvedField.argType)
      let analyzedKwarg = ? analyzeKeywordArgument(appDef, file, fileScope, module, funcScope, kwarg, resolvedField, analyzedFieldArgType)
      analyzedKwargs.add(analyzedKwarg)
    let argType =
      if analyzedStructRef.analyzedImpls.len == 0:
        newAnalyzedArgumentType(receiver)
      else:
        let resolvedSelfArg = receiver.self
        let analyzedModuleArg = newAnalyzedModuleArgumentType(resolvedSelfArg, receiver, analyzedStructRef.analyzedImpls)
        newAnalyzedArgumentType(analyzedModuleArg)
    ok(newAnalyzedStructInitializer(init, analyzedStructRef, argType, analyzedKwargs))

proc analyzeInitializer*(appDef: AnalyzedAppDefinition, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, init: ResolvedInitializer): Result[AnalyzedInitializer, string] =
  case init.kind:
  of rikLiteral:
    let analyzedLiteralInit = ? analyzeLiteralInitializer(appDef, fileScope, module, funcScope, init.literal)
    ok(newAnalyzedInitializer(analyzedLiteralInit))
  of rikStruct:
    let analyzedStructInit = ? analyzeStructInitializer(appDef, file, fileScope, module, funcScope, init.struct)
    ok(newAnalyzedInitializer(analyzedStructInit))
  of rikUnion:
    let analyzedUnionInit = ? analyzeUnionInitializer(appDef, file, fileScope, module, funcScope, init.union)
    ok(newAnalyzedInitializer(analyzedUnionInit))

proc defaultLiteralArgType(appDef: AnalyzedAppDefinition, file: ResolvedFile, fileScope: ResolvedFileScope, literal: Literal): Result[AnalyzedArgumentType, string] =
  ## Look up the default module for a bare-literal kind. Integer → i32,
  ## Float → f32, String → String. The default must be reachable via the
  ## file scope — `@std` auto-injection in .asl files puts these three
  ## in scope; if the caller is analyzing a file that skipped that
  ## injection (or a fixture that omits the type entirely), the lookup
  ## fails with a user-facing error naming the missing default.
  let literalModuleName =
    case literal.kind:
      of lkInteger: "i32"
      of lkFloat: "f32"
      of lkString: "String"

  let maybeLiteralModuleIdent = newIdentifier(literalModuleName, literal.loc)
  assert maybeLiteralModuleIdent.isOk, fmt"BUG: default literal type name `{literalModuleName}` should always satisfy newIdentifier"

  # Find `parser.Module` by accessing fileScope built in file resolution phase
  let literalModule = ? file.scope.findModule(maybeLiteralModuleIdent.get)
  # Use the `parser.Module` to lookup the `ResolvedModule`
  let maybeResolvedLiteralModule = fileScope.findModule(literalModule, literal.loc)
  if maybeResolvedLiteralModule.isErr:
    err(fmt"{literal.loc} bare literal defaults to `{literalModuleName}` but it is not in scope; ensure `@std` auto-injection or an explicit import brings it in")
  else:
    ok(newAnalyzedArgumentType(maybeResolvedLiteralModule.get))

proc analyzeBareLiteral(appDef: AnalyzedAppDefinition, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, literal: Literal, expected: Option[AnalyzedArgumentType]): Result[AnalyzedLiteralInitializer, string] =
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
      of aatkGeneric: ? defaultLiteralArgType(appDef, file, fileScope, literal)
    else:
      ? defaultLiteralArgType(appDef, file, fileScope, literal)

  let argDefModule = ? findModuleDef(appDef, concreteArgType, literal.loc)
  let argDefData = ? extractDataDef(argDefModule, literal.loc)
  case argDefData.kind:
  of adkStruct: err(fmt"{literal.loc} expected a struct initializer of type `{argDefModule.name.asl}` but found bare literal")
  of adkUnion: err(fmt"{literal.loc} expected a union initializer of type `{argDefModule.name.asl}` but found bare literal")
  of adkLiteral:
    ? analyzeLiteral(argDefData.literal.resolved, literal)
    ok(newAnalyzedLiteralInitializer(literal, concreteArgType))

proc analyzeExpression*(appDef: AnalyzedAppDefinition, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, expression: ResolvedExpression, expected: Option[AnalyzedArgumentType]): Result[AnalyzedExpression, string] =
  case expression.kind:
  of rekLiteral:
    let bareLit = ? analyzeBareLiteral(appDef, file, fileScope, module, funcScope, expression.literal, expected)
    ok(newAnalyzedExpression(newAnalyzedInitializer(bareLit)))
  of rekVariable:
    let analyzedVariable = ? analyzeVariable(funcScope, expression.variable)
    ok(newAnalyzedExpression(analyzedVariable))
  of rekGetter:
    let analyzedGetter = ? analyzeGetter(appDef, fileScope, module, funcScope, expression.getter)
    ok(newAnalyzedExpression(analyzedGetter))
  of rekInitializer:
    let analyzedInit = ? analyzeInitializer(appDef, file, fileScope, module, funcScope, expression.init)
    ok(newAnalyzedExpression(analyzedInit))
  of rekFunctionCall:
    let analyzedFunctionCall = ? analyzeFunctionCall(appDef, file, fileScope, module, funcScope, expression.fncall)
    ok(newAnalyzedExpression(analyzedFunctionCall))
  of rekMatchExpr:
    let analyzedMatchExpr = ? analyzeMatchExpression(appDef, file, fileScope, module, funcScope, expression.match)
    ok(newAnalyzedExpression(analyzedMatchExpr))

proc analyzeAssignment*(appDef: AnalyzedAppDefinition, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, assignment: ResolvedAssignment): Result[AnalyzedAssignment, string] =
  let analyzedExpr = ? analyzeExpression(appDef, file, fileScope, module, funcScope, assignment.expression, none(AnalyzedArgumentType))
  ok(newAnalyzedAssignment(assignment, analyzedExpr))

proc analyzeSetter*(appDef: AnalyzedAppDefinition, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, setter: ResolvedSetter): Result[AnalyzedSetter, string] =
  let analyzedGetter = ? analyzeGetter(appDef, fileScope, module, funcScope, setter.getter)
  # RHS must match the getter's field type — thread that as expected.
  let analyzedExpression = ? analyzeExpression(appDef, file, fileScope, module, funcScope, setter.expression, some(analyzedGetter.argType))
  # TODO: Ensure that the getter field type and the expression type are same
  ok(newAnalyzedSetter(setter, analyzedGetter, analyzedExpression))

proc analyzeStatement*(appDef: AnalyzedAppDefinition, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, statement: ResolvedStatement): Result[AnalyzedStatement, string] =
  case statement.kind:
  of rskExpr:
    let analyzedExpr = ? analyzeExpression(appDef, file, fileScope, module, funcScope, statement.expression, none(AnalyzedArgumentType))
    ok(newAnalyzedStatement(analyzedExpr))
  of rskAssignment:
    let analyzedAssignment = ? analyzeAssignment(appDef, file, fileScope, module, funcScope, statement.assignment)
    ok(newAnalyzedStatement(analyzedAssignment))
  of rskSetter:
    let analyzedMutation = ? analyzeSetter(appDef, file, fileScope, module, funcScope, statement.setter)
    ok(newAnalyzedStatement(analyzedMutation))

proc analyzeUserFunction*(appDef: AnalyzedAppDefinition, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, function: ResolvedUserFunction): Result[AnalyzedUserFunction, string] =
  var funcScope: AnalyzedFunctionScope
  for argDef in function.def.args:
    let analyzedArgType = ? analyzeArgumentType(fileScope, module, argDef.argType)
    funcScope[argDef.name] = analyzedArgType

  var analyzedStatements: seq[AnalyzedStatement]
  for statement in function.statements:
    let analyzedStatement = ? analyzeStatement(appDef, file, fileScope, module, funcScope, statement)
    analyzedStatements.add(analyzedStatement)
    if analyzedStatement.arg.isSome:
      let newArg = analyzedStatement.arg.get
      funcScope[newArg.name] = newArg.argType

  if function.statements.len == 0:
    err(fmt"{function.loc} UNREACHABLE: should have been caught by the resolver")
  else:
    let analyzedReturns = ? analyzeArgumentType(fileScope, module, function.def.returns)
    if analyzedStatements[^1].argType != analyzedReturns:
      err(fmt"{function.statements[^1].loc} function does not return the expected return type")
    else:
      ok(newAnalyzedUserFunction(function, function.def, analyzedStatements))

proc analyzeModule*(appDef: AnalyzedAppDefinition, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule): Result[AnalyzedModule, string] =
  var analyzedFunctions: seq[AnalyzedFunction]
  for function in module.functions:
    case function.kind:
    of rfkExtern:
      analyzedFunctions.add(newAnalyzedFunction(newAnalyzedExternFunction(function.extern, function.def)))
    of rfkUser:
      let analyzedUserFunction = ? analyzeUserFunction(appDef, file, fileScope, module, function.user)
      analyzedFunctions.add(newAnalyzedFunction(analyzedUserFunction))
  ok(newAnalyzedModule(module, analyzedFunctions))

proc analyzeFile(appDef: AnalyzedAppDefinition, app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope): Result[AnalyzedFile, string] =
  var analyzedImports: seq[AnalyzedImportDefinition]
  for imp in file.imports:
    let analyzedImport = ? analyzeImportDefinition(app, imp)
    analyzedImports.add(analyzedImport)

  var analyzedModules: seq[AnalyzedModule]
  for typ in file.types:
    case typ.kind:
    of rtkGeneric: discard # generics are already resolved since it is only a definition type
    of rtkModule:
      let analyzedModule = ? analyzeModule(appDef, file, fileScope, typ.module)
      analyzedModules.add(analyzedModule)
  ok(newAnalyzedFile(file, analyzedImports, analyzedModules))

proc analyze*(app: ResolvedApp): Result[AnalyzedApp, string] =
  let appDef = ? analyzeAppDefinition(app)
  var analyzedFiles: seq[AnalyzedFile]
  for fileDef in appDef.fileDefs:
    let analyzedFile = ? analyzeFile(appDef, app, fileDef.resolved, fileDef.scope)
    analyzedFiles.add(analyzedFile)
  ok(newAnalyzedApp(app, analyzedFiles))
