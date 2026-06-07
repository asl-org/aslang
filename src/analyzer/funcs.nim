import results, tables, strformat, sequtils, options, strutils, sets

import tokenizer
import parser
import resolver
import argtypes
import data
import funcdefs
import modules

type AnalyzedDefinedTypeScope* = Table[Identifier, AnalyzedDefinedType]
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
  if scope.variablePatternFound or scope.variants.len == totalVariants: ok()
  # TODO: improve error message by showing the uncovered variants
  else: err(fmt"case blocks do not cover all the variants")

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
    acpkVariant
  AnalyzedCasePattern = ref object
    case kind: AnalyzedCasePatternKind
    of acpkVariant: variant: AnalyzedVariantPattern

proc newAnalyzedCasePattern(variant: AnalyzedVariantPattern): AnalyzedCasePattern =
  AnalyzedCasePattern(kind: acpkVariant, variant: variant)

proc bindings(pattern: AnalyzedCasePattern): seq[AnalyzedArgumentDefinition] =
  case pattern.kind:
  of acpkVariant: pattern.variant.bindings

proc analyzeCasePattern*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, pattern: ResolvedCasePattern, union: AnalyzedUnion): Result[AnalyzedCasePattern, string] =
  case pattern.kind:
  of rcpkInteger: err(fmt"{pattern.loc} todo: analyze integer case pattern")
  of rcpkVariable: err(fmt"{pattern.loc} todo: analyze variable case pattern")
  of rcpkVariant:
    let analyzedPattern = ? analyzeVariantCasePattern(app, file, fileScope, module, defScope, funcScope, pattern.variant, union)
    ok(newAnalyzedCasePattern(analyzedPattern))

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

  AnalyzedExpressionKind = enum
    aekVariable, aekFunctionCall, aekLiteral, aekMatchExpr, aekInitializer
  AnalyzedExpression = ref object
    case kind: AnalyzedExpressionKind
    of aekVariable: variable: AnalyzedVariable
    of aekFunctionCall: fncall: AnalyzedFunctionCall
    of aekLiteral: literal: Literal
    of aekMatchExpr: match: AnalyzedMatchExpression
    of aekInitializer: init: AnalyzedInitializer

  AnalyzedStatementKind = enum
    askExpr, askAssignment
  AnalyzedStatement = ref object
    case kind: AnalyzedStatementKind
    of askExpr: expression: AnalyzedExpression
    of askAssignment: assignment: AnalyzedAssignment

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

proc newAnalyzedCaseBlock(resolved: ResolvedCaseBlock, pattern: AnalyzedCasePattern, statements: seq[AnalyzedStatement]): AnalyzedCaseBlock =
  AnalyzedCaseBlock(resolved: resolved, pattern: pattern, statements: statements)

proc argType(caseBlock: AnalyzedCaseBlock): Option[AnalyzedArgumentType] =
  assert(caseBlock.statements.len > 0, "UNREACHABLE: should have been caught by resolver")
  caseBlock.statements[^1].argType

proc newAnalyzedMatchExpression(resolved: ResolvedMatchExpression, subject: AnalyzedExpression, cases: seq[AnalyzedCaseBlock], returns: AnalyzedArgumentType): AnalyzedMatchExpression =
  AnalyzedMatchExpression(resolved: resolved, subject: subject, cases: cases, returns: returns)

proc newAnalyzedAssignment(resolved: ResolvedAssignment, expression: AnalyzedExpression): AnalyzedAssignment =
  AnalyzedAssignment(resolved: resolved, expression: expression)

proc loc(assignment: AnalyzedAssignment): Location = assignment.resolved.loc
proc target(assignment: AnalyzedAssignment): Identifier = assignment.resolved.target
proc argType(assignment: AnalyzedAssignment): Option[AnalyzedArgumentType] = assignment.expression.argType

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

proc loc(expression: AnalyzedExpression): Location =
  case expression.kind:
  of aekFunctionCall: return expression.fncall.loc
  of aekVariable: return expression.variable.loc
  of aekLiteral: return expression.literal.loc
  of aekMatchExpr:
    # BUG: both arms below hard-crash whenever the analyzer needs the loc
    # of a match-or-initializer expression — which happens the first time
    # analyzedSubjectExpr.loc fires on a nested match or an initializer
    # subject in analyzeMatchExpression (line ~393). Both have a `resolved`
    # field with a real loc — wire them through:
    #   of aekMatchExpr:   return expression.match.resolved.loc
    #   of aekInitializer: return expression.init.union.resolved.loc  (once
    #                      literal/struct initializer arms exist, dispatch
    #                      on init.kind first).
    assert(false, "BUG: AnalyzedExpression.loc is unwired for aekMatchExpr — delegate to expression.match.resolved.loc")
  of aekInitializer:
    assert(false, "BUG: AnalyzedExpression.loc is unwired for aekInitializer — delegate to expression.init's underlying resolved loc")

proc argType(expression: AnalyzedExpression): Option[AnalyzedArgumentType] =
  case expression.kind:
  of aekLiteral: return none(AnalyzedArgumentType)
  of aekFunctionCall: return some(expression.fncall.returns)
  of aekVariable: return some(expression.variable.argType)
  of aekMatchExpr: return some(expression.match.returns)
  of aekInitializer: return some(expression.init.argType)

proc newAnalyzedStatement(expression: AnalyzedExpression): AnalyzedStatement =
  AnalyzedStatement(kind: askExpr, expression: expression)

proc newAnalyzedStatement(assignment: AnalyzedAssignment): AnalyzedStatement =
  AnalyzedStatement(kind: askAssignment, assignment: assignment)

proc loc(statement: AnalyzedStatement): Location =
  case statement.kind:
  of askExpr: statement.expression.loc
  of askAssignment: statement.assignment.loc

proc argType(statement: AnalyzedStatement): Option[AnalyzedArgumentType] =
  case statement.kind:
  of askExpr: statement.expression.argType
  of askAssignment: statement.assignment.argType

proc arg(statement: AnalyzedStatement): Option[AnalyzedArgumentDefinition] =
  let maybeArgType = statement.argType
  if maybeArgType.isNone:
    assert(maybeArgType.isSome, fmt"{statement.loc} todo: support argType for statement")
  else:
    case statement.kind:
    of askExpr: return none(AnalyzedArgumentDefinition)
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

proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, defType: AnalyzedDefinedArgumentType, valType: AnalyzedArgumentType): Result[void, string] =
  case defType.kind:
  of adatkModule:
    ? analyzeValueTypeAgainstDefinitionType(app, file, fileScope, module, defScope, defType.module, valType)
    ok()
  of adatkGeneric:
    err(fmt"{valType.loc} todo: analyze value type against generic argument type")

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

proc analyzeFunctionCall*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, fncall: ResolvedFunctionCall): Result[AnalyzedFunctionCall, string] =
  let funcRef = ? analyzeFunctionRef(app, file, fileScope, module, defScope, fncall.funcRef)
  var analyzedArgs: seq[AnalyzedExpression]
  for arg in fncall.args:
    let analyzedArg = ? analyzeExpression(app, file, fileScope, module, defScope, funcScope, arg)
    analyzedArgs.add(analyzedArg)

  # BUG: overload selection below is broken — `maybeAnalyzedArgs` is computed
  # and discarded; `matchingFuncDef` is set unconditionally to the last
  # candidate every iteration. Fix: only set matchingFuncDef when
  # analyzeArgumentList(...).isOk (and probably break on first match, or
  # error on ambiguous match). For now this assert traps the multi-overload
  # path so the silent-wrong-candidate behaviour can't hide.
  assert(funcRef.funcDefs.len <= 1,
    fmt"{fncall.loc} BUG: overload resolution not implemented — found {funcRef.funcDefs.len} candidates but the loop below ignores analyzeArgumentList's result and silently picks the last one")
  var matchingFuncDef: Option[AnalyzedFunctionDefinition]
  for funcDef in funcRef.funcDefs:
    let maybeAnalyzedArgs = analyzeArgumentList(app, file, fileScope, module, defScope, funcScope, analyzedArgs, funcDef)
    matchingFuncDef = some(funcDef)

  if matchingFuncDef.isNone:
    var message: seq[string]
    message.add(fmt"{fncall.loc} failed to find matching function:")
    for funcDef in funcRef.funcDefs:
      message.add(fmt"\t\t{funcDef.loc}")
    err(message.join("\n"))
  else:
    # TODO: find a way to compute concrete return type for now just passing along the funcDef.returns
    ok(newAnalyzedFunctionCall(fncall, funcRef, analyzedArgs, matchingFuncDef.get.returns))

proc analyzeCaseBlock*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, caseBlock: ResolvedCaseBlock, union: AnalyzedUnion): Result[AnalyzedCaseBlock, string] =
  let analyzedCasePattern = ? analyzeCasePattern(app, file, fileScope, module, defScope, funcScope, caseBlock.pattern, union)
  var caseScope = funcScope.clone()
  for binding in analyzedCasePattern.bindings:
    caseScope[binding.name] = binding.argType
  var analyzedStatements: seq[AnalyzedStatement]
  for statement in caseBlock.statements:
    let analyzedStatement = ? analyzeStatement(app, file, fileScope, module, defScope, caseScope, statement)
    analyzedStatements.add(analyzedStatement)
  ok(newAnalyzedCaseBlock(caseBlock, analyzedCasePattern, analyzedStatements))

proc analyzeCases*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, cases: seq[ResolvedCaseBlock], union: AnalyzedUnion): Result[seq[AnalyzedCaseBlock], string] =
  var patternScope = newAnalyzedVariantPatternScope(cases.len)
  for id, caseBlock in cases:
    patternScope = ? patternScope.update(id, caseBlock.pattern)

  ? hasUncoveredCases(patternScope, union.variants.len)

  var analyzedCaseBlocks: seq[AnalyzedCaseBlock]
  # BUG: this assert was `cases.len > 1` which incorrectly crashed on a
  # legitimate single-case match. Relaxed to `> 0` (resolver still rejects
  # zero-case matches). Fix: leave the relaxed condition or drop the assert
  # entirely when the surrounding logic is reviewed.
  assert(cases.len > 0, "BUG: a match block with zero cases should have been caught by the resolver — previously asserted `cases.len > 1` which also crashed on valid single-case matches")
  for id, caseBlock in cases:
    let analyzedCaseBlock = ? analyzeCaseBlock(app, file, fileScope, module, defScope, funcScope, caseBlock, union)
    analyzedCaseBlocks.add(analyzedCaseBlock)
    if analyzedCaseBlock.argType.isNone:
      return err(fmt"{caseBlock.loc} todo: handle case block returning literal type")
    else:
      if id == 0:
        # NOTE: first case block does not have any return type to compare to so let it be
        discard
      else:
        let currentCaseArgType = analyzedCaseBlock.argType.get
        if currentCaseArgType != analyzedCaseBlocks[0].argType.get:
          return err(fmt"{caseBlock.loc} todo: return an error message telling that the case block return types are not same")
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
      err(fmt"{match.loc} todo: analyze case blocks for literal module")
    of adkUnion:
      if match.cases.len == 0:
        err(fmt"{match.loc} UNREACHABLE: match block does not contain any case blocks")
      else:
        # BUG: this assert was `match.cases.len > 1` — incorrectly crashed on
        # legitimate single-case matches. Relaxed to `> 0`; revisit when
        # surrounding logic is reviewed.
        assert(match.cases.len > 0, "BUG: match block with zero cases should be impossible by here (covered by the branch above); previously asserted `> 1` which also crashed on valid single-case matches")
        let analyzedCases = ? analyzeCases(app, file, fileScope, module, defScope, funcScope, match.cases, analyzedSubjectDataType.union)
        # BUG: the uniform-return check below duplicates the same loop inside
        # analyzeCases (lines 379–388). Pick one site to own the check and
        # remove the other. For now the duplicate is harmless because
        # analyzeCases would already have errored above on a mismatch.
        for id, caseBlock in analyzedCases:
          if caseBlock.argType.isNone:
            return err(fmt"{match.cases[id].loc} todo: handle case block returning literal type")
          else:
            if id == 0:
              # NOTE: first case block does not have any return type to compare to so let it be
              discard
            else:
              if caseBlock.argType.get != analyzedCases[0].argType.get:
                return err(fmt"{match.cases[id].loc} todo: return an error message telling that the case block return types are not same")
        ok(newAnalyzedMatchExpression(match, analyzedSubjectExpr, analyzedCases, analyzedCases[0].argType.get))

proc analyzeKeywordArgument*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, kwarg: ResolvedKeywordArgument, analyzedField: AnalyzedArgumentDefinition): Result[AnalyzedKeywordArgument, string] =
  let analyzedExpression = ? analyzeExpression(app, file, fileScope, module, defScope, funcScope, kwarg.expression)
  if analyzedExpression.argType.isNone:
    err(fmt"{kwarg.expression.loc} todo: analyze union initializer literal argument")
  else:
    ? analyzeValueTypeAgainstDefinitionType(app, file, fileScope, module, defScope, analyzedField.argType, analyzedExpression.argType.get)
    ok(newAnalyzedKeywordArgument(kwarg, analyzedField, analyzedExpression))

proc analyzeUnionInitializer*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, init: ResolvedUnionInitializer): Result[AnalyzedUnionInitializer, string] =
  let analyzedArgType = ? analyzeArgumentType(app, file, fileScope, module, init.argType)
  let argModule = ? defScope.findModuleDef(analyzedArgType, init.loc)
  let dataBlock = ? defScope.extractDataBlock(argModule, init.loc)
  case dataBlock.kind:
  of adkLiteral:
    err(fmt"{init.loc} expected module `{argModule.name.asl}` to have a union block but found literal")
  of adkStruct:
    err(fmt"{init.loc} expected module `{argModule.name.asl}` to have a union block but found struct")
  of adkUnion:
    let analyzedVariant = ? dataBlock.union.findVariant(init.variant)
    var analyzedKwargs: seq[AnalyzedKeywordArgument]
    for kwarg in init.kwargs:
      let analyzedField: AnalyzedArgumentDefinition = ? analyzedVariant.findField(kwarg.name)
      let analyzedKwarg = ? analyzeKeywordArgument(app, file, fileScope, module, defScope, funcScope, kwarg, analyzedField)
      analyzedKwargs.add(analyzedKwarg)
    ok(newAnalyzedUnionInitializer(init, analyzedArgType, analyzedVariant, analyzedKwargs))

proc analyzeStructInitializer*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, init: ResolvedStructInitializer): Result[AnalyzedStructInitializer, string] =
  let analyzedArgType = ? analyzeArgumentType(app, file, fileScope, module, init.argType)
  let argModule = ? defScope.findModuleDef(analyzedArgType, init.loc)
  let dataBlock = ? defScope.extractDataBlock(argModule, init.loc)
  case dataBlock.kind:
  of adkLiteral:
    err(fmt"{init.loc} expected module `{argModule.name.asl}` to have a struct block but found literal")
  of adkUnion:
    err(fmt"{init.loc} expected module `{argModule.name.asl}` to have a struct block but found union")
  of adkStruct:
    var analyzedKwargs: seq[AnalyzedKeywordArgument]
    for kwarg in init.kwargs:
      let analyzedField = ? dataBlock.struct.findField(kwarg.name)
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
  of rekInitializer:
    let analyzedInit = ? analyzeInitializer(app, file, fileScope, module, defScope, funcScope, expression.init)
    ok(newAnalyzedExpression(analyzedInit))
  of rekGetter: err(fmt"{expression.loc} todo: analyze getter")
  of rekLiteral: ok(newAnalyzedExpression(expression.literal))
  of rekVariable:
    let analyzedVariable = ? analyzeVariable(funcScope, expression.variable)
    ok(newAnalyzedExpression(analyzedVariable))
  of rekFunctionCall:
    let analyzedFunctionCall = ? analyzeFunctionCall(app, file, fileScope, module, defScope, funcScope, expression.fncall)
    ok(newAnalyzedExpression(analyzedFunctionCall))
  of rekMatchExpr:
    let analyzedMatchExpr = ? analyzeMatchExpression(app, file, fileScope, module, defScope, funcScope, expression.match)
    ok(newAnalyzedExpression(analyzedMatchExpr))

proc analyzeAssignment*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, assignment: ResolvedAssignment): Result[AnalyzedAssignment, string] =
  let analyzedExpr = ? analyzeExpression(app, file, fileScope, module, defScope, funcScope, assignment.expression)
  ok(newAnalyzedAssignment(assignment, analyzedExpr))

proc analyzeStatement*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, statement: ResolvedStatement): Result[AnalyzedStatement, string] =
  case statement.kind:
  of rskExpr:
    let analyzedExpr = ? analyzeExpression(app, file, fileScope, module, defScope, funcScope, statement.expression)
    ok(newAnalyzedStatement(analyzedExpr))
  of rskAssignment:
    let analyzedAssignment = ? analyzeAssignment(app, file, fileScope, module, defScope, funcScope, statement.assignment)
    ok(newAnalyzedStatement(analyzedAssignment))
  of rskMutation: err(fmt"{statement.loc} todo: analyze mutation")

type AnalyzedUserFunction = ref object
  resolved: ResolvedUserFunction
  def: AnalyzedFunctionDefinition
  statements: seq[AnalyzedStatement]

proc newAnalyzedUserFunction(resolved: ResolvedUserFunction, def: AnalyzedFunctionDefinition, statements: seq[AnalyzedStatement]): AnalyzedUserFunction =
  AnalyzedUserFunction(resolved: resolved, def: def, statements: statements)

proc analyzeUserFunction*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, function: ResolvedUserFunction): Result[AnalyzedUserFunction, string] =
  var funcScope: AnalyzedFunctionScope
  # BUG: `defScope[module.name]` below raises KeyError before `?` runs if the
  # module isn't in scope. Today analyzeFile populates defScope before
  # calling analyzeModule, so this is safe in practice — but the pattern
  # diverges from findModuleDef / analyzeFunctionRef which both guard with
  # `notin defScope` first. Fix: convert to a guarded lookup that returns a
  # Result[..., string] like the other helpers.
  assert(module.name in defScope,
    fmt"{function.loc} BUG: defScope is missing `{module.name.asl}` — analyzeFile is expected to populate every defined module before analyzeModule runs")
  let analyzedFuncDef = ? defScope[module.name].module.findFunctionDef(function.def)
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
  # BUG: same KeyError risk as analyzeUserFunction — unguarded defScope
  # lookup. Fix together with the analyzeUserFunction site by introducing a
  # guarded helper.
  assert(module.name in defScope,
    fmt"{module.loc} BUG: defScope is missing `{module.name.asl}` — analyzeFile is expected to populate every defined module before analyzeModule runs")
  let analyzedModuleDef = defScope[module.name].module
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
