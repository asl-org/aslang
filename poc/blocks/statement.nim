import strformat

import token, function_call

type Statement* = ref object of RootObj
  destination*: Token
  function_call*: FunctionCall

proc location*(statement: Statement): Location =
  statement.destination.location

proc `$`*(statement: Statement): string =
  fmt"{statement.destination} = {statement.function_call}"

proc new_statement*(destination: Token, function_call: FunctionCall): Statement =
  Statement(destination: destination, function_call: function_call)

proc new_statement*(destination: string,
    function_call: FunctionCall): Statement =
  let dest_token = new_id_token(destination)
  new_statement(dest_token, function_call)
