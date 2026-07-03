## Function-definition shape: a single argument definition, a full
## function signature (definition), and the extern-function form.
##
## The `Resolved*` types, their constructors, and direct-field
## accessors live in `types.nim`. This file owns the computed
## helpers (`hash`, `asl`, `arity`, `loc`, `public`, ...) and the
## resolveX procs.

import results, options, hashes, strformat, strutils

import tokenizer
import parser
import types
import argtypes

# ---- ResolvedArgumentDefinition helpers ----

proc loc*(d: ResolvedArgumentDefinition): Location = d.argType.loc
proc hash*(d: ResolvedArgumentDefinition): Hash = d.argType.hash
proc `==`*(a, b: ResolvedArgumentDefinition): bool = a.hash == b.hash
proc asl*(argDef: ResolvedArgumentDefinition): string =
  fmt"{argDef.name.asl}: {argDef.argType.asl}"

proc genericRequirement*(d: ResolvedArgumentDefinition): Option[ResolvedGenericArgumentType] =
  case d.argType.kind:
  of ratkModule: discard
  of ratkGeneric: result = some(d.argType.generic)

proc concreteArgumentDefinition(argDef: ResolvedArgumentDefinition, concrete: ResolvedArgumentType, generic: Generic): ResolvedArgumentDefinition =
  let concreteArgType = argDef.argType.concreteArgumentType(concrete, generic)
  newResolvedArgumentDefinition(argDef.parsed, concreteArgType)

proc resolveArgumentDefinition*(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope, module: Module,
    arg: ArgumentDefinition): Result[ResolvedArgumentDefinition, string] =
  let resolvedArgumentType = ? resolveArgumentType(app, shells, file, fileScope, module,
    arg.argType)
  ? resolveDataType(file, module, arg.argType, resolvedArgumentType)
  ok(newResolvedArgumentDefinition(arg, resolvedArgumentType))

proc resolveArgumentDefinition*(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope, generic: Generic,
    arg: ArgumentDefinition): Result[ResolvedArgumentDefinition, string] =
  let resolvedArgumentType = ? resolveArgumentType(app, shells, file, fileScope, generic,
    arg.argType)
  ? resolveDataType(file, generic, arg.argType, resolvedArgumentType)
  ok(newResolvedArgumentDefinition(arg, resolvedArgumentType))

# ---- ResolvedFunctionDefinition helpers ----

proc public*(funcDef: ResolvedFunctionDefinition): bool = funcDef.parsed.public
proc name*(funcDef: ResolvedFunctionDefinition): Identifier = funcDef.parsed.name
proc arity*(funcDef: ResolvedFunctionDefinition): int = funcDef.parsed.arity
proc loc*(funcDef: ResolvedFunctionDefinition): Location = funcDef.parsed.loc

proc asl*(funcDef: ResolvedFunctionDefinition): string =
  var args: seq[string]
  for arg in funcDef.args:
    args.add(arg.asl)
  let argsJoined = args.join(", ")
  fmt"func {funcDef.name.asl}({argsJoined}): {funcDef.returns.asl}"

proc hash*(funcDef: ResolvedFunctionDefinition): Hash =
  var acc = funcDef.name.hash
  for arg in funcDef.args:
    acc = acc !& arg.hash
  return acc

proc `==`*(a, b: ResolvedFunctionDefinition): bool = a.hash == b.hash

proc concreteFunctionDefinition*(funcDef: ResolvedFunctionDefinition, moduleType: ResolvedArgumentType, generic: Generic): ResolvedFunctionDefinition =
  var concreteArgs: seq[ResolvedArgumentDefinition]
  for arg in funcDef.args:
    concreteArgs.add(arg.concreteArgumentDefinition(moduleType, generic))
  let concreteReturns = funcDef.returns.concreteArgumentType(moduleType, generic)
  newResolvedFunctionDefinition(funcDef.parsed, concreteArgs, concreteReturns)

proc resolveFunctionDefinition*(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope, module: Module,
    def: FunctionDefinition): Result[ResolvedFunctionDefinition, string] =
  var resolvedArgs: seq[ResolvedArgumentDefinition]
  for arg in def.args:
    let resolvedArg = ? resolveArgumentDefinition(app, shells, file, fileScope, module,
      arg)
    resolvedArgs.add(resolvedArg)

  let resolvedReturnArgType = ? resolveArgumentType(app, shells, file, fileScope, module,
    def.returns)
  ? resolveDataType(file, module, def.returns, resolvedReturnArgType)

  ok(newResolvedFunctionDefinition(def, resolvedArgs,
    resolvedReturnArgType))

proc resolveFunctionDefinition*(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope, generic: Generic,
    def: FunctionDefinition): Result[ResolvedFunctionDefinition, string] =
  var resolvedArgs: seq[ResolvedArgumentDefinition]
  for arg in def.args:
    let resolvedArg = ? resolveArgumentDefinition(app, shells, file, fileScope, generic, arg)
    resolvedArgs.add(resolvedArg)

  let resolvedReturnArgType = ? resolveArgumentType(app, shells, file, fileScope, generic,
    def.returns)
  ? resolveDataType(file, generic, def.returns, resolvedReturnArgType)

  ok(newResolvedFunctionDefinition(def, resolvedArgs,
    resolvedReturnArgType))

# ---- ResolvedExternFunction helpers ----

proc ffi*(function: ResolvedExternFunction): string = function.parsed.ffi
proc loc*(function: ResolvedExternFunction): Location = function.def.loc

proc resolveExternFunction*(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope, module: Module,
    function: ExternFunction): Result[ResolvedExternFunction, string] =
  let resolvedFunctionDef = ? resolveFunctionDefinition(app, shells, file, fileScope,
    module, function.def)
  ok(newResolvedExternFunction(function, resolvedFunctionDef))
