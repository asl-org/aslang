import sequtils, strutils, strformat, options, hashes

import "../blocks"
import arg

type
  ResolvedFunctionRefKind* = enum
    RFRK_MODULE, RFRK_FUNCTION
  ResolvedFunctionRef* = ref object of RootObj
    function_def*: FunctionDefinition
    case kind*: ResolvedFunctionRefKind
    of RFRK_MODULE: module_name*: Token
    of RFRK_FUNCTION: discard

proc new_resolved_function_ref*(module: UserModule,
    function_def: FunctionDefinition): ResolvedFunctionRef =
  ResolvedFunctionRef(kind: RFRK_MODULE, module_name: module.name,
      function_def: function_def)

proc new_resolved_function_ref*(function_def: FunctionDefinition): ResolvedFunctionRef =
  ResolvedFunctionRef(kind: RFRK_FUNCTION, function_def: function_def)

proc name*(func_ref: ResolvedFunctionRef): string =
  case func_ref.kind:
  of RFRK_MODULE: fmt"{func_ref.module_name}_{func_ref.function_def.name}"
  of RFRK_FUNCTION: fmt"{func_ref.function_def.name}"

proc hash*(func_ref: ResolvedFunctionRef): Hash =
  case func_ref.kind:
  of RFRK_FUNCTION: hash(func_ref.function_def)
  of RFRK_MODULE: hash(func_ref.module_name) !& hash(func_ref.function_def)

proc `==`*(func_ref: ResolvedFunctionRef, other: ResolvedFunctionRef): bool =
  hash(func_ref) == hash(other)

proc `$`*(func_ref: ResolvedFunctionRef): string =
  fmt"{func_ref.module_name}.{func_ref.function_def.name}"

type
  ResolvedFunctionCallKind* = enum
    RFCK_BUILTIN, RFCK_MODULE, RFCK_LOCAL
  ResolvedFunctionCall* = ref object of RootObj
    args: seq[ResolvedArgument]
    function_def: FunctionDefinition
    case kind: ResolvedFunctionCallKind
    of RFCK_LOCAL: discard
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

proc new_resolved_user_function_call*(module: UserModule, function_def: FunctionDefinition, args: seq[
        ResolvedArgument]): ResolvedFunctionCall =
  ResolvedFunctionCall(kind: RFCK_MODULE,
      module: module, function_def: function_def, args: args)

proc user_function*(resolved_function_call: ResolvedFunctionCall): Option[
    ResolvedFunctionRef] =
  case resolved_function_call.kind:
  of RFCK_BUILTIN: none(ResolvedFunctionRef)
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
  of RFCK_LOCAL:
    fmt"{fncall.function_def.name}({args_str})"
  of RFCK_MODULE:
    fmt"{fncall.module.name}_{fncall.function_def.name}({args_str})"
