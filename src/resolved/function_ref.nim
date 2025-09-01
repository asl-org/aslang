import strformat, hashes
import "../blocks"

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
  case func_ref.kind:
  of RFRK_FUNCTION:
    fmt"{func_ref.function_def.name}"
  of RFRK_MODULE:
    fmt"{func_ref.module_name}.{func_ref.function_def.name}"
