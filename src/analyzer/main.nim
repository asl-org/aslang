## Body-analysis barrel — phase B of the two-pass analyzer, and the
## top of the compiler stack. Re-exports its own body walkers plus the
## public `analyze*` entry here. It does NOT re-export the layers below
## (defanalyzer / resolver / parser / tokenizer): every layer is a
## sibling under src/, so a consumer imports each layer whose types it
## actually uses, directly.

import options, results, sequtils, strformat, strutils, tables

import ../tokenizer/main as tokenizer
import ../parser/main as parser
import ../resolver/main as resolver
import ../defanalyzer/main as defanalyzer

import pattern
export pattern

import statement
export statement

import function
export function

import module
export module

import app
export app

import context

# ============================================================
# analyzeValueTypeAgainstDefType — structurally match a value's type
# against a declared (def) type, PRODUCING the generic impl map.
#
# A plain `==` on AnalyzedArgumentType only tests identity; it cannot
# report what each generic slot bound to. This walk descends both types
# in lockstep and, at each position:
#   - module vs module: require the same module, then recurse into every
#     impl slot (both sides carry the same require keys);
#   - def-side generic: solve it — record `generic -> valType` (with the
#     constraint defs the value must satisfy) into the map;
#   - def-side module vs value-side generic: reject (a concrete position
#     cannot be filled by an unbound generic).
# Bindings accumulate through `merge`, which enforces one concrete type
# per generic. This is why the assignability checks that must recover
# generic bindings (function-argument and kwarg checks) route through
# here rather than comparing with `==`.
# ============================================================

proc analyzeValueTypeAgainstDefType(module: AnalyzedDefModule, defType: AnalyzedArgumentType, valType: AnalyzedArgumentType, loc: Location): Result[AnalyzedImplMap, string]

proc analyzeValueTypeAgainstDefType(module: AnalyzedDefModule, defType: AnalyzedModuleArgumentType, valType: AnalyzedModuleArgumentType, loc: Location): Result[AnalyzedImplMap, string] =
  if defType.module != valType.module:
    err(fmt"{loc} expected `{defType.name.asl}` but found `{valType.name.asl}`")
  else:
    var genericImplMap: AnalyzedImplMap
    # Same module ⇒ both impl maps are keyed by the same require slots;
    # walk the def slots and match each against the value's impl in the
    # same slot.
    for defGeneric, defImpl in defType.impls:
      let valImpl = valType.impls[defGeneric]
      let valAnalyzedImplMap = ? analyzeValueTypeAgainstDefType(module, defImpl.argType, valImpl.argType, loc)
      genericImplMap = ? genericImplMap.merge(valAnalyzedImplMap)
    ok(genericImplMap)

proc analyzeValueTypeAgainstDefType(module: AnalyzedDefModule, defType: AnalyzedGenericArgumentType, valType: AnalyzedArgumentType, loc: Location): Result[AnalyzedImplMap, string] =
  let typeCtx = newResolvedTypeContext(module.resolved)
  var genericImplMap: AnalyzedImplMap
  let defs = ? analyzeDefImpl(typeCtx, defType.generic, valType)
  genericImplMap[defType.generic] = newAnalyzedImpl(valType, defs)
  ok(genericImplMap)

proc analyzeValueTypeAgainstDefType(module: AnalyzedDefModule, defType: AnalyzedModuleArgumentType, valType: AnalyzedArgumentType, loc: Location): Result[AnalyzedImplMap, string] =
  case valType.kind:
  of aatkGeneric:
    err(fmt"{loc} expected a module {defType.asl} type but found generic type {valType.asl}")
  of aatkModule:
    analyzeValueTypeAgainstDefType(module, defType, valType.module, loc)

proc analyzeValueTypeAgainstDefType(module: AnalyzedDefModule, defType: AnalyzedArgumentType, valType: AnalyzedArgumentType, loc: Location): Result[AnalyzedImplMap, string] =
  case defType.kind:
  of aatkModule: analyzeValueTypeAgainstDefType(module, defType.module, valType, loc)
  of aatkGeneric: analyzeValueTypeAgainstDefType(module, defType.generic, valType, loc)

proc analyzeUnionCasePattern*(variantPattern: UnionPattern, union: AnalyzedUnionDef, subjectType: AnalyzedArgumentType): Result[AnalyzedUnionPattern, string] =
  let variant = union.findVariant(variantPattern.name)
  var bindings: seq[AnalyzedBinding]
  for field in variantPattern.fields:
    let fieldDef = ? variant.findField(field.name)
    bindings.add(newAnalyzedBinding(field.binding, fieldDef, subjectType.impls))
  ok(newAnalyzedUnionPattern(variantPattern, variant, bindings))

proc analyzeCasePattern*(pattern: ResolvedCasePattern, subjectType: AnalyzedArgumentType, union: AnalyzedUnionDef): Result[AnalyzedCasePattern, string] =
  case pattern.kind:
  of rcpkInteger: err(fmt"{pattern.loc} integer literals are not allowed in union case pattern")
  of rcpkVariable:
    ok(newAnalyzedCasePattern(newAnalyzedBinding(pattern.variable, subjectType)))
  of rcpkUnion:
    let analyzedPattern = ? analyzeUnionCasePattern(pattern.variant, union, subjectType)
    ok(newAnalyzedCasePattern(analyzedPattern))

proc analyzeCasePattern*(pattern: ResolvedCasePattern, subjectType: AnalyzedArgumentType): Result[AnalyzedCasePattern, string] =
  case pattern.kind:
  of rcpkUnion:
    err(fmt"{pattern.loc} union variants are not allowed in literal case pattern")
  of rcpkInteger:
    ok(newAnalyzedCasePattern(pattern.integer))
  of rcpkVariable:
    ok(newAnalyzedCasePattern(newAnalyzedBinding(pattern.variable, subjectType)))

proc analyzeVariable*(funcCtx: AnalyzedUserFunctionContext, variable: Identifier): Result[AnalyzedVariable, string] =
  let binding = ? funcCtx.get(variable)
  ok(newAnalyzedVariable(variable, binding.argType))

proc analyzeStructGetter*(funcCtx: AnalyzedUserFunctionContext, getter: ResolvedGetter): Result[AnalyzedStructGetter, string] =
  let binding = ? funcCtx.get(getter.source)
  let sourceArgType = binding.argType
  case sourceArgType.kind:
  of aatkGeneric:
    err(fmt"{getter.loc} expected `{getter.source.asl}` to be a module but found generic ")
  of aatkModule:
    let sourceModuleArgType = sourceArgType.module
    let sourceModule = funcCtx.findModule(sourceModuleArgType.module)
    case sourceModule.dataOrFail.kind:
    of adkUnion: err(fmt"{getter.loc} expected module `{sourceModule.name.asl}` to have a struct getter.block but found union")
    of adkLiteral: err(fmt"{getter.loc} expected module `{sourceModule.name.asl}` to have a struct block getter.but found literal")
    of adkStruct:
      let struct = sourceModule.dataOrFail.struct
      let property = ? struct.findField(getter.property)
      ok(newAnalyzedStructGetter(getter, sourceModuleArgType, property))

proc analyzeLiteralInitializer*(funcCtx: AnalyzedUserFunctionContext, init: AnalyzedDefLiteralInitializer): Result[AnalyzedLiteralInitializer, string] =
  let argDefModule = funcCtx.findModule(init.argType.module)
  case argDefModule.dataOrFail.kind:
  of adkStruct: err(fmt"{init.loc} statement expects a literal initializer `{argDefModule.name.asl}`")
  of adkUnion: err(fmt"{init.loc} statement expects a literal initializer `{argDefModule.name.asl}`")
  of adkLiteral:
    ? argDefModule.dataOrFail.literal.validate(init.literal)
    ok(newAnalyzedLiteralInitializer(init.literal, init.argType))

# Forward declarations for the analyzeX procs in the cluster.
# `returns` is the enclosing function's declared return type, threaded
# through the whole body walk so a `try f()` call can check that the
# callee's Status error type matches the function's own (both must be
# `Status[_, E]` with the same `E`).
proc analyzeExpression*(funcCtx: AnalyzedUserFunctionContext, expression: AnalyzedDefExpression, expected: Option[AnalyzedArgumentType]): Result[AnalyzedExpression, string]
proc analyzeStatement*(funcCtx: AnalyzedUserFunctionContext, statement: AnalyzedDefStatement): Result[AnalyzedStatement, string]

proc analyzeArgumentList*(funcCtx: AnalyzedUserFunctionContext, argValues: seq[AnalyzedExpression], analyzedFuncDef: AnalyzedFunctionDef): Result[AnalyzedImplMap, string] =
  # Reads pre-analyzed args directly from the AnalyzedFunctionDef
  # — no lookup, no re-analysis. Every analyzed expression carries a
  # concrete argType post-Approach C; bare literals adopt the caller's
  # expected type or default to i32/f32/String at the
  # analyzeBareLiteral site. Per-candidate type context is threaded
  # from `analyzeFunctionCall`.
  assert(analyzedFuncDef.args.len == argValues.len,
    fmt"BUG: analyzeArgumentList arity mismatch — funcDef has {analyzedFuncDef.args.len} args, call site passed {argValues.len}. zip would silently truncate; fix by erroring (or relying on resolver / overload selection).")
  var genericImplMap: AnalyzedImplMap
  for (analyzedArgDef, argValue) in zip(analyzedFuncDef.args, argValues):
    let argAnalyzedImplMap = ? analyzeValueTypeAgainstDefType(funcCtx.module, analyzedArgDef.argType, argValue.argType, argValue.loc)
    genericImplMap = ? genericImplMap.merge(argAnalyzedImplMap)
  ok(genericImplMap)

proc analyzeArgumentList(funcCtx: AnalyzedUserFunctionContext, fncall: AnalyzedDefFunctionCall, funcDefs: seq[AnalyzedFunctionDef]): Result[(AnalyzedFunctionDef, seq[AnalyzedExpression], AnalyzedImplMap), string] =
  # Per-candidate analysis over pre-analyzed AnalyzedFunctionDef
  # candidates: for each candidate, walk the call's raw arguments and
  # analyze each with the candidate's declared arg type (pre-analyzed)
  # as the expected context. Bare literals adopt the declared type when
  # concrete, or default to i32/f32/String otherwise
  # (`analyzeBareLiteral`). First candidate whose args analyze +
  # type-check wins; ambiguity fires the existing multi-match error
  # path.
  var matches: seq[(AnalyzedFunctionDef, seq[AnalyzedExpression], AnalyzedImplMap)]
  var errors: seq[string]
  for index, analyzedFuncDef in funcDefs:
    assert(analyzedFuncDef.args.len == fncall.args.len, "[BUG] - UNREACHABLE")
    var analyzedArgs: seq[AnalyzedExpression]
    var candidateErr = ""
    for (actualArg, expectedArg) in zip(fncall.args, analyzedFuncDef.args):
      let maybeAnalyzed = analyzeExpression(funcCtx, actualArg, some(expectedArg.argType))
      if maybeAnalyzed.isErr:
        candidateErr = maybeAnalyzed.error
        break
      analyzedArgs.add(maybeAnalyzed.get)
    if candidateErr.len > 0:
      errors.add(fmt"[{index + 1}] - {candidateErr}")
      errors.add("\t" & fmt"{analyzedFuncDef.loc}: {analyzedFuncDef.asl}")
      continue
    let maybeAnalyzedImplMap = analyzeArgumentList(funcCtx, analyzedArgs, analyzedFuncDef)
    if maybeAnalyzedImplMap.isOk:
      matches.add((analyzedFuncDef, analyzedArgs, maybeAnalyzedImplMap.get))
    else:
      errors.add(fmt"[{index + 1}] - " & maybeAnalyzedImplMap.error)
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

proc analyzeBareLiteral(funcCtx: AnalyzedUserFunctionContext, literal: AnalyzedDefLiteral, expected: Option[AnalyzedArgumentType]): Result[AnalyzedLiteralInitializer, string] =
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

  let argDefModule = funcCtx.findModule(literalArgType.module)
  case argDefModule.dataOrFail.kind:
  of adkStruct: err(fmt"{literal.loc} expected a struct initializer of type `{argDefModule.name.asl}` but found bare literal")
  of adkUnion: err(fmt"{literal.loc} expected a union initializer of type `{argDefModule.name.asl}` but found bare literal")
  of adkLiteral:
    ? argDefModule.dataOrFail.literal.validate(literal.value)
    ok(newAnalyzedLiteralInitializer(literal.value, literalArgType))

proc statusSlots(status: AnalyzedModuleArgumentType, loc: Location): Result[(AnalyzedArgumentType, AnalyzedArgumentType), string] =
  ## The (value, error) type arguments of a `Status[Value, Error]`. The
  ## impl map keeps require-slot order — value (Ok's `Any`) first, error
  ## (Err's `Failure`) second — so a fully-parameterized Status yields
  ## exactly two slots.
  var slots: seq[AnalyzedArgumentType]
  for _, impl in status.impls:
    slots.add(impl.argType)
  if slots.len < 2:
    err(fmt"{loc} `try` requires a fully-parameterized Status[Value, Error]")
  else:
    ok((slots[0], slots[1]))

proc analyzeFunctionCall*(funcCtx: AnalyzedUserFunctionContext, fncall: AnalyzedDefFunctionCall): Result[AnalyzedFunctionCall, string] =
  let localType = funcCtx.findType(fncall.typ)
  let access =
    case localType.kind:
    of altkGeneric:
      faPublic
    of altkModule:
      if funcCtx.module == localType.module: faAll else: faPublic
  let maybeFuncDefs = localType.findFunctionDefs(fncall.name, fncall.arity, access)
  assert(maybeFuncDefs.isOk, "[BUG] - Resolver validates every call target (name, arity, access) at resolve time")
  let funcDefs = maybeFuncDefs.get

  let (matchingFuncDef, analyzedArgs, genericImpls) = ? analyzeArgumentList(funcCtx, fncall, funcDefs)
  # The impl map inferred from the arguments rides on the call node;
  # the `returns` accessor concretizes the funcDef's return type from
  # it on access (matching the initializers).
  case fncall.resolved.kind:
  of fckDefault:
    return ok(newAnalyzedFunctionCall(fncall, localType, matchingFuncDef, analyzedArgs, genericImpls))
  of fckTry:
    # `try f()` requires the callee to return a Status[Value, Error]; the
    # expression evaluates to the unwrapped Ok `Value`. Its Err is
    # propagated as the enclosing function's own error, so that function
    # must ALSO return a Status whose error type matches the callee's.
    let concreteReturn = matchingFuncDef.returns.concrete(genericImpls)
    case concreteReturn.kind:
    of aatkGeneric:
      return err(fmt"{fncall.loc} `try` requires a call that returns a Status, but `{fncall.name.asl}` returns generic type `{concreteReturn.name.asl}`")
    of aatkModule:
      let calleeStatus = concreteReturn.module
      if calleeStatus.name.asl != "Status":
        return err(fmt"{fncall.loc} `try` requires a call that returns a Status, but `{fncall.name.asl}` returns `{concreteReturn.asl}`")
      let (calleeValue, calleeError) = ? statusSlots(calleeStatus, fncall.loc)
      let returns = funcCtx.returns
      case returns.kind:
      of aatkGeneric:
        return err(fmt"{fncall.loc} `try` can only appear in a function returning a Status, but this function returns generic type `{returns.name.asl}`")
      of aatkModule:
        let fnStatus = returns.module
        if fnStatus.name.asl != "Status":
          return err(fmt"{fncall.loc} `try` can only appear in a function returning a Status, but this function returns `{returns.asl}`")
        let (_, fnError) = ? statusSlots(fnStatus, fncall.loc)
        if calleeError != fnError:
          return err(fmt"{fncall.loc} `try` error-type mismatch: `{fncall.name.asl}` propagates `{calleeError.asl}` but the enclosing function's error type is `{fnError.asl}`")
        return ok(newAnalyzedTryFunctionCall(fncall, localType, matchingFuncDef, analyzedArgs, genericImpls, calleeValue))

proc analyzeCaseBlock*(funcCtx: AnalyzedUserFunctionContext, caseBlock: AnalyzedDefCase, subjectType: AnalyzedArgumentType, union: AnalyzedUnionDef): Result[AnalyzedCaseBlock, string] =
  var caseCtx = funcCtx.branch()

  let analyzedCasePattern = ? analyzeCasePattern(caseBlock.pattern, subjectType, union)
  caseCtx = caseCtx.update(analyzedCasePattern)

  var analyzedStatements: seq[AnalyzedStatement]
  for statement in caseBlock.statements:
    let analyzedStatement = ? analyzeStatement(caseCtx, statement)
    analyzedStatements.add(analyzedStatement)
    caseCtx = caseCtx.update(analyzedStatement)
  ok(newAnalyzedCaseBlock(caseBlock, analyzedCasePattern, analyzedStatements))

proc analyzeCaseBlock*(funcCtx: AnalyzedUserFunctionContext, caseBlock: AnalyzedDefCase, subjectType: AnalyzedArgumentType): Result[AnalyzedCaseBlock, string] =
  var caseCtx = funcCtx.branch()

  let analyzedCasePattern = ? analyzeCasePattern(caseBlock.pattern, subjectType)
  caseCtx = caseCtx.update(analyzedCasePattern)

  var analyzedStatements: seq[AnalyzedStatement]
  for statement in caseBlock.statements:
    let analyzedStatement = ? analyzeStatement(caseCtx, statement)
    analyzedStatements.add(analyzedStatement)
    caseCtx = caseCtx.update(analyzedStatement)
  ok(newAnalyzedCaseBlock(caseBlock, analyzedCasePattern, analyzedStatements))

proc verifyUniformReturnType(cases: seq[AnalyzedCaseBlock]): Result[void, string] =
  let expected = cases[0].argType
  for c in cases:
    if c.argType != expected:
      return err(fmt"{c.loc} todo: return an error message telling that the case block return types are not same")
  ok()

proc analyzeCases*(funcCtx: AnalyzedUserFunctionContext, cases: seq[AnalyzedDefCase], subjectType: AnalyzedArgumentType, union: AnalyzedUnionDef, loc: Location): Result[seq[AnalyzedCaseBlock], string] =
  var patternScope = newAnalyzedUnionPatternScope(cases.len)
  for id, caseBlock in cases:
    patternScope = ? patternScope.update(id, caseBlock.pattern)

  ? hasUncoveredCases(patternScope, union.variants.len, loc)

  assert(cases.len > 0, "UNREACHABLE: zero-case match should have been caught by the resolver")

  var analyzedCaseBlocks: seq[AnalyzedCaseBlock]
  for caseBlock in cases:
    let analyzedCaseBlock = ? analyzeCaseBlock(funcCtx, caseBlock, subjectType, union)
    analyzedCaseBlocks.add(analyzedCaseBlock)
  ? verifyUniformReturnType(analyzedCaseBlocks)
  ok(analyzedCaseBlocks)

proc analyzeCases*(funcCtx: AnalyzedUserFunctionContext, cases: seq[AnalyzedDefCase], subjectType: AnalyzedArgumentType, literal: AnalyzedLiteralDef, loc: Location): Result[seq[AnalyzedCaseBlock], string] =
  var patternScope = ? newAnalyzedLiteralPatternScope(literal, cases.len)
  for id, caseBlock in cases:
    patternScope = ? patternScope.update(id, caseBlock.pattern)

  ? hasUncoveredCases(patternScope, loc)

  assert(cases.len > 0, "UNREACHABLE: zero-case match should have been caught by the resolver")

  var analyzedCaseBlocks: seq[AnalyzedCaseBlock]
  for caseBlock in cases:
    let analyzedCaseBlock = ? analyzeCaseBlock(funcCtx, caseBlock, subjectType)
    analyzedCaseBlocks.add(analyzedCaseBlock)
  ? verifyUniformReturnType(analyzedCaseBlocks)
  ok(analyzedCaseBlocks)

proc analyzeMatchExpression*(funcCtx: AnalyzedUserFunctionContext, match: AnalyzedDefMatch): Result[AnalyzedMatchExpression, string] =
  let subjectExpr = ? analyzeExpression(funcCtx, match.subject, none(AnalyzedArgumentType))
  let subjectArgType = subjectExpr.argType
  case subjectArgType.kind:
  of aatkGeneric:
    err(fmt"{match.subject.loc} expected subject expression to return a module but found generic")
  of aatkModule:
    let subjectDataModule = funcCtx.findModule(subjectArgType.module.module)
    case subjectDataModule.dataOrFail.kind:
    of adkStruct:
      err(fmt"{match.loc} match block only supports literal and union types but subject expression returns `{subjectArgType.name.asl}` a struct type")
    of adkLiteral:
      assert(match.cases.len > 0, "UNREACHABLE: zero-case match should have been caught by the resolver")
      let analyzedCases = ? analyzeCases(funcCtx, match.cases, subjectArgType, subjectDataModule.dataOrFail.literal, match.loc)
      ok(newAnalyzedMatchExpression(match, subjectExpr, analyzedCases))
    of adkUnion:
      assert(match.cases.len > 0, "UNREACHABLE: zero-case match should have been caught by the resolver")
      let analyzedCases = ? analyzeCases(funcCtx, match.cases, subjectArgType, subjectDataModule.dataOrFail.union, match.loc)
      ok(newAnalyzedMatchExpression(match, subjectExpr, analyzedCases))

proc analyzeKeywordArgument*(funcCtx: AnalyzedUserFunctionContext, kwarg: AnalyzedDefKeywordArgument, analyzedField: AnalyzedArgumentDef): Result[AnalyzedKeywordArgument, string] =
  # Field's declared type is the expected context — bare literals in
  # kwarg values adapt when concrete, default when generic. The
  # value-vs-field check yields the bindings this kwarg contributes
  # (field `value: T` + a `u8` value binds `T -> u8`); they ride on
  # the kwarg node so the initializer can merge them across fields.
  let analyzedExpression = ? analyzeExpression(funcCtx, kwarg.expression, some(analyzedField.argType))
  let impls = ? analyzeValueTypeAgainstDefType(funcCtx.module, analyzedField.argType, analyzedExpression.argType, analyzedExpression.loc)
  ok(newAnalyzedKeywordArgument(kwarg, analyzedField, analyzedExpression, impls))

proc analyzeUnionInitializer*(funcCtx: AnalyzedUserFunctionContext, init: AnalyzedDefUnionInitializer): Result[AnalyzedUnionInitializer, string] =
  ## Walks the variant's kwargs, checking each value against its field
  ## type and accumulating the generic bindings each kwarg contributes
  ## (carried on `AnalyzedKeywordArgument.impls`). Merging across
  ## fields enforces that kwargs binding the same generic agree — e.g.
  ## a variant `Ok { a: T, b: T }` with `a: u8, b: String` is rejected
  ## here.
  let unionModule = funcCtx.findModule(init.unionRef.module)
  let unionDef = unionModule.dataOrFail.union
  let variantDef = unionDef.findVariant(init.variant)

  var analyzedKwargs: seq[AnalyzedKeywordArgument]
  # Auto-inference: the ref may or may not carry explicit impls. Seed
  # the map with the ref's own impls (`u8!.Ok {...}` → {Any: u8, Failure: Error})
  # so a kwarg value contradicting them is caught by merge; a bare ref
  # (`Status.Ok {...}`) seeds empty and the kwargs infer the slots.
  var impls = init.unionRef.argType.impls
  for kwarg in init.kwargs:
    let field = ? variantDef.findField(kwarg.name)
    let analyzedKwarg = ? analyzeKeywordArgument(funcCtx, kwarg, field)
    impls = ? impls.merge(analyzedKwarg.impls)
    analyzedKwargs.add(analyzedKwarg)

  # A variant only touches the generics its own fields use, but the
  # union type has all of them — the merged map may cover only a
  # subset. Rebuild it over the union's canonical slots so every slot
  # is present and in order: a covered slot keeps its concrete binding,
  # an uncovered one defaults to itself (a free generic, leave-as-is).
  var completeImpls: AnalyzedImplMap
  for requirement in unionModule.requires:
    completeImpls[requirement.generic] = impls.getOrDefault(requirement.generic, requirement.newAnalyzedArgumentType.newAnalyzedImpl)

  ok(newAnalyzedUnionInitializer(init, analyzedKwargs, completeImpls))

proc analyzeStructInitializer*(funcCtx: AnalyzedUserFunctionContext, init: AnalyzedDefStructInitializer): Result[AnalyzedStructInitializer, string] =
  ## Walks the struct's kwargs, checking each value against its field
  ## type and accumulating the generic bindings each kwarg contributes
  ## (carried on `AnalyzedKeywordArgument.impls`). Merging across
  ## fields enforces that kwargs binding the same generic agree.
  let structModule = funcCtx.findModule(init.structRef.module)
  let structDef = structModule.dataOrFail.struct
  var analyzedKwargs: seq[AnalyzedKeywordArgument]
  # Auto-inference: the ref may or may not carry explicit impls. Seed
  # the map with the ref's own impls (`Pair[u8] {...}` → {T: u8}) so a
  # kwarg value contradicting them is caught by merge; a bare ref
  # (`Pair {...}`) seeds empty and the kwargs infer the slots.
  var impls = init.structRef.argType.impls
  for kwarg in init.kwargs:
    let field = ? structDef.findField(kwarg.name)
    let analyzedKwarg = ? analyzeKeywordArgument(funcCtx, kwarg, field)
    impls = ? impls.merge(analyzedKwarg.impls)
    analyzedKwargs.add(analyzedKwarg)

  # The merged map follows kwarg order, not slot order. Rebuild it over the
  # struct's canonical slots so the initializer's type has every slot, in
  # order: a covered slot keeps its binding, an uncovered one defaults to
  # itself (a free generic, leave-as-is) — as for union initializers.
  var completeImpls: AnalyzedImplMap
  for requirement in structModule.requires:
    completeImpls[requirement.generic] = impls.getOrDefault(requirement.generic, requirement.newAnalyzedArgumentType.newAnalyzedImpl)

  ok(newAnalyzedStructInitializer(init, analyzedKwargs, completeImpls))

proc analyzeInitializer*(funcCtx: AnalyzedUserFunctionContext, init: AnalyzedDefInitializer): Result[AnalyzedInitializer, string] =
  case init.kind:
  of adikLiteral:
    let literalInit = ? analyzeLiteralInitializer(funcCtx, init.literal)
    ok(newAnalyzedInitializer(literalInit))
  of adikStruct:
    let structInit = ? analyzeStructInitializer(funcCtx, init.struct)
    ok(newAnalyzedInitializer(structInit))
  of adikUnion:
    let unionInit = ? analyzeUnionInitializer(funcCtx, init.union)
    ok(newAnalyzedInitializer(unionInit))

proc analyzeExpression*(funcCtx: AnalyzedUserFunctionContext, expression: AnalyzedDefExpression, expected: Option[AnalyzedArgumentType]): Result[AnalyzedExpression, string] =
  case expression.kind:
  of adekLiteral:
    let bareLit = ? analyzeBareLiteral(funcCtx, expression.literal, expected)
    ok(newAnalyzedExpression(newAnalyzedInitializer(bareLit)))
  of adekVariable:
    let analyzedVariable = ? analyzeVariable(funcCtx, expression.variable)
    ok(newAnalyzedExpression(analyzedVariable))
  of adekGetter:
    let analyzedStructGetter = ? analyzeStructGetter(funcCtx, expression.getter)
    ok(newAnalyzedExpression(analyzedStructGetter))
  of adekInitializer:
    let analyzedInit = ? analyzeInitializer(funcCtx, expression.init)
    ok(newAnalyzedExpression(analyzedInit))
  of adekFunctionCall:
    let analyzedFunctionCall = ? analyzeFunctionCall(funcCtx, expression.fncall)
    ok(newAnalyzedExpression(analyzedFunctionCall))
  of adekMatchExpr:
    let analyzedMatchExpr = ? analyzeMatchExpression(funcCtx, expression.match)
    ok(newAnalyzedExpression(analyzedMatchExpr))

proc analyzeStatement*(funcCtx: AnalyzedUserFunctionContext, statement: AnalyzedDefStatement): Result[AnalyzedStatement, string] =
  case statement.kind:
  of rskGetter:
    # A getter-assignment (`p.a = <rhs>`) mutates a field: analyze the
    # getter to get the field's type, thread it into the RHS as the
    # expected type (so a bare literal adopts the field type and is
    # range-checked against it), then require the RHS type to match.
    let analyzedStructGetter = ? analyzeStructGetter(funcCtx, statement.getter)
    let analyzedExpr = ? analyzeExpression(funcCtx, statement.expression, some(analyzedStructGetter.argType))
    if analyzedStructGetter.argType != analyzedExpr.argType:
      err(fmt"{statement.loc} `{analyzedStructGetter.argType.asl}` field cannot be assigned a `{analyzedExpr.argType.asl}` value")
    else:
      ok(newAnalyzedStatement(statement, analyzedExpr, analyzedStructGetter))
  of rskNone, rskVariable:
    let analyzedExpr = ? analyzeExpression(funcCtx, statement.expression, none(AnalyzedArgumentType))
    ok(newAnalyzedStatement(statement, analyzedExpr))

proc analyzeUserFunction*(moduleCtx: AnalyzedModuleContext, function: AnalyzedDefUserFunction): Result[AnalyzedUserFunction, string] =
  var funcCtx = newAnalyzedUserFunctionContext(moduleCtx, function)
  assert(function.statements.len > 0, fmt"{function.loc} [BUG] empty user function must have been caught by the resolver")

  var statements: seq[AnalyzedStatement]
  for statement in function.statements:

    let statement = ? analyzeStatement(funcCtx, statement)
    statements.add(statement)
    funcCtx = funcCtx.update(statement)

  if statements[^1].argType != function.def.returns:
    err(fmt"{function.statements[^1].loc} function does not return the expected return type")
  else:
    ok(newAnalyzedUserFunction(function, statements))

proc analyzeFunction(moduleCtx: AnalyzedModuleContext, function: AnalyzedDefFunction): Result[AnalyzedFunction, string] =
  case function.kind:
  of adfkExtern:
    ok(newAnalyzedFunction(function.extern))
  of adfkUser:
    let userFunc = ? analyzeUserFunction(moduleCtx, function.user)
    ok(newAnalyzedFunction(userFunc))
  of adfkGenerated:
    ok(newAnalyzedFunction(function.generated))

proc analyzeModule*(fileCtx: AnalyzedFileContext, module: AnalyzedDefModule): Result[AnalyzedModule, string] =
  var analyzedFunctions: seq[AnalyzedFunction]
  let moduleCtx = newAnalyzedModuleContext(fileCtx, module)
  for function in module.functions:
    let analyzedFunction = ? analyzeFunction(moduleCtx, function)
    analyzedFunctions.add(analyzedFunction)
  ok(newAnalyzedModule(module, analyzedFunctions))

proc analyzeFile(appDef: AnalyzedDefApp, fileDef: AnalyzedDefFile): Result[AnalyzedFile, string] =
  var analyzedModules: seq[AnalyzedModule]
  let fileCtx = newAnalyzedFileContext(appDef, fileDef)
  for module in fileDef.modules:
    let analyzedModule = ? analyzeModule(fileCtx, module)
    analyzedModules.add(analyzedModule)
  ok(newAnalyzedFile(fileDef, analyzedModules))

proc analyze*(app: ResolvedApp): Result[AnalyzedApp, string] =
  var files: seq[AnalyzedFile]
  let appDef = ? analyzeDefApp(app)
  for fileDef in appDef.fileDefs:
    let file = ? analyzeFile(appDef, fileDef)
    files.add(file)
  ok(newAnalyzedApp(appDef, files))

