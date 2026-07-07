## User and tagged-union Function analysis, plus AnalyzedModule
## (the per-module driver that walks every function body).

import results, strformat, tables, options

import parser
import resolver
import argtypes
import funcrefs
import body

type AnalyzedUserFunction* = ref object
  resolved: ResolvedUserFunction
  def: ResolvedFunctionDefinition
  statements: seq[AnalyzedStatement]

proc newAnalyzedUserFunction*(resolved: ResolvedUserFunction, def: ResolvedFunctionDefinition, statements: seq[AnalyzedStatement]): AnalyzedUserFunction =
  AnalyzedUserFunction(resolved: resolved, def: def, statements: statements)

proc resolved*(function: AnalyzedUserFunction): ResolvedUserFunction = function.resolved
proc def*(function: AnalyzedUserFunction): ResolvedFunctionDefinition = function.def
proc statements*(function: AnalyzedUserFunction): seq[AnalyzedStatement] = function.statements

proc analyzeUserFunction*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, function: ResolvedUserFunction): Result[AnalyzedUserFunction, string] =
  ## Seeds funcScope from the resolved arg definitions (converting each
  ## resolved argType to the analyzer-side AnalyzedArgumentType in the
  ## calling module context), then walks statements.
  var funcScope: AnalyzedFunctionScope
  for argDef in function.def.args:
    let analyzedArgType = ? analyzeArgumentType(app, file, fileScope, module, argDef.argType)
    funcScope[argDef.name] = analyzedArgType

  var analyzedStatements: seq[AnalyzedStatement]
  for statement in function.statements:
    let analyzedStatement = ? analyzeStatement(app, file, fileScope, module, funcScope, statement)
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
      let analyzedReturns = ? analyzeArgumentType(app, file, fileScope, module, function.def.returns)
      if analyzedStatements[^1].argType.get != analyzedReturns:
        err(fmt"{function.statements[^1].loc} function does not return the expected return type")
      else:
        ok(newAnalyzedUserFunction(function, function.def, analyzedStatements))

type AnalyzedExternFunction* = ref object
  resolved: ResolvedExternFunction
  def: ResolvedFunctionDefinition

proc newAnalyzedExternFunction*(resolved: ResolvedExternFunction, def: ResolvedFunctionDefinition): AnalyzedExternFunction =
  AnalyzedExternFunction(resolved: resolved, def: def)

proc resolved*(function: AnalyzedExternFunction): ResolvedExternFunction = function.resolved
proc def*(function: AnalyzedExternFunction): ResolvedFunctionDefinition = function.def

type
  AnalyzedFunctionKind* = enum
    afkUser, afkExtern
  AnalyzedFunction* = ref object
    case kind: AnalyzedFunctionKind
    of afkUser: user: AnalyzedUserFunction
    of afkExtern: extern: AnalyzedExternFunction

proc newAnalyzedFunction*(user: AnalyzedUserFunction): AnalyzedFunction =
  AnalyzedFunction(kind: afkUser, user: user)

proc newAnalyzedFunction*(extern: AnalyzedExternFunction): AnalyzedFunction =
  AnalyzedFunction(kind: afkExtern, extern: extern)

proc kind*(function: AnalyzedFunction): AnalyzedFunctionKind = function.kind
proc user*(function: AnalyzedFunction): AnalyzedUserFunction =
  assert function.kind == afkUser,
    fmt"AnalyzedFunction.user accessed but kind is {function.kind}"
  function.user
proc extern*(function: AnalyzedFunction): AnalyzedExternFunction =
  assert function.kind == afkExtern,
    fmt"AnalyzedFunction.extern accessed but kind is {function.kind}"
  function.extern

type AnalyzedModule* = ref object
  def: ResolvedModule
  functions: seq[AnalyzedFunction]

proc newAnalyzedModule*(def: ResolvedModule, functions: seq[AnalyzedFunction]): AnalyzedModule =
  AnalyzedModule(def: def, functions: functions)

proc def*(m: AnalyzedModule): ResolvedModule = m.def
proc resolved*(m: AnalyzedModule): ResolvedModule = m.def
proc loc*(m: AnalyzedModule): Location = m.def.loc
proc name*(m: AnalyzedModule): Identifier = m.def.name
proc functions*(m: AnalyzedModule): seq[AnalyzedFunction] = m.functions

proc analyzeModule*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule): Result[AnalyzedModule, string] =
  var analyzedFunctions: seq[AnalyzedFunction]
  for function in module.functions:
    case function.kind:
    of rfkExtern:
      analyzedFunctions.add(newAnalyzedFunction(newAnalyzedExternFunction(function.extern, function.def)))
    of rfkUser:
      let analyzedUserFunction = ? analyzeUserFunction(app, file, fileScope, module, function.user)
      analyzedFunctions.add(newAnalyzedFunction(analyzedUserFunction))
  ok(newAnalyzedModule(module, analyzedFunctions))
