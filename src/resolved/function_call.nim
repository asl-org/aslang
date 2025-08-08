import sequtils, strutils, strformat, options

import "../blocks"
import arg
import function_ref

type
  ResolvedFunctionCallKind* = enum
    RFCK_BUILTIN, RFCK_MODULE, RFCK_LOCAL, RFCK_GENERIC
  ResolvedFunctionCall* = ref object of RootObj
    args: seq[ResolvedArgument]
    function_def: FunctionDefinition
    case kind: ResolvedFunctionCallKind
    of RFCK_LOCAL: discard
    of RFCK_GENERIC:
      generic: Token
      concrete: Token
    of RFCK_BUILTIN: builtin_module: BuiltinModule
    of RFCK_MODULE: module: UserModule

proc new_resolved_function_call*(function_def: FunctionDefinition, args: seq[
        ResolvedArgument]): ResolvedFunctionCall =
  ResolvedFunctionCall(kind: RFCK_LOCAL,
      function_def: function_def, args: args)

proc new_resolved_function_call*(module: BuiltinModule,
    function_def: FunctionDefinition, args: seq[
        ResolvedArgument]): ResolvedFunctionCall =
  ResolvedFunctionCall(kind: RFCK_BUILTIN,
      builtin_module: module, function_def: function_def, args: args)

proc new_resolved_function_call*(module: UserModule, function_def: FunctionDefinition, args: seq[
        ResolvedArgument]): ResolvedFunctionCall =
  ResolvedFunctionCall(kind: RFCK_MODULE,
      module: module, function_def: function_def, args: args)

proc new_resolved_function_call*(generic: Token, concrete: Token, function_def: FunctionDefinition, args: seq[
        ResolvedArgument]): ResolvedFunctionCall =
  ResolvedFunctionCall(kind: RFCK_GENERIC, generic: generic, concrete: concrete,
      function_def: function_def, args: args)

proc user_function*(resolved_function_call: ResolvedFunctionCall): Option[
    ResolvedFunctionRef] =
  case resolved_function_call.kind:
  of RFCK_BUILTIN: none(ResolvedFunctionRef)
  of RFCK_GENERIC: none(ResolvedFunctionRef)
  of RFCK_LOCAL: some(new_resolved_function_ref(
      resolved_function_call.function_def))
  of RFCK_MODULE: some(new_resolved_function_ref(resolved_function_call.module,
      resolved_function_call.function_def))

proc return_type*(resolved_function_call: ResolvedFunctionCall): Token =
  resolved_function_call.function_def.return_type

proc c*(fncall: ResolvedFunctionCall): string =
  let args_str = fncall.args.map_it($(it.value)).join(", ")
  case fncall.kind:
  of RFCK_BUILTIN:
    fmt"{fncall.builtin_module.name}_{fncall.function_def.name}({args_str})"
  of RFCK_GENERIC:
    fmt"{fncall.concrete}_{fncall.generic}_{fncall.function_def.name}({args_str})"
  of RFCK_LOCAL:
    fmt"{fncall.function_def.name}({args_str})"
  of RFCK_MODULE:
    fmt"{fncall.module.name}_{fncall.function_def.name}({args_str})"
