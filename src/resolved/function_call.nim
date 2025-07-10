import sequtils, strutils, strformat, options, hashes

import "../blocks"
import expression

type ExternalFunction* = ref object of RootObj
  module*: Option[Module]
  function*: Function

proc new_external_function*(module: Module,
    function: Function): ExternalFunction =
  ExternalFunction(module: some(module), function: function)

proc new_external_function*(function: Function): ExternalFunction =
  ExternalFunction(module: none(Module), function: function)

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
    RFCK_BUILTIN, RFCK_MODULE, RFCK_LOCAL
  ResolvedFunctionCall* = ref object of RootObj
    args: seq[ResolvedExpression]
    case kind: ResolvedFunctionCallKind
    of RFCK_BUILTIN:
      builtin_module: Module
      function_def: FunctionDefinition
    of RFCK_LOCAL:
      local_function: Function
    of RFCK_MODULE:
      module: Module
      function: Function

proc new_resolved_function_call*(function: Function, args: seq[
    ResolvedExpression]): ResolvedFunctionCall =
  ResolvedFunctionCall(kind: RFCK_LOCAL, local_function: function, args: args)

proc new_resolved_function_call*(module: Module,
    function_def: FunctionDefinition, args: seq[
    ResolvedExpression]): ResolvedFunctionCall =
  ResolvedFunctionCall(kind: RFCK_BUILTIN, builtin_module: module,
      function_def: function_def, args: args)

proc new_resolved_function_call*(module: Module, function: Function, args: seq[
    ResolvedExpression]): ResolvedFunctionCall =
  ResolvedFunctionCall(kind: RFCK_MODULE, module: module, function: function, args: args)

proc user_function*(resolved_function_call: ResolvedFunctionCall): Option[
    ExternalFunction] =
  case resolved_function_call.kind:
  of RFCK_BUILTIN: none(ExternalFunction)
  of RFCK_LOCAL: some(new_external_function(resolved_function_call.function))
  of RFCK_MODULE: some(new_external_function(resolved_function_call.module,
      resolved_function_call.function))

proc return_type*(resolved_function_call: ResolvedFunctionCall): Token =
  case resolved_function_call.kind:
  of RFCK_BUILTIN:
    resolved_function_call.function_def.return_type
  of RFCK_LOCAL:
    resolved_function_call.local_function.definition.return_type
  of RFCK_MODULE:
    resolved_function_call.function.definition.return_type

proc c*(fncall: ResolvedFunctionCall): string =
  let args_str = fncall.args.map_it($(it.value)).join(", ")
  case fncall.kind:
  of RFCK_BUILTIN:
    fmt"{fncall.builtin_module.name}_{fncall.function_def.name}({args_str})"
  of RFCK_LOCAL:
    fmt"{fncall.function.name}({args_str})"
  of RFCK_MODULE:
    fmt"{fncall.module.name}_{fncall.function.name}({args_str})"
