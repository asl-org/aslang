import strformat

import token, function_call

type StructGetter* = ref object of RootObj
  struct*: Token
  field*: Token

proc location*(struct_getter: StructGetter): Location =
  struct_getter.struct.location

proc `$`*(struct_getter: StructGetter): string =
  fmt"{struct_getter.struct}.{struct_getter.field}"

proc new_struct_getter*(struct: Token, field: Token): StructGetter =
  StructGetter(struct: struct, field: field)

type
  StatementKind* = enum
    SK_FUNCTION_CALL, SK_STRUCT_GETTER
  Statement* = ref object of RootObj
    destination*: Token
    case kind*: StatementKind
    of SK_FUNCTION_CALL:
      function_call*: FunctionCall
    of SK_STRUCT_GETTER:
      struct_getter*: StructGetter

proc location*(statement: Statement): Location =
  statement.destination.location

proc `$`*(statement: Statement): string =
  fmt"{statement.destination} = {statement.function_call}"

proc new_statement*(destination: Token, function_call: FunctionCall): Statement =
  Statement(kind: SK_FUNCTION_CALL, destination: destination,
      function_call: function_call)

proc new_statement*(destination: Token, struct_getter: StructGetter): Statement =
  Statement(kind: SK_STRUCT_GETTER, destination: destination,
      struct_getter: struct_getter)

proc new_statement*(destination: string,
    function_call: FunctionCall): Statement =
  let dest_token = new_id_token(destination)
  new_statement(dest_token, function_call)
