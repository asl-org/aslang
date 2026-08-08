## Body-analysis barrel — phase B of the two-pass analyzer, and the
## top of the compiler stack. Consumers say `import analyzer` to get
## everything: the body walkers + public `analyze*` entry here, plus
## the defanalyzer layer beneath (which transitively re-exports
## resolver -> parser -> Location).

import options, results, sequtils, strformat, strutils, tables

import ./analyzer/defanalyzer
export defanalyzer

import ./analyzer/funccontext
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
import ./analyzer/filecontext
import ./analyzer/importedtype
import ./analyzer/imports
import ./analyzer/file
import ./analyzer/appcontext
import ./analyzer/app

proc extractDataDef*(fileCtx: AnalyzedFileContext, argType: AnalyzedModuleArgumentType): Result[AnalyzedDataDef, string] =
  ok(fileCtx.findModule(argType.module).dataDef)

proc extractStructFor*(fileCtx: AnalyzedFileContext, argType: AnalyzedModuleArgumentType, loc: Location): Result[AnalyzedStructDef, string] =
  let moduleDef = fileCtx.findModule(argType.module)
  let dataDef = moduleDef.dataDef
  case dataDef.kind:
  of adkStruct: ok(dataDef.struct)
  of adkUnion: err(fmt"{loc} expected module `{moduleDef.name.asl}` to have a struct block but found union")
  of adkLiteral: err(fmt"{loc} expected module `{moduleDef.name.asl}` to have a struct block but found literal")

proc extractUnionFor*(fileCtx: AnalyzedFileContext, argType: AnalyzedModuleArgumentType, loc: Location): Result[AnalyzedUnionDef, string] =
  let moduleDef = fileCtx.findModule(argType.module)
  let dataDef = moduleDef.dataDef
  case dataDef.kind:
  of adkUnion: ok(dataDef.union)
  of adkStruct: err(fmt"{loc} expected module `{moduleDef.name.asl}` to have a union block but found struct")
  of adkLiteral: err(fmt"{loc} expected module `{moduleDef.name.asl}` to have a union block but found literal")

# ============================================================
# ⚠ KNOWN LIMITATION — SIGNATURE-PARITY IS HASH-EQUALITY, NOT
#   UNIFICATION.
#
# The value-vs-defType walk below compares argument types with
# hash-based `==` at module positions. That is sound when both sides
# are ground, but a free generic in impl position (post leave-as-is
# inference, e.g. Box[u8, Sample] against Box[u8, MyImpl]) needs
# unification — solving for the binding — not equality. The def-time
# constraint check no longer shares this limitation (its deep
# `concrete` grounds contract defs before the identity probe).
#
# The fix routes every assignability check through
# `analyzeValueTypeAgainstDefType` + `merge` with eager chain-
# collapsing in `merge` (so `Sample → K, K → u8` collapses to
# `Sample → u8`). See `plans/plan_deferred_typing.md` §
# "Equality vs unification for analyzed types" — that plan owns the
# fix.
# ============================================================

proc analyzeValueTypeAgainstDefType(module: AnalyzedDefModule, defType: AnalyzedArgumentType, valType: AnalyzedArgumentType, loc: Location): Result[GenericImplMap, string]

proc analyzeValueTypeAgainstDefType(module: AnalyzedDefModule, defType: AnalyzedModuleArgumentType, valType: AnalyzedModuleArgumentType, loc: Location): Result[GenericImplMap, string] =
  if defType.module != valType.module:
    err(fmt"{loc} expected `{defType.name.asl}` but found `{valType.name.asl}`")
  else:
    var genericImplMap: GenericImplMap
    for (defImpl, valImpl) in zip(defType.impls, valType.impls):
      let valGenericImplMap = ? analyzeValueTypeAgainstDefType(module, defImpl, valImpl, loc)
      genericImplMap = ? genericImplMap.merge(valGenericImplMap)
    ok(genericImplMap)

proc analyzeValueTypeAgainstDefType(module: AnalyzedDefModule, defType: AnalyzedGenericArgumentType, valType: AnalyzedArgumentType, loc: Location): Result[GenericImplMap, string] =
  let typeCtx = newResolvedTypeContext(module.resolved)
  discard ? analyzeDefImpl(typeCtx, defType.generic, valType)
  var genericImplMap: GenericImplMap
  genericImplMap[defType.generic] = valType
  ok(genericImplMap)

proc analyzeValueTypeAgainstDefType(module: AnalyzedDefModule, defType: AnalyzedModuleArgumentType, valType: AnalyzedArgumentType, loc: Location): Result[GenericImplMap, string] =
  case valType.kind:
  of aatkGeneric:
    err(fmt"{loc} expected a module {defType.asl} type but found generic type {valType.asl}")
  of aatkModule:
    analyzeValueTypeAgainstDefType(module, defType, valType.module, loc)

# TODO: Return a map of generic -> argType from the recursive analysis
proc analyzeValueTypeAgainstDefType(module: AnalyzedDefModule, defType: AnalyzedArgumentType, valType: AnalyzedArgumentType, loc: Location): Result[GenericImplMap, string] =
  case defType.kind:
  of aatkModule: analyzeValueTypeAgainstDefType(module, defType.module, valType, loc)
  of aatkGeneric: analyzeValueTypeAgainstDefType(module, defType.generic, valType, loc)

proc analyzeUnionCasePattern*(variantPattern: UnionPattern, union: AnalyzedUnionDef, subjectImplMap: GenericImplMap): Result[AnalyzedUnionPattern, string] =
  let variant = union.findVariant(variantPattern.name)
  var bindings: seq[AnalyzedBinding]
  for field in variantPattern.fields:
    let fieldDef = ? variant.findField(field.name)
    let analyzedFieldArgType = fieldDef.argType
    let concreteFieldArgType = analyzedFieldArgType.concrete(subjectImplMap)
    bindings.add((name: field.binding, argType: concreteFieldArgType))
  ok(newAnalyzedUnionPattern(variantPattern, variant, bindings))

proc analyzeCasePattern*(pattern: ResolvedCasePattern, subjectType: AnalyzedArgumentType, union: AnalyzedUnionDef, subjectImplMap: GenericImplMap): Result[AnalyzedCasePattern, string] =
  case pattern.kind:
  of rcpkInteger: err(fmt"{pattern.loc} integer literals are not allowed in union case pattern")
  of rcpkVariable:
    ok(newAnalyzedCasePattern((name: pattern.variable, argType: subjectType)))
  of rcpkUnion:
    let analyzedPattern = ? analyzeUnionCasePattern(pattern.variant, union, subjectImplMap)
    ok(newAnalyzedCasePattern(analyzedPattern))

proc analyzeCasePattern*(pattern: ResolvedCasePattern, subjectType: AnalyzedArgumentType): Result[AnalyzedCasePattern, string] =
  case pattern.kind:
  of rcpkUnion:
    err(fmt"{pattern.loc} union variants are not allowed in literal case pattern")
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

proc analyzeLiteral(literalDef: AnalyzedLiteralDef, literal: Literal): Result[void, string] =
  let resolved = literalDef.resolved
  case resolved:
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

proc analyzeVariable*(scope: AnalyzedFunctionContext, variable: Identifier): Result[AnalyzedVariable, string] =
  if variable in scope: ok(newAnalyzedVariable(variable, scope[variable]))
  else: err(fmt"{variable.loc} variable `{variable.asl}` does not exist in scope")

proc analyzeGetter*(fileCtx: AnalyzedFileContext, module: AnalyzedDefModule, funcCtx: AnalyzedFunctionContext, getter: ResolvedGetter): Result[AnalyzedGetter, string] =
  if getter.source notin funcCtx:
    err(fmt"{getter.loc} variable `{getter.source.asl}` is not present in scope")
  else:
    let analyzedSourceArgType = funcCtx[getter.source]
    case analyzedSourceArgType.kind:
    of aatkGeneric:
      err(fmt"{getter.loc} expected `{getter.source.asl}` to be a module but found generic ")
    of aatkModule:
      let struct = ? fileCtx.extractStructFor(analyzedSourceArgType.module, getter.loc)
      let property = ? struct.findField(getter.property)
      # TODO: coerce the property type from the generic to concrete
      ok(newAnalyzedGetter(getter, analyzedSourceArgType, property))

proc analyzeLiteralInitializer*(fileCtx: AnalyzedFileContext, module: AnalyzedDefModule, funcCtx: AnalyzedFunctionContext, init: AnalyzedDefLiteralInitializer): Result[AnalyzedLiteralInitializer, string] =
  let analyzedModuleArgType = init.argType
  let argDefModule = fileCtx.findModule(init.argType.module)
  let argDefData = argDefModule.dataDef
  case argDefData.kind:
  of adkStruct: err(fmt"{init.loc} statement expects a literal initializer `{argDefModule.name.asl}`")
  of adkUnion: err(fmt"{init.loc} statement expects a literal initializer `{argDefModule.name.asl}`")
  of adkLiteral:
    let maybeValidLiteral = analyzeLiteral(argDefData.literal, init.literal)
    if maybeValidLiteral.isOk: ok(newAnalyzedLiteralInitializer(init.literal, analyzedModuleArgType))
    else: err(maybeValidLiteral.error)

# Forward declarations for the analyzeX procs in the cluster.
proc analyzeExpression*(fileCtx: AnalyzedFileContext, module: AnalyzedDefModule, funcCtx: AnalyzedFunctionContext, expression: AnalyzedDefExpression, expected: Option[AnalyzedArgumentType]): Result[AnalyzedExpression, string]
proc analyzeStatement*(fileCtx: AnalyzedFileContext, module: AnalyzedDefModule, funcCtx: AnalyzedFunctionContext, statement: AnalyzedDefStatement): Result[AnalyzedStatement, string]

proc analyzeArgumentList*(fileCtx: AnalyzedFileContext, module: AnalyzedDefModule, funcCtx: AnalyzedFunctionContext, argValues: seq[AnalyzedExpression], analyzedFuncDef: AnalyzedFunctionDef): Result[GenericImplMap, string] =
  # Reads pre-analyzed args directly from the AnalyzedFunctionDef
  # — no lookup, no re-analysis. Every analyzed expression carries a
  # concrete argType post-Approach C; bare literals adopt the caller's
  # expected type or default to i32/f32/String at the
  # analyzeBareLiteral site. Per-candidate type context is threaded
  # from `analyzeFunctionCall`.
  assert(analyzedFuncDef.args.len == argValues.len,
    fmt"BUG: analyzeArgumentList arity mismatch — funcDef has {analyzedFuncDef.args.len} args, call site passed {argValues.len}. zip would silently truncate; fix by erroring (or relying on resolver / overload selection).")
  var genericImplMap: GenericImplMap
  for (analyzedArgDef, argValue) in zip(analyzedFuncDef.args, argValues):
    let argGenericImplMap = ? analyzeValueTypeAgainstDefType(module, analyzedArgDef.argType, argValue.argType, argValue.loc)
    genericImplMap = ? genericImplMap.merge(argGenericImplMap)
  ok(genericImplMap)

proc analyzeArgumentList(fileCtx: AnalyzedFileContext, module: AnalyzedDefModule, funcCtx: AnalyzedFunctionContext, fncall: AnalyzedDefFunctionCall, funcDefs: seq[AnalyzedFunctionDef]): Result[(AnalyzedFunctionDef, seq[AnalyzedExpression], GenericImplMap), string] =
  # Per-candidate analysis over pre-analyzed AnalyzedFunctionDef
  # candidates: for each candidate, walk the call's raw arguments and
  # analyze each with the candidate's declared arg type (pre-analyzed)
  # as the expected context. Bare literals adopt the declared type when
  # concrete, or default to i32/f32/String otherwise
  # (`analyzeBareLiteral`). First candidate whose args analyze +
  # type-check wins; ambiguity fires the existing multi-match error
  # path.
  var matches: seq[(AnalyzedFunctionDef, seq[AnalyzedExpression], GenericImplMap)]
  var errors: seq[string]
  for index, analyzedFuncDef in funcDefs:
    assert(analyzedFuncDef.args.len == fncall.args.len, "[BUG] - UNREACHABLE")
    var analyzedArgs: seq[AnalyzedExpression]
    var candidateErr = ""
    for (actualArg, expectedArg) in zip(fncall.args, analyzedFuncDef.args):
      let maybeAnalyzed = analyzeExpression(fileCtx, module, funcCtx, actualArg, some(expectedArg.argType))
      if maybeAnalyzed.isErr:
        candidateErr = maybeAnalyzed.error
        break
      analyzedArgs.add(maybeAnalyzed.get)
    if candidateErr.len > 0:
      errors.add(fmt"[{index + 1}] - {candidateErr}")
      errors.add("\t" & fmt"{analyzedFuncDef.loc}: {analyzedFuncDef.asl}")
      continue
    let maybeGenericImplMap = analyzeArgumentList(fileCtx, module, funcCtx, analyzedArgs, analyzedFuncDef)
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

proc analyzeBareLiteral(fileCtx: AnalyzedFileContext, module: AnalyzedDefModule, funcCtx: AnalyzedFunctionContext, literal: AnalyzedDefLiteral, expected: Option[AnalyzedArgumentType]): Result[AnalyzedLiteralInitializer, string] =
  ## Approach C — pick a concrete type for the bare literal.
  ##   - `expected = some(module)`  → adopt the module type. If the
  ##     module's data def is struct/union the caller wrote a literal
  ##     where an initializer was expected → error with a clear message.
  ##   - `expected = some(generic)` → default (the binding contributes
  ##     to the generic-impl map at the call site).
  ##   - `expected = none`          → default (bare assignment / bare
  ##     statement).
  ## Then fit-check the value against the chosen module's literal spec.
  let literalArgType =
    if expected.isSome:
      case expected.get.kind:
      of aatkModule: expected.get.module
      of aatkGeneric: literal.default
    else:
      literal.default

  let argDefModule = fileCtx.findModule(literalArgType.module)
  let argDefData = argDefModule.dataDef
  case argDefData.kind:
  of adkStruct: err(fmt"{literal.loc} expected a struct initializer of type `{argDefModule.name.asl}` but found bare literal")
  of adkUnion: err(fmt"{literal.loc} expected a union initializer of type `{argDefModule.name.asl}` but found bare literal")
  of adkLiteral:
    ? analyzeLiteral(argDefData.literal, literal.value)
    ok(newAnalyzedLiteralInitializer(literal.value, literalArgType))

proc analyzeFunctionCall*(fileCtx: AnalyzedFileContext, module: AnalyzedDefModule, funcCtx: AnalyzedFunctionContext, fncall: AnalyzedDefFunctionCall): Result[AnalyzedFunctionCall, string] =
  let typ = fncall.typ
  let definedType = fileCtx.findType(typ)
  let access =
    case definedType.kind:
    of altkGeneric:
      faPublic
    of altkModule:
      if module == definedType.module: faAll else: faPublic
  let maybeFuncDefs = definedType.findFunctionDefs(fncall.name, fncall.arity, access)
  assert(maybeFuncDefs.isOk, "[BUG] - Resolver validates every call target (name, arity, access) at resolve time")
  let funcDefs = maybeFuncDefs.get

  let (matchingFuncDef, analyzedArgs, genericImpls) = ? analyzeArgumentList(fileCtx, module, funcCtx, fncall, funcDefs)
  # The impl map inferred from the arguments rides on the call node;
  # the `returns` accessor concretizes the funcDef's return type from
  # it on access (matching the initializers).
  ok(newAnalyzedFunctionCall(fncall, matchingFuncDef, analyzedArgs, genericImpls))

proc analyzeCaseBlock*(fileCtx: AnalyzedFileContext, module: AnalyzedDefModule, funcCtx: AnalyzedFunctionContext, caseBlock: AnalyzedDefCase, subjectType: AnalyzedArgumentType, union: AnalyzedUnionDef, subjectImplMap: GenericImplMap): Result[AnalyzedCaseBlock, string] =
  var caseCtx = funcCtx

  let analyzedCasePattern = ? analyzeCasePattern(caseBlock.pattern, subjectType, union, subjectImplMap)
  caseCtx = caseCtx.update(analyzedCasePattern)

  var analyzedStatements: seq[AnalyzedStatement]
  for statement in caseBlock.statements:
    let analyzedStatement = ? analyzeStatement(fileCtx, module, caseCtx, statement)
    analyzedStatements.add(analyzedStatement)
    caseCtx = caseCtx.update(analyzedStatement)
  ok(newAnalyzedCaseBlock(caseBlock, analyzedCasePattern, analyzedStatements))

proc analyzeCaseBlock*(fileCtx: AnalyzedFileContext, module: AnalyzedDefModule, funcCtx: AnalyzedFunctionContext, caseBlock: AnalyzedDefCase, subjectType: AnalyzedArgumentType): Result[AnalyzedCaseBlock, string] =
  var caseCtx = funcCtx

  let analyzedCasePattern = ? analyzeCasePattern(caseBlock.pattern, subjectType)
  caseCtx = caseCtx.update(analyzedCasePattern)

  var analyzedStatements: seq[AnalyzedStatement]
  for statement in caseBlock.statements:
    let analyzedStatement = ? analyzeStatement(fileCtx, module, caseCtx, statement)
    analyzedStatements.add(analyzedStatement)
    caseCtx = caseCtx.update(analyzedStatement)
  ok(newAnalyzedCaseBlock(caseBlock, analyzedCasePattern, analyzedStatements))

proc verifyUniformReturnType(cases: seq[AnalyzedCaseBlock]): Result[void, string] =
  let expected = cases[0].argType
  for c in cases:
    if c.argType != expected:
      return err(fmt"{c.loc} todo: return an error message telling that the case block return types are not same")
  ok()

proc analyzeCases*(fileCtx: AnalyzedFileContext, module: AnalyzedDefModule, funcCtx: AnalyzedFunctionContext, cases: seq[AnalyzedDefCase], subjectType: AnalyzedArgumentType, union: AnalyzedUnionDef, subjectImplMap: GenericImplMap, loc: Location): Result[seq[AnalyzedCaseBlock], string] =
  var patternScope = newAnalyzedUnionPatternScope(cases.len)
  for id, caseBlock in cases:
    patternScope = ? patternScope.update(id, caseBlock.pattern)

  ? hasUncoveredCases(patternScope, union.variants.len, loc)

  assert(cases.len > 0, "UNREACHABLE: zero-case match should have been caught by the resolver")

  var analyzedCaseBlocks: seq[AnalyzedCaseBlock]
  for caseBlock in cases:
    let analyzedCaseBlock = ? analyzeCaseBlock(fileCtx, module, funcCtx, caseBlock, subjectType, union, subjectImplMap)
    analyzedCaseBlocks.add(analyzedCaseBlock)
  ? verifyUniformReturnType(analyzedCaseBlocks)
  ok(analyzedCaseBlocks)

proc analyzeCases*(fileCtx: AnalyzedFileContext, module: AnalyzedDefModule, funcCtx: AnalyzedFunctionContext, cases: seq[AnalyzedDefCase], subjectType: AnalyzedArgumentType, literal: AnalyzedLiteralDef, loc: Location): Result[seq[AnalyzedCaseBlock], string] =
  var patternScope = ? newAnalyzedLiteralPatternScope(literal, cases.len)
  for id, caseBlock in cases:
    patternScope = ? patternScope.update(id, caseBlock.pattern)

  ? hasUncoveredCases(patternScope, loc)

  assert(cases.len > 0, "UNREACHABLE: zero-case match should have been caught by the resolver")

  var analyzedCaseBlocks: seq[AnalyzedCaseBlock]
  for caseBlock in cases:
    let analyzedCaseBlock = ? analyzeCaseBlock(fileCtx, module, funcCtx, caseBlock, subjectType)
    analyzedCaseBlocks.add(analyzedCaseBlock)
  ? verifyUniformReturnType(analyzedCaseBlocks)
  ok(analyzedCaseBlocks)

proc analyzeMatchExpression*(fileCtx: AnalyzedFileContext, module: AnalyzedDefModule, funcCtx: AnalyzedFunctionContext, match: AnalyzedDefMatch): Result[AnalyzedMatchExpression, string] =
  let analyzedSubjectExpr = ? analyzeExpression(fileCtx, module, funcCtx, match.subject, none(AnalyzedArgumentType))
  let subjectArgType = analyzedSubjectExpr.argType
  case subjectArgType.kind:
  of aatkGeneric:
    err(fmt"{match.subject.loc} expected subject expression to return a module but found generic")
  of aatkModule:
    let analyzedSubjectDataType = ? fileCtx.extractDataDef(subjectArgType.module)
    case analyzedSubjectDataType.kind:
    of adkStruct:
      err(fmt"{match.loc} match block only supports literal and union types but subject expression returns `{subjectArgType.name.asl}` a struct type")
    of adkLiteral:
      assert(match.cases.len > 0, "UNREACHABLE: zero-case match should have been caught by the resolver")
      let analyzedCases = ? analyzeCases(fileCtx, module, funcCtx, match.cases, subjectArgType, analyzedSubjectDataType.literal, match.loc)
      ok(newAnalyzedMatchExpression(match, analyzedSubjectExpr, analyzedCases))
    of adkUnion:
      assert(match.cases.len > 0, "UNREACHABLE: zero-case match should have been caught by the resolver")
      let analyzedCases = ? analyzeCases(fileCtx, module, funcCtx, match.cases, subjectArgType, analyzedSubjectDataType.union, analyzedSubjectExpr.impls, match.loc)
      ok(newAnalyzedMatchExpression(match, analyzedSubjectExpr, analyzedCases))

proc analyzeKeywordArgument*(fileCtx: AnalyzedFileContext, module: AnalyzedDefModule, funcCtx: AnalyzedFunctionContext, kwarg: AnalyzedDefKeywordArgument, analyzedField: AnalyzedArgumentDef): Result[AnalyzedKeywordArgument, string] =
  # Field's declared type is the expected context — bare literals in
  # kwarg values adapt when concrete, default when generic. The
  # value-vs-field check yields the bindings this kwarg contributes
  # (field `value: T` + a `u8` value binds `T -> u8`); they ride on
  # the kwarg node so the initializer can merge them across fields.
  let analyzedExpression = ? analyzeExpression(fileCtx, module, funcCtx, kwarg.expression, some(analyzedField.argType))
  let impls = ? analyzeValueTypeAgainstDefType(module, analyzedField.argType, analyzedExpression.argType, analyzedExpression.loc)
  ok(newAnalyzedKeywordArgument(kwarg, analyzedField, analyzedExpression, impls))

proc analyzeUnionInitializer*(fileCtx: AnalyzedFileContext, module: AnalyzedDefModule, funcCtx: AnalyzedFunctionContext, init: AnalyzedDefUnionInitializer): Result[AnalyzedUnionInitializer, string] =
  ## Walks the variant's kwargs, checking each value against its field
  ## type and accumulating the generic bindings each kwarg contributes
  ## (carried on `AnalyzedKeywordArgument.impls`). Merging across
  ## fields enforces that kwargs binding the same generic agree — e.g.
  ## a variant `Ok { a: T, b: T }` with `a: u8, b: String` is rejected
  ## here. TODO: consume the merged map to concretize the result type.
  let unionModule = fileCtx.findModule(init.unionRef.module)
  let unionDef = unionModule.dataDef.union
  let variantDef = unionDef.findVariant(init.variant)

  var analyzedKwargs: seq[AnalyzedKeywordArgument]
  var impls: GenericImplMap
  for kwarg in init.kwargs:
    let field = ? variantDef.findField(kwarg.name)
    let analyzedKwarg = ? analyzeKeywordArgument(fileCtx, module, funcCtx, kwarg, field)
    impls = ? impls.merge(analyzedKwarg.impls)
    analyzedKwargs.add(analyzedKwarg)

  ok(newAnalyzedUnionInitializer(init, analyzedKwargs, impls))

proc analyzeStructInitializer*(fileCtx: AnalyzedFileContext, module: AnalyzedDefModule, funcCtx: AnalyzedFunctionContext, init: AnalyzedDefStructInitializer): Result[AnalyzedStructInitializer, string] =
  ## Walks the struct's kwargs, checking each value against its field
  ## type and accumulating the generic bindings each kwarg contributes
  ## (carried on `AnalyzedKeywordArgument.impls`). Merging across
  ## fields enforces that kwargs binding the same generic agree.
  ## TODO: consume the merged map to concretize the result type.
  let structModule = fileCtx.findModule(init.structRef.module)
  let structDef = structModule.dataDef.struct
  var analyzedKwargs: seq[AnalyzedKeywordArgument]
  var impls: GenericImplMap
  for kwarg in init.kwargs:
    let field = ? structDef.findField(kwarg.name)
    let analyzedKwarg = ? analyzeKeywordArgument(fileCtx, module, funcCtx, kwarg, field)
    impls = ? impls.merge(analyzedKwarg.impls)
    analyzedKwargs.add(analyzedKwarg)
  ok(newAnalyzedStructInitializer(init, analyzedKwargs, impls))

proc analyzeInitializer*(fileCtx: AnalyzedFileContext, module: AnalyzedDefModule, funcCtx: AnalyzedFunctionContext, init: AnalyzedDefInitializer): Result[AnalyzedInitializer, string] =
  case init.kind:
  of adikLiteral:
    let literalInit = ? analyzeLiteralInitializer(fileCtx, module, funcCtx, init.literal)
    ok(newAnalyzedInitializer(literalInit))
  of adikStruct:
    let structInit = ? analyzeStructInitializer(fileCtx, module, funcCtx, init.struct)
    ok(newAnalyzedInitializer(structInit))
  of adikUnion:
    let unionInit = ? analyzeUnionInitializer(fileCtx, module, funcCtx, init.union)
    ok(newAnalyzedInitializer(unionInit))

proc analyzeExpression*(fileCtx: AnalyzedFileContext, module: AnalyzedDefModule, funcCtx: AnalyzedFunctionContext, expression: AnalyzedDefExpression, expected: Option[AnalyzedArgumentType]): Result[AnalyzedExpression, string] =
  case expression.kind:
  of adekLiteral:
    let bareLit = ? analyzeBareLiteral(fileCtx, module, funcCtx, expression.literal, expected)
    ok(newAnalyzedExpression(newAnalyzedInitializer(bareLit)))
  of adekVariable:
    let analyzedVariable = ? analyzeVariable(funcCtx, expression.variable)
    ok(newAnalyzedExpression(analyzedVariable))
  of adekGetter:
    let analyzedGetter = ? analyzeGetter(fileCtx, module, funcCtx, expression.getter)
    ok(newAnalyzedExpression(analyzedGetter))
  of adekInitializer:
    let analyzedInit = ? analyzeInitializer(fileCtx, module, funcCtx, expression.init)
    ok(newAnalyzedExpression(analyzedInit))
  of adekFunctionCall:
    let analyzedFunctionCall = ? analyzeFunctionCall(fileCtx, module, funcCtx, expression.fncall)
    ok(newAnalyzedExpression(analyzedFunctionCall))
  of adekMatchExpr:
    let analyzedMatchExpr = ? analyzeMatchExpression(fileCtx, module, funcCtx, expression.match)
    ok(newAnalyzedExpression(analyzedMatchExpr))

proc analyzeAssignment*(fileCtx: AnalyzedFileContext, module: AnalyzedDefModule, funcCtx: AnalyzedFunctionContext, assignment: AnalyzedDefAssignment): Result[AnalyzedAssignment, string] =
  let analyzedExpr = ? analyzeExpression(fileCtx, module, funcCtx, assignment.expression, none(AnalyzedArgumentType))
  ok(newAnalyzedAssignment(assignment, analyzedExpr))

proc analyzeSetter*(fileCtx: AnalyzedFileContext, module: AnalyzedDefModule, funcCtx: AnalyzedFunctionContext, setter: AnalyzedDefSetter): Result[AnalyzedSetter, string] =
  let analyzedGetter = ? analyzeGetter(fileCtx, module, funcCtx, setter.getter)
  let analyzedExpression = ? analyzeExpression(fileCtx, module, funcCtx, setter.expression, some(analyzedGetter.argType))
  if analyzedGetter.argType != analyzedExpression.argType:
    err(fmt"{setter.loc} argument type mismatch") # TODO: improve error message
  else:
    ok(newAnalyzedSetter(setter, analyzedGetter, analyzedExpression))

proc analyzeStatement*(fileCtx: AnalyzedFileContext, module: AnalyzedDefModule, funcCtx: AnalyzedFunctionContext, statement: AnalyzedDefStatement): Result[AnalyzedStatement, string] =
  case statement.kind:
  of adskExpr:
    let analyzedExpr = ? analyzeExpression(fileCtx, module, funcCtx, statement.expression, none(AnalyzedArgumentType))
    ok(newAnalyzedStatement(analyzedExpr))
  of adskAssignment:
    let analyzedAssignment = ? analyzeAssignment(fileCtx, module, funcCtx, statement.assignment)
    ok(newAnalyzedStatement(analyzedAssignment))
  of adskSetter:
    let analyzedMutation = ? analyzeSetter(fileCtx, module, funcCtx, statement.setter)
    ok(newAnalyzedStatement(analyzedMutation))

proc analyzeUserFunction*(fileCtx: AnalyzedFileContext, module: AnalyzedDefModule, function: AnalyzedDefUserFunction): Result[AnalyzedUserFunction, string] =
  var funcCtx = newAnalyzedFunctionContext(function.def)
  assert(function.statements.len > 0, fmt"{function.loc} [BUG] empty user function must have been caught by the resolver")

  var analyzedStatements: seq[AnalyzedStatement]
  for statement in function.statements:
    let analyzedStatement = ? analyzeStatement(fileCtx, module, funcCtx, statement)
    analyzedStatements.add(analyzedStatement)
    funcCtx = funcCtx.update(analyzedStatement)

  if analyzedStatements[^1].argType != function.def.returns:
    err(fmt"{function.statements[^1].loc} function does not return the expected return type")
  else:
    ok(newAnalyzedUserFunction(function, analyzedStatements))

proc analyzeFunction(fileCtx: AnalyzedFileContext, module: AnalyzedDefModule, function: AnalyzedDefFunction): Result[AnalyzedFunction, string] =
  case function.kind:
  of adfkExtern:
    let analyzedExternFunction = newAnalyzedExternFunction(function.extern)
    ok(newAnalyzedFunction(analyzedExternFunction))
  of adfkUser:
    let analyzedUserFunction = ? analyzeUserFunction(fileCtx, module, function.user)
    ok(newAnalyzedFunction(analyzedUserFunction))

proc analyzeModule*(fileCtx: AnalyzedFileContext, module: AnalyzedDefModule): Result[AnalyzedModule, string] =
  var analyzedFunctions: seq[AnalyzedFunction]
  for function in module.functions:
    let analyzedFunction = ? analyzeFunction(fileCtx, module, function)
    analyzedFunctions.add(analyzedFunction)
  ok(newAnalyzedModule(module, analyzedFunctions))

proc analyzeImportedType*(impFile: AnalyzedDefFile, impType: AnalyzedDefImportedType): Result[AnalyzedImportedType, string] =
  let analyzedImpType = impFile.findType(impType.typ)
  ok(newAnalyzedImportedType(impType, analyzedImpType))

proc analyzeImport*(appCtx: AnalyzedAppContext, imp: AnalyzedDefImport): Result[AnalyzedImport, string] =
  let impFile = appCtx.findFileDef(imp.path)
  var analyzedImpTypes: seq[AnalyzedImportedType]
  for impType in imp.importedTypes:
    let analyzedImportedType = ? analyzeImportedType(impFile, impType)
    analyzedImpTypes.add(analyzedImportedType)
  ok(newAnalyzedImport(imp, analyzedImpTypes))

proc analyzeFile(appCtx: AnalyzedAppContext, fileDef: AnalyzedDefFile): Result[AnalyzedFile, string] =
  var analyzedImports: seq[AnalyzedImport]
  for imp in fileDef.imports:
    let analyzedImport = ? analyzeImport(appCtx, imp)
    analyzedImports.add(analyzedImport)

  let fileCtx = newAnalyzedFileContext(analyzedImports, fileDef.types)
  var analyzedModules: seq[AnalyzedModule]
  for module in fileDef.modules:
    let analyzedModule = ? analyzeModule(fileCtx, module)
    analyzedModules.add(analyzedModule)
  ok(newAnalyzedFile(fileDef, analyzedImports, analyzedModules))

proc analyze*(app: ResolvedApp): Result[AnalyzedApp, string] =
  let appDef = ? analyzeDefApp(app)
  let appCtx = newAnalyzedAppContext(appDef)
  for fileDef in appCtx.fileDefs:
    let analyzedFile = ? analyzeFile(appCtx, fileDef)
    appCtx.add(analyzedFile)
  ok(newAnalyzedApp(app, appCtx.files))
