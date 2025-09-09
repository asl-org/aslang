import strutils, sequtils, strformat

import token, arg_def

type
  FunctionRefKind* = enum
    FRK_LOCAL, FRK_MODULE
  FunctionRef* = ref object of RootObj
    name*: Token
    case kind*: FunctionRefKind
    of FRK_LOCAL: discard
    of FRK_MODULE: module*: ArgumentType

proc new_function_ref*(name: Token): FunctionRef =
  FunctionRef(kind: FRK_LOCAL, name: name)

proc new_function_ref*(module: ArgumentType, name: Token): FunctionRef =
  FunctionRef(kind: FRK_MODULE, module: module, name: name)

proc location*(func_ref: FunctionRef): Location =
  case func_ref.kind:
  of FRK_LOCAL: func_ref.name.location
  of FRK_MODULE: func_ref.module.location

proc `$`*(func_ref: FunctionRef): string =
  case func_ref.kind:
  of FRK_LOCAL: $(func_ref.name)
  of FRK_MODULE: fmt"{func_ref.module}.{func_ref.name}"

type
  FunctionCall* = ref object of RootObj
    func_ref*: FunctionRef
    arg_list*: seq[Token]

proc new_function_call*(func_ref: FunctionRef, arg_list: seq[
    Token]): FunctionCall =
  FunctionCall(func_ref: func_ref, arg_list: arg_list)

proc location*(function_call: FunctionCall): Location =
  function_call.func_ref.location

proc name*(function_call: FunctionCall): Token =
  function_call.func_ref.name

proc module*(function_call: FunctionCall): ArgumentType =
  function_call.func_ref.module

proc `$`*(function_call: FunctionCall): string =
  let arg_list_str = function_call.arg_list.map_it($(it)).join(", ")
  fmt"{function_call.func_ref}({arg_list_str})"
