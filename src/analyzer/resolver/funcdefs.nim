## Function-def cluster — ResolvedArgumentDef, ResolvedFunctionDef,
## ResolvedExternFunction and their resolve procs. Reads
## ResolvedArgumentType from argtypes.nim.

import results, strformat, strutils, hashes

import ./parser
import argtypes

type
  ResolvedArgumentDef* = ref object
    parsed: ArgumentDef
    argType: ResolvedArgumentType

  ResolvedFunctionDef* = ref object
    parsed: FunctionDef
    args: seq[ResolvedArgumentDef]
    returns: ResolvedArgumentType

  ResolvedExternFunction* = ref object
    parsed: ExternFunction
    def: ResolvedFunctionDef

# =====================================================================
# Function definitions
# (ResolvedArgumentDef, ResolvedFunctionDef,
#  ResolvedExternFunction)
# =====================================================================

# ---- ResolvedArgumentDef ----

proc newResolvedArgumentDef*(parsed: ArgumentDef,
    argType: ResolvedArgumentType): ResolvedArgumentDef =
  ResolvedArgumentDef(parsed: parsed, argType: argType)

proc parsed*(d: ResolvedArgumentDef): ArgumentDef = d.parsed
proc name*(d: ResolvedArgumentDef): Identifier = d.parsed.name
proc argType*(d: ResolvedArgumentDef): ResolvedArgumentType = d.argType
proc loc*(d: ResolvedArgumentDef): Location = d.argType.loc
proc hash*(d: ResolvedArgumentDef): Hash = d.argType.hash
proc `==`*(a, b: ResolvedArgumentDef): bool = a.hash == b.hash
proc asl*(argDef: ResolvedArgumentDef): string =
  fmt"{argDef.name.asl}: {argDef.argType.asl}"

proc concreteArgumentDef(argDef: ResolvedArgumentDef, concrete: ResolvedArgumentType, generic: Generic): ResolvedArgumentDef =
  let concreteArgType = argDef.argType.concreteArgumentType(concrete, generic)
  newResolvedArgumentDef(argDef.parsed, concreteArgType)

proc resolveArgumentDef*(app: App,     file: parser.File, fileScope: FileScope, module: Module,
    arg: ArgumentDef): Result[ResolvedArgumentDef, string] =
  let resolvedArgumentType = ? resolveArgumentType(app, file, fileScope, module,
    arg.argType)
  ? resolveDataType(file, module, arg.argType, resolvedArgumentType)
  ok(newResolvedArgumentDef(arg, resolvedArgumentType))

proc resolveArgumentDef*(app: App,     file: parser.File, fileScope: FileScope, generic: Generic,
    arg: ArgumentDef): Result[ResolvedArgumentDef, string] =
  let resolvedArgumentType = ? resolveArgumentType(app, file, fileScope, generic,
    arg.argType)
  ? resolveDataType(file, generic, arg.argType, resolvedArgumentType)
  ok(newResolvedArgumentDef(arg, resolvedArgumentType))

# ---- ResolvedFunctionDef ----

proc newResolvedFunctionDef*(parsed: FunctionDef,
    args: seq[ResolvedArgumentDef],
    returns: ResolvedArgumentType): ResolvedFunctionDef =
  ResolvedFunctionDef(parsed: parsed, args: args, returns: returns)

proc parsed*(funcDef: ResolvedFunctionDef): FunctionDef = funcDef.parsed
proc args*(funcDef: ResolvedFunctionDef): seq[ResolvedArgumentDef] = funcDef.args
proc returns*(funcDef: ResolvedFunctionDef): ResolvedArgumentType = funcDef.returns
proc public*(funcDef: ResolvedFunctionDef): bool = funcDef.parsed.public
proc name*(funcDef: ResolvedFunctionDef): Identifier = funcDef.parsed.name
proc arity*(funcDef: ResolvedFunctionDef): int = funcDef.parsed.arity
proc loc*(funcDef: ResolvedFunctionDef): Location = funcDef.parsed.loc

proc asl*(funcDef: ResolvedFunctionDef): string =
  var args: seq[string]
  for arg in funcDef.args:
    args.add(arg.asl)
  let argsJoined = args.join(", ")
  fmt"func {funcDef.name.asl}({argsJoined}): {funcDef.returns.asl}"

proc hash*(funcDef: ResolvedFunctionDef): Hash =
  var acc = funcDef.name.hash
  for arg in funcDef.args:
    acc = acc !& arg.hash
  return acc

proc `==`*(a, b: ResolvedFunctionDef): bool = a.hash == b.hash

proc concreteFunctionDef*(funcDef: ResolvedFunctionDef, moduleType: ResolvedArgumentType, generic: Generic): ResolvedFunctionDef =
  var concreteArgs: seq[ResolvedArgumentDef]
  for arg in funcDef.args:
    concreteArgs.add(arg.concreteArgumentDef(moduleType, generic))
  let concreteReturns = funcDef.returns.concreteArgumentType(moduleType, generic)
  newResolvedFunctionDef(funcDef.parsed, concreteArgs, concreteReturns)

proc resolveFunctionDef*(app: App,     file: parser.File, fileScope: FileScope, module: Module,
    def: FunctionDef): Result[ResolvedFunctionDef, string] =
  var resolvedArgs: seq[ResolvedArgumentDef]
  for arg in def.args:
    let resolvedArg = ? resolveArgumentDef(app, file, fileScope, module,
      arg)
    resolvedArgs.add(resolvedArg)

  let resolvedReturnArgType = ? resolveArgumentType(app, file, fileScope, module,
    def.returns)
  ? resolveDataType(file, module, def.returns, resolvedReturnArgType)

  ok(newResolvedFunctionDef(def, resolvedArgs,
    resolvedReturnArgType))

proc resolveFunctionDef*(app: App,     file: parser.File, fileScope: FileScope, generic: Generic,
    def: FunctionDef): Result[ResolvedFunctionDef, string] =
  var resolvedArgs: seq[ResolvedArgumentDef]
  for arg in def.args:
    let resolvedArg = ? resolveArgumentDef(app, file, fileScope, generic, arg)
    resolvedArgs.add(resolvedArg)

  let resolvedReturnArgType = ? resolveArgumentType(app, file, fileScope, generic,
    def.returns)
  ? resolveDataType(file, generic, def.returns, resolvedReturnArgType)

  ok(newResolvedFunctionDef(def, resolvedArgs,
    resolvedReturnArgType))

# ---- ResolvedExternFunction ----

proc newResolvedExternFunction*(parsed: ExternFunction,
    def: ResolvedFunctionDef): ResolvedExternFunction =
  ResolvedExternFunction(parsed: parsed, def: def)

proc parsed*(function: ResolvedExternFunction): ExternFunction = function.parsed
proc def*(function: ResolvedExternFunction): ResolvedFunctionDef = function.def
proc ffi*(function: ResolvedExternFunction): string = function.parsed.ffi
proc loc*(function: ResolvedExternFunction): Location = function.def.loc

proc resolveExternFunction*(app: App,     file: parser.File, fileScope: FileScope, module: Module,
    function: ExternFunction): Result[ResolvedExternFunction, string] =
  let resolvedFunctionDef = ? resolveFunctionDef(app, file, fileScope,
    module, function.def)
  ok(newResolvedExternFunction(function, resolvedFunctionDef))

