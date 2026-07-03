## User and tagged-union Function resolution.
##
## The `Resolved*` types, their constructors, and direct-field
## accessors live in `types.nim`. This file owns the computed
## helpers and the resolve procs.

import options, sets, strformat, results

import tokenizer
import parser
import types
import argtypes
import funcdefs
import body

# ---- ResolvedUserFunction helpers ----

proc loc*(function: ResolvedUserFunction): Location = function.parsed.loc

proc resolveUserFunction*(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope, module: Module,
    function: UserFunction): Result[ResolvedUserFunction, string] =
  if function.decorators.len > 0:
    return err(fmt"{function.loc} todo: resolve decorators in user function")

  let resolvedFunctionDefinition = ? resolveFunctionDefinition(app, shells, file, fileScope, module, function.def)

  var scope: FunctionScope
  for arg in resolvedFunctionDefinition.args:
    scope.incl(arg.name)

  var resolvedStatements: seq[ResolvedStatement]
  for statement in function.statements:
    let resolvedStatement = ? resolveStatement(app, shells, file, fileScope, module,
      scope, statement)
    resolvedStatements.add(resolvedStatement)
    if resolvedStatement.variable.isSome:
      scope.incl(resolvedStatement.variable.get)

  ok(newResolvedUserFunction(function, resolvedFunctionDefinition, resolvedStatements))

# ---- ResolvedFunction helpers ----

proc def*(function: ResolvedFunction): ResolvedFunctionDefinition =
  case function.kind:
  of rfkExtern: function.extern.def
  of rfkUser: function.user.def
proc loc*(function: ResolvedFunction): Location =
  case function.kind:
  of rfkExtern: function.extern.loc
  of rfkUser: function.user.loc

proc resolveFunction*(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope, module: Module,
    function: Function): Result[ResolvedFunction, string] =
  case function.kind:
  of fkUser:
    let resolvedUserFunction = ? resolveUserFunction(app, shells, file, fileScope,
      module, function.user)
    ok(newResolvedFunction(resolvedUserFunction))
  of fkExtern:
    let resolvedExternFunction = ? resolveExternFunction(app, shells, file, fileScope,
      module, function.extern)
    ok(newResolvedFunction(resolvedExternFunction))
