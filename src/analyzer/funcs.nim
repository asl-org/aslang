import results, tables, strformat, sequtils, options, strutils, sets

import tokenizer
import parser
import resolver
import argtypes
import data
import funcdefs
import modules

type AnalyzedModuleScope* = Table[Identifier, AnalyzedModuleDefinition]

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

proc analyzeVariantCasePattern*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedModuleScope, funcScope: AnalyzedFunctionScope, variantPattern: VariantPattern, union: AnalyzedUnion): Result[AnalyzedVariantPattern, string] =
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

proc analyzeCasePattern*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedModuleScope, funcScope: AnalyzedFunctionScope, pattern: ResolvedCasePattern, union: AnalyzedUnion): Result[AnalyzedCasePattern, string] =
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

proc analyzeFunctionRef*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedModuleScope, fnref: ResolvedFunctionRef): Result[AnalyzedFunctionRef, string] =
  let argType = ? analyzeArgumentType(app, file, fileScope, module, fnref.argType)
  case argType.kind:
  of aatkImported: err(fmt"{fnref.loc} todo: analyze imported type function ref")
  of aatkDefined:
    let definedType = argType.definedType
    case definedType.kind:
    of adatkGeneric: err(fmt"{fnref.loc} todo: analyze generic type function ref")
    of adatkModule:
      let moduleType = definedType.module
      if moduleType.module.name notin defScope:
        err(fmt"{fnref.loc} [UNREACHABLE] module `{moduleType.module.name.asl}` does not exist in scope")
      else:
        let moduleDef = defScope[moduleType.module.name]
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

  AnalyzedCaseBlock = ref object
    resolved: ResolvedCaseBlock
    pattern: AnalyzedCasePattern
    statements: seq[AnalyzedStatement]

  AnalyzedMatchExpression = ref object
    resolved: ResolvedMatchExpression
    subject: AnalyzedExpression
    cases: seq[AnalyzedCaseBlock]

  AnalyzedExpressionKind = enum
    aekVariable, aekFunctionCall, aekLiteral, aekMatchExpr
  AnalyzedExpression = ref object
    case kind: AnalyzedExpressionKind
    of aekVariable: variable: AnalyzedVariable
    of aekFunctionCall: fncall: AnalyzedFunctionCall
    of aekLiteral: literal: Literal
    of aekMatchExpr: match: AnalyzedMatchExpression

  AnalyzedStatementKind = enum
    askExpr
  AnalyzedStatement = ref object
    case kind: AnalyzedStatementKind
    of askExpr: expression: AnalyzedExpression

# TODO: accepts returns field once function call resolution is complete
proc newAnalyzedFunctionCall(resolved: ResolvedFunctionCall, fnref: AnalyzedFunctionRef, args: seq[AnalyzedExpression], returns: AnalyzedArgumentType): AnalyzedFunctionCall =
  AnalyzedFunctionCall(resolved: resolved, fnref: fnref, args: args, returns: returns)

proc loc(fncall: AnalyzedFunctionCall): Location = fncall.resolved.loc

proc newAnalyzedCaseBlock(resolved: ResolvedCaseBlock, pattern: AnalyzedCasePattern, statements: seq[AnalyzedStatement]): AnalyzedCaseBlock =
  AnalyzedCaseBlock(resolved: resolved, pattern: pattern, statements: statements)

proc newAnalyzedMatchExpression(resolved: ResolvedMatchExpression, subject: AnalyzedExpression, cases: seq[AnalyzedCaseBlock]): AnalyzedMatchExpression =
  AnalyzedMatchExpression(resolved: resolved, subject: subject, cases: cases)

proc newAnalyzedExpression(variable: AnalyzedVariable): AnalyzedExpression =
  AnalyzedExpression(kind: aekVariable, variable: variable)

proc newAnalyzedExpression(fncall: AnalyzedFunctionCall): AnalyzedExpression =
  AnalyzedExpression(kind: aekFunctionCall, fncall: fncall)

proc newAnalyzedExpression(literal: Literal): AnalyzedExpression =
  AnalyzedExpression(kind: aekLiteral, literal: literal)

proc newAnalyzedExpression(match: AnalyzedMatchExpression): AnalyzedExpression =
  AnalyzedExpression(kind: aekMatchExpr, match: match)

proc loc(expression: AnalyzedExpression): Location =
  case expression.kind:
  of aekFunctionCall: return expression.fncall.loc
  of aekVariable: return expression.variable.loc
  of aekLiteral: return expression.literal.loc
  of aekMatchExpr: assert(false, fmt"todo: implement location for match expression")

proc argType(expression: AnalyzedExpression): Option[AnalyzedArgumentType] =
  case expression.kind:
  of aekFunctionCall: return some(expression.fncall.returns)
  of aekVariable: return some(expression.variable.argType)
  of aekLiteral: return none(AnalyzedArgumentType)
  of aekMatchExpr: assert(false, fmt"todo: implement return type for match expression")

proc newAnalyzedStatement(expression: AnalyzedExpression): AnalyzedStatement =
  AnalyzedStatement(kind: askExpr, expression: expression)

proc analyzeExpression*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedModuleScope, funcScope: AnalyzedFunctionScope, expression: ResolvedExpression): Result[AnalyzedExpression, string]

proc analyzeStatement*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedModuleScope, funcScope: AnalyzedFunctionScope, statement: ResolvedStatement): Result[AnalyzedStatement, string]

proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedModuleScope, defType: AnalyzedArgumentType, valType: AnalyzedArgumentType): Result[void, string]

proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedModuleScope, defType: AnalyzedModuleArgumentType, valType: AnalyzedModuleArgumentType): Result[void, string] =
  if defType.module != valType.module:
    err(fmt"{valType.loc} expected `{defType.name.asl}` but found `{valType.name.asl}`")
  else:
    for (defImpl, valImpl) in zip(defType.impls, valType.impls):
      ? analyzeValueTypeAgainstDefinitionType(app, file, fileScope, module, defScope, defImpl, valImpl)
    ok()

proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedModuleScope, defType: AnalyzedModuleArgumentType, valType: AnalyzedDefinedArgumentType): Result[void, string] =
  case valType.kind:
  of adatkModule:
    ? analyzeValueTypeAgainstDefinitionType(app, file, fileScope, module, defScope, defType, valType.module)
    ok()
  of adatkGeneric:
    err(fmt"{valType.loc} todo: analyze generic value type against module argument type")

proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedModuleScope, defType: AnalyzedModuleArgumentType, valType: AnalyzedArgumentType): Result[void, string] =
  case valType.kind:
  of aatkImported:
    err(fmt"{valType.loc} todo: analyze imported value type against module argument type")
  of aatkDefined:
    ? analyzeValueTypeAgainstDefinitionType(app, file, fileScope, module, defScope, defType, valType.definedType)
    ok()

proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedModuleScope, defType: AnalyzedDefinedArgumentType, valType: AnalyzedArgumentType): Result[void, string] =
  case defType.kind:
  of adatkModule:
    ? analyzeValueTypeAgainstDefinitionType(app, file, fileScope, module, defScope, defType.module, valType)
    ok()
  of adatkGeneric:
    err(fmt"{valType.loc} todo: analyze value type against generic argument type")

proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedModuleScope, defType: AnalyzedArgumentType, valType: AnalyzedArgumentType): Result[void, string] =
  case defType.kind:
  of aatkImported:
    err(fmt"{valType.loc} todo: analyze value type against imported argument type")
  of aatkDefined:
    ? analyzeValueTypeAgainstDefinitionType(app, file, fileScope, module, defScope, defType.definedType, valType)
    ok()

proc analyzeArgumentList*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedModuleScope, funcScope: AnalyzedFunctionScope, argValues: seq[AnalyzedExpression], funcDef: AnalyzedFunctionDefinition): Result[void, string] =
  for (argDef, argValue) in zip(funcDef.args, argValues):
    if argValue.argType.isNone:
      return err(fmt"{argValue.loc} todo: analyze function call literal argument")
    else:
      ? analyzeValueTypeAgainstDefinitionType(app, file, fileScope, module, defScope, argDef.argType, argValue.argType.get)
  ok()

proc analyzeFunctionCall*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedModuleScope, funcScope: AnalyzedFunctionScope, fncall: ResolvedFunctionCall): Result[AnalyzedFunctionCall, string] =
  let funcRef = ? analyzeFunctionRef(app, file, fileScope, module, defScope, fncall.funcRef)
  var analyzedArgs: seq[AnalyzedExpression]
  for arg in fncall.args:
    let analyzedArg = ? analyzeExpression(app, file, fileScope, module, defScope, funcScope, arg)
    analyzedArgs.add(analyzedArg)

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

proc validateSubjectExpr*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedModuleScope, funcScope: AnalyzedFunctionScope, subject: AnalyzedExpression): Result[AnalyzedData, string] =
  if subject.argType.isNone:
    err(fmt"{subject.loc} todo: analyze case blocks for literal expression")
  else:
    let subjectType = subject.argType.get
    case subjectType.kind:
    of aatkImported:
      err(fmt"{subject.loc} todo: analyze case blocks for imported subject type")
    of aatkDefined:
      let subjectDefinedType = subjectType.definedType
      case subjectDefinedType.kind:
      of adatkGeneric:
        err(fmt"{subject.loc} todo: analyze case blocks for generic subject type")
      of adatkModule:
        let subjectModuleType = subjectDefinedType.module
        if subjectModuleType.name notin defScope:
          err(fmt"{subject.loc} UNREACHABLE: module `{subjectModuleType.name.asl}` is not defined")
        else:
          let subjectModule = defScope[subjectModuleType.name]
          if subjectModule.data.isNone:
            err(fmt"{subject.loc} UNREACHABLE: subject expression does not return a data type")
          else:
            ok(subjectModule.data.get)

proc analyzeCaseBlock*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedModuleScope, funcScope: AnalyzedFunctionScope, caseBlock: ResolvedCaseBlock, union: AnalyzedUnion): Result[AnalyzedCaseBlock, string] =
  let analyzedCasePattern = ? analyzeCasePattern(app, file, fileScope, module, defScope, funcScope, caseBlock.pattern, union)
  var caseScope = funcScope.clone()
  for binding in analyzedCasePattern.bindings:
    caseScope[binding.name] = binding.argType
  var analyzedStatements: seq[AnalyzedStatement]
  for statement in caseBlock.statements:
    let analyzedStatement = ? analyzeStatement(app, file, fileScope, module, defScope, caseScope, statement)
    analyzedStatements.add(analyzedStatement)
  ok(newAnalyzedCaseBlock(caseBlock, analyzedCasePattern, analyzedStatements))

proc analyzeCases*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedModuleScope, funcScope: AnalyzedFunctionScope, cases: seq[ResolvedCaseBlock], union: AnalyzedUnion): Result[seq[AnalyzedCaseBlock], string] =
  var patternScope = newAnalyzedVariantPatternScope(cases.len)
  for id, caseBlock in cases:
    patternScope = ? patternScope.update(id, caseBlock.pattern)

  ? hasUncoveredCases(patternScope, union.variants.len)

  var analyzedCaseBlocks: seq[AnalyzedCaseBlock]
  for caseBlock in cases:
    let analyzedCaseBlock = ? analyzeCaseBlock(app, file, fileScope, module, defScope, funcScope, caseBlock, union)
    analyzedCaseBlocks.add(analyzedCaseBlock)
  ok(analyzedCaseBlocks)

proc analyzeMatchExpression*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedModuleScope, funcScope: AnalyzedFunctionScope, match: ResolvedMatchExpression): Result[AnalyzedMatchExpression, string] =
  let analyzedSubjectExpr = ? analyzeExpression(app, file, fileScope, module, defScope, funcScope, match.subject)
  let analyzedSubjectDataType = ? validateSubjectExpr(app, file, fileScope, module, defScope, funcScope, analyzedSubjectExpr)
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
      let analyzedCases = ? analyzeCases(app, file, fileScope, module, defScope, funcScope, match.cases, analyzedSubjectDataType.union)
      ok(newAnalyzedMatchExpression(match, analyzedSubjectExpr, analyzedCases))

proc analyzeExpression*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedModuleScope, funcScope: AnalyzedFunctionScope, expression: ResolvedExpression): Result[AnalyzedExpression, string] =
  case expression.kind:
  of rekInitializer: err(fmt"{expression.loc} todo: analyze initializer")
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

proc analyzeStatement*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedModuleScope, funcScope: AnalyzedFunctionScope, statement: ResolvedStatement): Result[AnalyzedStatement, string] =
  case statement.kind:
  of rskExpr:
    let analyzedExpr = ? analyzeExpression(app, file, fileScope, module, defScope, funcScope, statement.expression)
    ok(newAnalyzedStatement(analyzedExpr))
  of rskAssignment: err(fmt"{statement.loc} todo: analyze assignment")
  of rskMutation: err(fmt"{statement.loc} todo: analyze mutation")

proc analyzeFunction*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedModuleScope, function: ResolvedUserFunction): Result[void, string] =
  var funcScope: AnalyzedFunctionScope
  let analyzedFuncDef = ? defScope[module.name].findFunctionDef(function.def)
  for argDef in analyzedFuncDef.args:
    funcScope[argDef.name] = argDef.argType

  var analyzedStatements: seq[AnalyzedStatement]
  for statement in function.statements:
    let analyzedStatement = ? analyzeStatement(app, file, fileScope, module, defScope, funcScope, statement)
    analyzedStatements.add(analyzedStatement)
  err(fmt"{function.loc} todo: analyze function")

proc analyzeModule*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedModuleScope): Result[void, string] =
  for function in module.functions:
    case function.kind:
    of rfkExtern:
      discard # extern functions are definition only
    of rfkUser:
      ? analyzeFunction(app, file, fileScope, module, defScope, function.user)
  # err(fmt"{module.loc} todo: analyze module")
  ok()