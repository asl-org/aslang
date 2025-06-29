import strutils, sequtils, strformat

import token

type FunctionCall* = ref object of RootObj
  name*: Token
  arg_list*: seq[Token]

proc location*(function_call: FunctionCall): Location =
  function_call.name.location

proc `$`*(function_call: FunctionCall): string =
  let arg_list_str = function_call.arg_list.map_it($(it)).join(", ")
  fmt"{function_call.name}({arg_list_str})"

proc new_function_call*(name: Token, arg_list: seq[Token]): FunctionCall =
  FunctionCall(name: name, arg_list: arg_list)

proc new_function_call*(name: string, arg_list: seq[string]): FunctionCall =
  let name_token = new_id_token(name)
  let token_arg_list = arg_list.map(new_id_token)
  new_function_call(name_token, token_arg_list)
