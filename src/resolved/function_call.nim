import sequtils, strutils, strformat, options, hashes

import "../blocks"
import argument

type ExternalFunction* = ref object of RootObj
  module*: Option[Module]
  function*: Function

proc new_external_function*(module: Option[Module],
    function: Function): ExternalFunction =
  ExternalFunction(module: module, function: function)

proc hash*(ext_fn: ExternalFunction): Hash =
  if ext_fn.module.is_some:
    hash(ext_fn.module.get.name) !& hash(ext_fn.function)
  else:
    hash(ext_fn.function)

proc `==`*(ext_fn: ExternalFunction, other: ExternalFunction): bool =
  hash(ext_fn) == hash(other)

proc `$`*(ext_fn: ExternalFunction): string =
  fmt"{ext_fn.module}.{ext_fn.function.name}"

type
  ResolvedFunctionCallKind* = enum
    RFCK_BUILTIN, RFCK_USER
  ResolvedFunctionCall* = ref object of RootObj
    args: seq[ResolvedArgument]
    module: Option[Module]
    builtin_module: Option[BuiltinModule]
    case kind: ResolvedFunctionCallKind
    of RFCK_BUILTIN:
      function_def: FunctionDefinition
    of RFCK_USER:
      function: Function

proc new_resolved_function_call*(function_def: FunctionDefinition, args: seq[
    ResolvedArgument]): ResolvedFunctionCall =
  ResolvedFunctionCall(kind: RFCK_BUILTIN, function_def: function_def, args: args)

proc new_resolved_function_call*(builtin_module: BuiltinModule,
    function_def: FunctionDefinition, args: seq[
    ResolvedArgument]): ResolvedFunctionCall =
  ResolvedFunctionCall(kind: RFCK_BUILTIN, builtin_module: some(builtin_module),
      function_def: function_def, args: args)

proc new_resolved_function_call*(function: Function, args: seq[
    ResolvedArgument]): ResolvedFunctionCall =
  ResolvedFunctionCall(kind: RFCK_USER, function: function, args: args)

proc new_resolved_function_call*(module: Module, function: Function, args: seq[
    ResolvedArgument]): ResolvedFunctionCall =
  ResolvedFunctionCall(kind: RFCK_USER, module: some(module),
      function: function, args: args)

proc user_function*(resolved_function_call: ResolvedFunctionCall): Option[
    ExternalFunction] =
  case resolved_function_call.kind:
  of RFCK_BUILTIN: none(ExternalFunction)
  of RFCK_USER: some(new_external_function(resolved_function_call.module,
      resolved_function_call.function))

proc return_type*(resolved_function_call: ResolvedFunctionCall): Token =
  case resolved_function_call.kind:
  of RFCK_BUILTIN:
    resolved_function_call.function_def.return_type
  of RFCK_USER:
    resolved_function_call.function.definition.return_type

proc c*(fncall: ResolvedFunctionCall): string =
  let args_str = fncall.args.map_it($(it.value)).join(", ")
  case fncall.kind:
  of RFCK_BUILTIN:
    let prefix = if fncall.builtin_module.is_some: fmt"{fncall.builtin_module.get.name}_" else: ""
    fmt"{prefix}{fncall.function_def.name}({args_str})"
  of RFCK_USER:
    let prefix = if fncall.module.is_some: fmt"{fncall.module.get.name}_" else: ""
    fmt"{prefix}{fncall.function.name}({args_str})"
