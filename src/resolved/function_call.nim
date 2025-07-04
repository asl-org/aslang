import sequtils, strutils, strformat, options

import "../blocks"
import argument

type
  ResolvedFunctionCallKind* = enum
    RFCK_BUILTIN, RFCK_USER
  ResolvedFunctionCall* = ref object of RootObj
    args: seq[ResolvedArgument]
    module: Option[Module]
    case kind: ResolvedFunctionCallKind
    of RFCK_BUILTIN:
      function_def: FunctionDefinition
    of RFCK_USER:
      function: Function

proc new_resolved_function_call*(function_def: FunctionDefinition, args: seq[
    ResolvedArgument]): ResolvedFunctionCall =
  ResolvedFunctionCall(kind: RFCK_BUILTIN, function_def: function_def, args: args)

proc new_resolved_function_call*(function: Function, args: seq[
    ResolvedArgument]): ResolvedFunctionCall =
  ResolvedFunctionCall(kind: RFCK_USER, function: function, args: args)

proc new_resolved_function_call*(module: Module, function: Function, args: seq[
    ResolvedArgument]): ResolvedFunctionCall =
  ResolvedFunctionCall(kind: RFCK_USER, module: some(module),
      function: function, args: args)

proc user_function*(resolved_function_call: ResolvedFunctionCall): Option[Function] =
  case resolved_function_call.kind:
  of RFCK_BUILTIN: none(Function)
  of RFCK_USER: some(resolved_function_call.function)

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
    fmt"{fncall.function_def.name}({args_str})"
  of RFCK_USER:
    fmt"{fncall.function.name}({args_str})"
