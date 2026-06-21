## Function-definition shape: a single argument definition, a full
## function signature (definition), and the extern-function form.
## Each layers on top of argtypes via resolveArgumentType +
## resolveDataType.

import results, options, hashes, strformat, strutils

import tokenizer
import parser
import argtypes

# ResolvedArgumentDefinition
type ResolvedArgumentDefinition* = ref object
  parsed: ArgumentDefinition
  argType: ResolvedArgumentType

proc newResolvedArgumentDefinition*(parsed: ArgumentDefinition,
    argType: ResolvedArgumentType): ResolvedArgumentDefinition =
  ResolvedArgumentDefinition(parsed: parsed, argType: argType)

proc parsed*(d: ResolvedArgumentDefinition): ArgumentDefinition = d.parsed
proc name*(d: ResolvedArgumentDefinition): Identifier = d.parsed.name
proc loc*(d: ResolvedArgumentDefinition): Location = d.argType.loc
proc argType*(d: ResolvedArgumentDefinition): ResolvedArgumentType = d.argType
proc hash*(d: ResolvedArgumentDefinition): Hash = d.argType.hash
proc `==`*(a, b: ResolvedArgumentDefinition): bool = a.hash == b.hash
proc asl*(argDef: ResolvedArgumentDefinition): string =
  fmt"{argDef.name.asl}: {argDef.argType.asl}"

proc genericRequirement*(d: ResolvedArgumentDefinition): Option[ResolvedGenericArgumentType] =
  case d.argType.kind:
  of ratkImported: assert(false, "todo: support imported types for requier list")
  of ratkDefined:
    case d.argType.definedType.kind:
    of rdatkModule: discard
    of rdatkGeneric: result = some(d.argType.definedType.generic)

proc concreteArgumentDefinition(argDef: ResolvedArgumentDefinition, concrete: ResolvedArgumentType, generic: Generic): ResolvedArgumentDefinition =
  let concreteArgType = argDef.argType.concreteArgumentType(concrete, generic)
  newResolvedArgumentDefinition(argDef.parsed, concreteArgType)

proc resolveArgumentDefinition*(app: App, file: parser.File,
    fileScope: FileScope, module: Module,
    arg: ArgumentDefinition): Result[ResolvedArgumentDefinition, string] =
  let resolvedArgumentType = ? resolveArgumentType(app, file, fileScope, module,
    arg.argType)
  ? resolveDataType(file, module, arg.argType, resolvedArgumentType)
  ok(newResolvedArgumentDefinition(arg, resolvedArgumentType))

proc resolveArgumentDefinition*(app: App, file: parser.File, fileScope: FileScope, generic: Generic,
    arg: ArgumentDefinition): Result[ResolvedArgumentDefinition, string] =
  let resolvedArgumentType = ? resolveArgumentType(app, file, fileScope, generic,
    arg.argType)
  ? resolveDataType(file, generic, arg.argType, resolvedArgumentType)
  ok(newResolvedArgumentDefinition(arg, resolvedArgumentType))

# ResolvedFunctionDefinition
type ResolvedFunctionDefinition* = ref object
  parsed: FunctionDefinition
  args: seq[ResolvedArgumentDefinition]
  returns: ResolvedArgumentType

proc newResolvedFunctionDefinition*(parsed: FunctionDefinition, args: seq[ResolvedArgumentDefinition], returns: ResolvedArgumentType): ResolvedFunctionDefinition =
  ResolvedFunctionDefinition(parsed: parsed, args: args, returns: returns)

proc public*(funcDef: ResolvedFunctionDefinition): bool = funcDef.parsed.public
proc name*(funcDef: ResolvedFunctionDefinition): Identifier = funcDef.parsed.name
proc arity*(funcDef: ResolvedFunctionDefinition): int = funcDef.parsed.arity
proc args*(funcDef: ResolvedFunctionDefinition): seq[ResolvedArgumentDefinition] = funcDef.args
proc returns*(funcDef: ResolvedFunctionDefinition): ResolvedArgumentType = funcDef.returns
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

proc resolveFunctionDefinition*(app: App, file: parser.File, fileScope: FileScope, module: Module, def: FunctionDefinition): Result[ResolvedFunctionDefinition, string] =
  var resolvedArgs: seq[ResolvedArgumentDefinition]
  for arg in def.args:
    let resolvedArg = ? resolveArgumentDefinition(app, file, fileScope, module,
      arg)
    resolvedArgs.add(resolvedArg)

  let resolvedReturnArgType = ? resolveArgumentType(app, file, fileScope, module,
    def.returns)
  ? resolveDataType(file, module, def.returns, resolvedReturnArgType)

  ok(newResolvedFunctionDefinition(def, resolvedArgs,
    resolvedReturnArgType))

proc resolveFunctionDefinition*(app: App, file: parser.File, fileScope: FileScope, generic: Generic,
    def: FunctionDefinition): Result[ResolvedFunctionDefinition, string] =
  var resolvedArgs: seq[ResolvedArgumentDefinition]
  for arg in def.args:
    let resolvedArg = ? resolveArgumentDefinition(app, file, fileScope, generic, arg)
    resolvedArgs.add(resolvedArg)

  let resolvedReturnArgType = ? resolveArgumentType(app, file, fileScope, generic,
    def.returns)
  ? resolveDataType(file, generic, def.returns, resolvedReturnArgType)

  ok(newResolvedFunctionDefinition(def, resolvedArgs,
    resolvedReturnArgType))

# ResolvedExternFunction
type ResolvedExternFunction* = ref object
  parsed: ExternFunction
  def: ResolvedFunctionDefinition

proc newResolvedExternFunction*(parsed: ExternFunction,
    def: ResolvedFunctionDefinition): ResolvedExternFunction =
  ResolvedExternFunction(parsed: parsed, def: def)

proc parsed*(function: ResolvedExternFunction): ExternFunction = function.parsed
proc ffi*(function: ResolvedExternFunction): string = function.parsed.ffi
proc def*(function: ResolvedExternFunction): ResolvedFunctionDefinition = function.def
proc loc*(function: ResolvedExternFunction): Location = function.def.loc

proc resolveExternFunction*(app: App, file: parser.File, fileScope: FileScope,
    module: Module,
    function: ExternFunction): Result[ResolvedExternFunction, string] =
  let resolvedFunctionDef = ? resolveFunctionDefinition(app, file, fileScope,
    module, function.def)
  ok(newResolvedExternFunction(function, resolvedFunctionDef))
