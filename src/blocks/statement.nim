import strformat, sequtils, strutils

import token, function_call

type StructInit* = ref object of RootObj
  struct*: Token
  fields*: seq[(Token, Token)]

proc location*(struct_init: StructInit): Location =
  struct_init.struct.location

proc `$`*(struct_init: StructInit): string =
  let fields = struct_init.fields.map_it(fmt"{it[0]}: {it[1]}").join(", ")
  $(struct_init.struct) & "{ " & fields & " }"

proc new_struct_init*(struct: Token, fields: seq[(Token, Token)]): StructInit =
  StructInit(struct: struct, fields: fields)

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
    SK_FUNCTION_CALL, SK_STRUCT_INIT, SK_STRUCT_GETTER
  Statement* = ref object of RootObj
    destination*: Token
    case kind*: StatementKind
    of SK_FUNCTION_CALL:
      function_call*: FunctionCall
    of SK_STRUCT_INIT:
      struct_init*: StructInit
    of SK_STRUCT_GETTER:
      struct_getter*: StructGetter

proc location*(statement: Statement): Location =
  statement.destination.location

proc `$`*(statement: Statement): string =
  case statement.kind:
  of SK_FUNCTION_CALL:
    fmt"{statement.destination} = {statement.function_call}"
  of SK_STRUCT_GETTER:
    fmt"{statement.destination} = {statement.struct_getter}"
  of SK_STRUCT_INIT:
    fmt"{statement.destination} = {statement.struct_init}"

proc new_statement*(destination: Token, function_call: FunctionCall): Statement =
  Statement(kind: SK_FUNCTION_CALL, destination: destination,
      function_call: function_call)

proc new_statement*(destination: Token, struct_init: StructInit): Statement =
  Statement(kind: SK_STRUCT_INIT, destination: destination,
      struct_init: struct_init)

proc new_statement*(destination: Token, struct_getter: StructGetter): Statement =
  Statement(kind: SK_STRUCT_GETTER, destination: destination,
      struct_getter: struct_getter)

proc new_statement*(destination: string,
    function_call: FunctionCall): Statement =
  let dest_token = new_id_token(destination)
  new_statement(dest_token, function_call)
