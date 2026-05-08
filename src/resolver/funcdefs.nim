## Function-definition shape: a single argument definition, a full
## function signature (definition), and the extern-function form.
## Each layers on top of argtypes via resolveArgumentType +
## resolveDataType.

import results

import parser
import argtypes

# ResolvedArgumentDefinition
type ResolvedArgumentDefinition* = ref object
  argType: ResolvedArgumentType
  name: Identifier

proc newResolvedArgumentDefinition*(argType: ResolvedArgumentType,
    name: Identifier): ResolvedArgumentDefinition =
  ResolvedArgumentDefinition(name: name, argType: argType)

proc name*(d: ResolvedArgumentDefinition): Identifier = d.name

proc resolveArgumentDefinition*(app: App, file: parser.File,
    fileScope: FileScope, module: Module,
    arg: ArgumentDefinition): Result[ResolvedArgumentDefinition, string] =
  let resolvedArgumentType = ? resolveArgumentType(app, file, fileScope, module,
    arg.argType)
  ? resolveDataType(file, module, arg.argType, resolvedArgumentType)
  ok(newResolvedArgumentDefinition(resolvedArgumentType, arg.name))

proc resolveArgumentDefinition*(app: App, file: parser.File, generic: Generic,
    arg: ArgumentDefinition): Result[ResolvedArgumentDefinition, string] =
  let resolvedArgumentType = ? resolveArgumentType(app, file, generic,
    arg.argType)
  ? resolveDataType(file, generic, arg.argType, resolvedArgumentType)
  ok(newResolvedArgumentDefinition(resolvedArgumentType, arg.name))

# ResolvedFunctionDefinition
type ResolvedFunctionDefinition* = ref object
  public: bool
  name: Identifier
  args: seq[ResolvedArgumentDefinition]
  returns: ResolvedArgumentType

proc newResolvedFunctionDefinition*(public: bool, name: Identifier,
    args: seq[ResolvedArgumentDefinition],
    returns: ResolvedArgumentType): ResolvedFunctionDefinition =
  ResolvedFunctionDefinition(public: public, name: name, args: args,
    returns: returns)

proc args*(d: ResolvedFunctionDefinition): seq[ResolvedArgumentDefinition] =
  d.args

proc resolveFunctionDefinition*(app: App, file: parser.File,
    fileScope: FileScope, module: Module,
    def: FunctionDefinition): Result[ResolvedFunctionDefinition, string] =
  var resolvedArgs: seq[ResolvedArgumentDefinition]
  for arg in def.args:
    let resolvedArg = ? resolveArgumentDefinition(app, file, fileScope, module,
      arg)
    resolvedArgs.add(resolvedArg)

  let resolvedReturnArgType = ? resolveArgumentType(app, file, fileScope, module,
    def.returns)
  ? resolveDataType(file, module, def.returns, resolvedReturnArgType)

  ok(newResolvedFunctionDefinition(def.public, def.name, resolvedArgs,
    resolvedReturnArgType))

proc resolveFunctionDefinition*(app: App, file: parser.File, generic: Generic,
    def: FunctionDefinition): Result[ResolvedFunctionDefinition, string] =
  var resolvedArgs: seq[ResolvedArgumentDefinition]
  for arg in def.args:
    let resolvedArg = ? resolveArgumentDefinition(app, file, generic, arg)
    resolvedArgs.add(resolvedArg)

  let resolvedReturnArgType = ? resolveArgumentType(app, file, generic,
    def.returns)
  ? resolveDataType(file, generic, def.returns, resolvedReturnArgType)

  ok(newResolvedFunctionDefinition(def.public, def.name, resolvedArgs,
    resolvedReturnArgType))

# ResolvedExternFunction
type ResolvedExternFunction* = ref object
  ffi: string
  def: ResolvedFunctionDefinition

proc newResolvedExternFunction*(ffi: string,
    def: ResolvedFunctionDefinition): ResolvedExternFunction =
  ResolvedExternFunction(ffi: ffi, def: def)

proc resolveExternFunction*(app: App, file: parser.File, fileScope: FileScope,
    module: Module,
    function: ExternFunction): Result[ResolvedExternFunction, string] =
  let resolvedFunctionDef = ? resolveFunctionDefinition(app, file, fileScope,
    module, function.def)
  ok(newResolvedExternFunction(function.ffi, resolvedFunctionDef))
