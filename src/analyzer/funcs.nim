## User and tagged-union Function analysis, plus AnalyzedModule
## (the per-module driver that walks every function body).

import results, strformat, tables, options

import tokenizer
import parser
import resolver
import argtypes
import funcdefs
import modules
import funcrefs
import body

type AnalyzedUserFunction* = ref object
  resolved: ResolvedUserFunction
  def: AnalyzedFunctionDefinition
  statements: seq[AnalyzedStatement]

proc newAnalyzedUserFunction*(resolved: ResolvedUserFunction, def: AnalyzedFunctionDefinition, statements: seq[AnalyzedStatement]): AnalyzedUserFunction =
  AnalyzedUserFunction(resolved: resolved, def: def, statements: statements)

proc resolved*(function: AnalyzedUserFunction): ResolvedUserFunction = function.resolved
proc def*(function: AnalyzedUserFunction): AnalyzedFunctionDefinition = function.def
proc statements*(function: AnalyzedUserFunction): seq[AnalyzedStatement] = function.statements

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

type AnalyzedExternFunction* = ref object
  resolved: ResolvedExternFunction
  def: AnalyzedFunctionDefinition

proc newAnalyzedExternFunction*(resolved: ResolvedExternFunction, def: AnalyzedFunctionDefinition): AnalyzedExternFunction =
  AnalyzedExternFunction(resolved: resolved, def: def)

proc resolved*(function: AnalyzedExternFunction): ResolvedExternFunction = function.resolved
proc def*(function: AnalyzedExternFunction): AnalyzedFunctionDefinition = function.def

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
  def: AnalyzedModuleDefinition
  functions: seq[AnalyzedFunction]

proc newAnalyzedModule*(def: AnalyzedModuleDefinition, functions: seq[AnalyzedFunction]): AnalyzedModule =
  AnalyzedModule(def: def, functions: functions)

proc def*(m: AnalyzedModule): AnalyzedModuleDefinition = m.def
proc resolved*(m: AnalyzedModule): ResolvedModule = m.def.resolved
proc loc*(m: AnalyzedModule): Location = m.def.resolved.loc
proc name*(m: AnalyzedModule): Identifier = m.def.name
proc functions*(m: AnalyzedModule): seq[AnalyzedFunction] = m.functions

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
