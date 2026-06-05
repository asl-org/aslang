import results, tables, strformat, sequtils, options, strutils

import tokenizer
import parser
import resolver
import argtypes
import data
import funcdefs
import modules

type AnalyzedModuleScope* = Table[Identifier, AnalyzedModuleDefinition]
type AnalyzedFunctionScope = Table[Identifier, AnalyzedArgumentType]

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

  AnalyzedExpressionKind = enum
    aekVariable, aekFunctionCall, aekLiteral, aekMatchExpr
  AnalyzedExpression = ref object
    case kind: AnalyzedExpressionKind
    of aekVariable: variable: AnalyzedVariable
    of aekFunctionCall: fncall: AnalyzedFunctionCall
    of aekLiteral: literal: Literal
    of aekMatchExpr: discard

  AnalyzedStatementKind = enum
    askExpr
  AnalyzedStatement = ref object
    case kind: AnalyzedStatementKind
    of askExpr: expression: AnalyzedExpression

# TODO: accepts returns field once function call resolution is complete
proc newAnalyzedFunctionCall(resolved: ResolvedFunctionCall, fnref: AnalyzedFunctionRef, args: seq[AnalyzedExpression], returns: AnalyzedArgumentType): AnalyzedFunctionCall =
  AnalyzedFunctionCall(resolved: resolved, fnref: fnref, args: args, returns: returns)

proc loc(fncall: AnalyzedFunctionCall): Location = fncall.resolved.loc

proc newAnalyzedExpression(variable: AnalyzedVariable): AnalyzedExpression =
  AnalyzedExpression(kind: aekVariable, variable: variable)

proc newAnalyzedExpression(fncall: AnalyzedFunctionCall): AnalyzedExpression =
  AnalyzedExpression(kind: aekFunctionCall, fncall: fncall)

proc newAnalyzedExpression(literal: Literal): AnalyzedExpression =
  AnalyzedExpression(kind: aekLiteral, literal: literal)

proc newAnalyzedExpression(): AnalyzedExpression =
  AnalyzedExpression(kind: aekMatchExpr)

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

proc analyzeSubjectExpression*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedModuleScope, funcScope: AnalyzedFunctionScope, subject: AnalyzedExpression): Result[AnalyzedData, string] =
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


proc analyzeCaseBlock*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedModuleScope, funcScope: AnalyzedFunctionScope, caseBlock: ResolvedCaseBlock, union: AnalyzedUnion): Result[void, string] =
  err(fmt"{caseBlock.loc} todo: analyze case blocks for union module")

proc analyzeCases*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedModuleScope, funcScope: AnalyzedFunctionScope, cases: seq[ResolvedCaseBlock], union: AnalyzedUnion): Result[void, string] =
  for caseBlock in cases:
    ? analyzeCaseBlock(app, file, fileScope, module, defScope, funcScope, caseBlock, union)
  ok()

proc analyzeMatchExpression*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedModuleScope, funcScope: AnalyzedFunctionScope, match: ResolvedMatchExpression): Result[void, string] =
  let analyzedSubjectExpr = ? analyzeExpression(app, file, fileScope, module, defScope, funcScope, match.subject)
  let analyzedSubjectDataType = ? analyzeSubjectExpression(app, file, fileScope, module, defScope, funcScope, analyzedSubjectExpr)
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
      ? analyzeCases(app, file, fileScope, module, defScope, funcScope, match.cases, analyzedSubjectDataType.union)
      ok()

  # for caseBlock in match.cases:
  #   ? analyzeCaseBlock(app, file, fileScope, module, defScope, funcScope, caseBlock, analyzedSubjectExpr.argType)

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
    ? analyzeMatchExpression(app, file, fileScope, module, defScope, funcScope, expression.match)
    ok(newAnalyzedExpression())

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