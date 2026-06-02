## User function + tagged-union Function analysis.
##
## Currently empty — function-body analysis is the next milestone.
## The commented-out scaffolding below was carried over from the
## monolithic analyzer.nim so the user-function / statement /
## expression / function-ref structure stays preserved while it's
## being iterated on.

# type AnalyzedExternFunction = ref object
#   funcDef: AnalyzedFunctionDefinition
#   ffi: string

# proc newAnalyzedExternFunction(funcDef: AnalyzedFunctionDefinition, ffi: string): AnalyzedExternFunction =
#   AnalyzedExternFunction(funcDef: funcDef, ffi: ffi)

# proc analyzeExternFunction*(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, function: ResolvedExternFunction): Result[AnalyzedExternFunction, string] =
#   let analyzedFuncDef = ? analyzeFunctionDefinition(app, file, module, function.def)
#   ok(newAnalyzedExternFunction(analyzedFuncDef, function.ffi))

# proc analyzeModuleTypeRef(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, moduleTypeRef: ResolvedModuleTypeRef): Result[void, string] =
#   let resolvedModule = ? file.findModule(moduleTypeRef.module.name)
#   err(fmt"{moduleTypeRef.loc} todo: analyze module ref")

# proc analyzeDefinedTypeRef(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, definedTypeRef: ResolvedDefinedTypeRef): Result[void, string] =
#   case definedTypeRef.kind:
#   of rdtrkGeneric:
#     err(fmt"{definedTypeRef.loc} todo: analyze defined generic ref")
#   of rdtrkModule:
#     analyzeModuleTypeRef(app, file, module, definedTypeRef.module)

# proc analyzeFunctionRef(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, funcRef: ResolvedFunctionRef): Result[void, string] =
#   case funcRef.kind:
#   of rfrkDefined: analyzeDefinedTypeRef(app, file, module, funcRef.definedType)

# proc analyzeExpression(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, scope: Table[Identifier, AnalyzedArgumentDefinition], expression: ResolvedExpression): Result[void, string]

# proc analyzeFunctionCall(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, scope: Table[Identifier, AnalyzedArgumentDefinition], fncall: ResolvedFunctionCall): Result[void, string] =
#   ? analyzeFunctionRef(app, file, module, fncall.funcRef)
#   for arg in fncall.args:
#     ? analyzeExpression(app, file, module, scope, arg)
#   err(fmt"{fncall.loc} todo: analyze function call")

# proc analyzeExpression(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, scope: Table[Identifier, AnalyzedArgumentDefinition], expression: ResolvedExpression): Result[void, string] =
#   case expression.kind:
#   of rekGetter: err(fmt"{expression.loc} todo: analyze getter")
#   of rekInitializer: err(fmt"{expression.loc} todo: analyze initializer")
#   of rekVariable: err(fmt"{expression.loc} todo: analyze variable")
#   of rekLiteral: err(fmt"{expression.loc} todo: analyze literal")
#   of rekMatchExpr: err(fmt"{expression.loc} todo: analyze match block")
#   of rekFunctionCall: analyzeFunctionCall(app, file, module, scope, expression.fncall)

# proc analyzeStatement(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, scope: Table[Identifier, AnalyzedArgumentDefinition], statement: ResolvedStatement): Result[void, string] =
#   case statement.kind:
#   of rskAssignment: err(fmt"{statement.loc} todo: analyze assignment")
#   of rskMutation: err(fmt"{statement.loc} todo: analyze mutation")
#   of rskExpr: analyzeExpression(app, file, module, scope, statement.expression)

# proc analyzeUserFunction(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, function: ResolvedUserFunction): Result[void, string] =
#   var scope: Table[Identifier, AnalyzedArgumentDefinition]
#   for arg in analyzedFuncDef.args:
#     assert(arg.name notin scope, "UNREACHABLE: function definition can not have same param name in different positions")
#     scope[arg.name] = arg
#   for statement in function.statements:
#     ? analyzeStatement(app, file, module, scope, statement)
#   ok()

# type
#   AnalyzedFunctionKind = enum
#     afkExtern, afkUser
#   AnalyzedFunction = ref object
#     case kind: AnalyzedFunctionKind
#     of afkExtern: extern: AnalyzedExternFunction
#     of afkUser:

# proc newAnalyzedFunction(extern: AnalyzedExternFunction): AnalyzedFunction =
#   AnalyzedFunction(kind: afkExtern, extern: extern)

# proc analyzeFunction*(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, function: ResolvedFunction): Result[AnalyzedFunction, string] =
#   case function.kind:
#   of rfkExtern:
#     let analyzedExternFn = ? analyzeExternFunction(app, file, module, function.extern)
#     ok(newAnalyzedFunction(analyzedExternFn))
#   of rfkUser:
#     let analyzedFuncDef = ? analyzeFunctionDefinition(app, file, module, function.def)
#     ok()

import results, tables, strformat

import parser
import resolver
import argtypes
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

proc analyzeVariable(scope: AnalyzedFunctionScope, variable: Identifier): Result[AnalyzedVariable, string] =
  if variable in scope: ok(newAnalyzedVariable(variable, scope[variable]))
  else: err(fmt"{variable.loc} variable `{variable.asl}` does not exist in scope")

type
  AnalyzedFunctionCall = ref object
    fnref: AnalyzedFunctionRef
    args: seq[AnalyzedExpression]

  AnalyzedExpressionKind = enum
    aekVariable, aekFunctionCall, aekLiteral
  AnalyzedExpression = ref object
    case kind: AnalyzedExpressionKind
    of aekVariable: variable: AnalyzedVariable
    of aekFunctionCall: fncall: AnalyzedFunctionCall
    of aekLiteral: literal: Literal

  AnalyzedStatementKind = enum
    askExpr
  AnalyzedStatement = ref object
    case kind: AnalyzedStatementKind
    of askExpr: expression: AnalyzedExpression

proc newAnalyzedFunctionCall(fnref: AnalyzedFunctionRef, args: seq[AnalyzedExpression]): AnalyzedFunctionCall =
  AnalyzedFunctionCall(fnref: fnref, args: args)

proc newAnalyzedExpression(variable: AnalyzedVariable): AnalyzedExpression =
  AnalyzedExpression(kind: aekVariable, variable: variable)

proc newAnalyzedExpression(fncall: AnalyzedFunctionCall): AnalyzedExpression =
  AnalyzedExpression(kind: aekFunctionCall, fncall: fncall)

proc newAnalyzedExpression(literal: Literal): AnalyzedExpression =
  AnalyzedExpression(kind: aekLiteral, literal: literal)

proc newAnalyzedStatement(expression: AnalyzedExpression): AnalyzedStatement =
  AnalyzedStatement(kind: askExpr, expression: expression)

proc analyzeExpression*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedModuleScope, funcScope: AnalyzedFunctionScope, expression: ResolvedExpression): Result[AnalyzedExpression, string]

proc analyzeArgumentList*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedModuleScope, funcScope: AnalyzedFunctionScope, args: seq[AnalyzedExpression], funcDef: AnalyzedFunctionDefinition): Result[void, string] =
  err(fmt"{funcDef.loc} todo: analyze function call argument list")

proc analyzeFunctionCall*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedModuleScope, funcScope: AnalyzedFunctionScope, fncall: ResolvedFunctionCall): Result[AnalyzedFunctionCall, string] =
  let funcRef = ? analyzeFunctionRef(app, file, fileScope, module, defScope, fncall.funcRef)
  var analyzedArgs: seq[AnalyzedExpression]
  for arg in fncall.args:
    let analyzedArg = ? analyzeExpression(app, file, fileScope, module, defScope, funcScope, arg)
    analyzedArgs.add(analyzedArg)

  for funcDef in funcRef.funcDefs:
    ? analyzeArgumentList(app, file, fileScope, module, defScope, funcScope, analyzedArgs, funcDef)

  ok(newAnalyzedFunctionCall(funcRef, analyzedArgs))

proc analyzeExpression*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedModuleScope, funcScope: AnalyzedFunctionScope, expression: ResolvedExpression): Result[AnalyzedExpression, string] =
  case expression.kind:
  of rekFunctionCall:
    let analyzedFunctionCall = ? analyzeFunctionCall(app, file, fileScope, module, defScope, funcScope, expression.fncall)
    ok(newAnalyzedExpression(analyzedFunctionCall))
  of rekInitializer: err(fmt"{expression.loc} todo: analyze initializer")
  of rekMatchExpr: err(fmt"{expression.loc} todo: analyze match expression")
  of rekGetter: err(fmt"{expression.loc} todo: analyze getter")
  of rekLiteral:
    ok(newAnalyzedExpression(expression.literal))
  of rekVariable:
    let analyzedVariable = ? analyzeVariable(funcScope, expression.variable)
    ok(newAnalyzedExpression(analyzedVariable))

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