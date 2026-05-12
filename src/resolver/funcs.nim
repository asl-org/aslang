## User and tagged-union Function resolution.

import options, sets, strformat, results

import parser
import argtypes
import funcdefs
import funcrefs
import body

# ResolvedUserFunction
type ResolvedUserFunction* = ref object
  funcDef: ResolvedFunctionDefinition
  statements: seq[ResolvedStatement]

proc newResolvedUserFunction*(funcDef: ResolvedFunctionDefinition,
    statements: seq[ResolvedStatement]): ResolvedUserFunction =
  ResolvedUserFunction(funcDef: funcDef, statements: statements)

proc resolveUserFunction*(app: App, file: parser.File, fileScope: FileScope,
    module: Module,
    function: UserFunction): Result[ResolvedUserFunction, string] =
  if function.decorators.len > 0:
    return err(fmt"{function.loc} todo: resolve decorators in user function")

  let resolvedFunctionDefinition = ? resolveFunctionDefinition(app, file,
    fileScope, module, function.def)

  var scope: FunctionScope
  for arg in resolvedFunctionDefinition.args:
    scope.incl(arg.name)

  var resolvedStatements: seq[ResolvedStatement]
  for statement in function.statements:
    let resolvedStatement = ? resolveStatement(app, file, fileScope, module,
      scope, statement)
    resolvedStatements.add(resolvedStatement)
    if resolvedStatement.variable.isSome:
      scope.incl(resolvedStatement.variable.get)

  ok(newResolvedUserFunction(resolvedFunctionDefinition, resolvedStatements))

# ResolvedFunction
type
  ResolvedFunctionKind* = enum
    rfkExtern, rfkUser
  ResolvedFunction* = ref object
    case kind: ResolvedFunctionKind
    of rfkExtern: extern: ResolvedExternFunction
    of rfkUser: user: ResolvedUserFunction

proc newResolvedFunction*(extern: ResolvedExternFunction): ResolvedFunction =
  ResolvedFunction(kind: rfkExtern, extern: extern)

proc newResolvedFunction*(user: ResolvedUserFunction): ResolvedFunction =
  ResolvedFunction(kind: rfkUser, user: user)

proc kind*(function: ResolvedFunction): ResolvedFunctionKind = function.kind
proc extern*(function: ResolvedFunction): ResolvedExternFunction = function.extern
proc user*(function: ResolvedFunction): ResolvedUserFunction = function.user

proc resolveFunction*(app: App, file: parser.File, fileScope: FileScope,
    module: Module, function: Function): Result[ResolvedFunction, string] =
  case function.kind:
  of fkUser:
    let resolvedUserFunction = ? resolveUserFunction(app, file, fileScope,
      module, function.user)
    ok(newResolvedFunction(resolvedUserFunction))
  of fkExtern:
    let resolvedExternFunction = ? resolveExternFunction(app, file, fileScope,
      module, function.extern)
    ok(newResolvedFunction(resolvedExternFunction))
