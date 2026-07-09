## Function cluster — ResolvedUserFunction wraps a ResolvedFunctionDef
## + statements; ResolvedFunction is the tagged union over user/extern.

import results, strformat, options, tables, sets

import ./parser
import argtypes
import funcdefs
import body

type
  ResolvedUserFunction* = ref object
    parsed: UserFunction
    funcDef: ResolvedFunctionDef
    statements: seq[ResolvedStatement]

  ResolvedFunctionKind* = enum
    rfkExtern, rfkUser
  ResolvedFunction* = ref object
    case kind: ResolvedFunctionKind
    of rfkExtern: extern: ResolvedExternFunction
    of rfkUser: user: ResolvedUserFunction

# =====================================================================
# Functions (UserFunction, tagged Function)
# =====================================================================

# ---- ResolvedUserFunction ----

proc newResolvedUserFunction*(parsed: UserFunction,
    funcDef: ResolvedFunctionDef,
    statements: seq[ResolvedStatement]): ResolvedUserFunction =
  ResolvedUserFunction(parsed: parsed, funcDef: funcDef, statements: statements)

proc parsed*(function: ResolvedUserFunction): UserFunction = function.parsed
proc def*(function: ResolvedUserFunction): ResolvedFunctionDef = function.funcDef
proc statements*(function: ResolvedUserFunction): seq[ResolvedStatement] = function.statements
proc loc*(function: ResolvedUserFunction): Location = function.parsed.loc

proc resolveUserFunction*(app: App,     file: parser.File, fileScope: FileScope, module: Module,
    function: UserFunction): Result[ResolvedUserFunction, string] =
  if function.decorators.len > 0:
    return err(fmt"{function.loc} todo: resolve decorators in user function")

  let resolvedFunctionDef = ? resolveFunctionDef(app, file, fileScope, module, function.def)

  var scope: FunctionScope
  for arg in resolvedFunctionDef.args:
    scope.incl(arg.name)

  var resolvedStatements: seq[ResolvedStatement]
  for statement in function.statements:
    let resolvedStatement = ? resolveStatement(app, file, fileScope, module,
      scope, statement)
    resolvedStatements.add(resolvedStatement)
    if resolvedStatement.variable.isSome:
      scope.incl(resolvedStatement.variable.get)

  ok(newResolvedUserFunction(function, resolvedFunctionDef, resolvedStatements))

# ---- ResolvedFunction (tagged union) ----

proc newResolvedFunction*(extern: ResolvedExternFunction): ResolvedFunction =
  ResolvedFunction(kind: rfkExtern, extern: extern)

proc newResolvedFunction*(user: ResolvedUserFunction): ResolvedFunction =
  ResolvedFunction(kind: rfkUser, user: user)

proc kind*(function: ResolvedFunction): ResolvedFunctionKind = function.kind
proc extern*(function: ResolvedFunction): ResolvedExternFunction =
  assert function.kind == rfkExtern,
    fmt"ResolvedFunction.extern accessed but kind is {function.kind}"
  function.extern
proc user*(function: ResolvedFunction): ResolvedUserFunction =
  assert function.kind == rfkUser,
    fmt"ResolvedFunction.user accessed but kind is {function.kind}"
  function.user

proc def*(function: ResolvedFunction): ResolvedFunctionDef =
  case function.kind:
  of rfkExtern: function.extern.def
  of rfkUser: function.user.def
proc loc*(function: ResolvedFunction): Location =
  case function.kind:
  of rfkExtern: function.extern.loc
  of rfkUser: function.user.loc

proc resolveFunction*(app: App,     file: parser.File, fileScope: FileScope, module: Module,
    function: Function): Result[ResolvedFunction, string] =
  case function.kind:
  of fkUser:
    let resolvedUserFunction = ? resolveUserFunction(app, file, fileScope,
      module, function.user)
    ok(newResolvedFunction(resolvedUserFunction))
  of fkExtern:
    let resolvedExternFunction = ? resolveExternFunction(app, file, fileScope,
      module, function.extern)
    ok(newResolvedFunction(resolvedExternFunction))

