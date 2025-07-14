import strformat, sequtils, strutils

import token, function_call

type StructInit* = ref object of RootObj
  struct*: Token
  fields*: seq[(Token, Token)]

proc new_struct_init*(struct: Token, fields: seq[(Token, Token)]): StructInit =
  StructInit(struct: struct, fields: fields)

proc location*(struct_init: StructInit): Location =
  struct_init.struct.location

proc `$`*(struct_init: StructInit): string =
  let fields = struct_init.fields.map_it(fmt"{it[0]}: {it[1]}").join(", ")
  $(struct_init.struct) & "{ " & fields & " }"

type StructGetter* = ref object of RootObj
  struct*: Token
  field*: Token

proc new_struct_getter*(struct: Token, field: Token): StructGetter =
  StructGetter(struct: struct, field: field)

proc location*(struct_getter: StructGetter): Location =
  struct_getter.struct.location

proc `$`*(struct_getter: StructGetter): string =
  fmt"{struct_getter.struct}.{struct_getter.field}"

type
  ExpressionKind* = enum
    EK_FUNCTION_CALL, EK_STRUCT_INIT, EK_STRUCT_GETTER
  Expression* = ref object of RootObj
    case kind*: ExpressionKind
    of EK_FUNCTION_CALL: function_call*: FunctionCall
    of EK_STRUCT_INIT: struct_init*: StructInit
    of EK_STRUCT_GETTER: struct_getter*: StructGetter

proc new_expression*(function_call: FunctionCall): Expression =
  Expression(kind: EK_FUNCTION_CALL, function_call: function_call)

proc new_expression*(struct_init: StructInit): Expression =
  Expression(kind: EK_STRUCT_INIT, struct_init: struct_init)

proc new_expression*(struct_getter: StructGetter): Expression =
  Expression(kind: EK_STRUCT_GETTER, struct_getter: struct_getter)

proc location*(expression: Expression): Location =
  case expression.kind:
  of EK_FUNCTION_CALL: expression.function_call.location
  of EK_STRUCT_INIT: expression.struct_init.location
  of EK_STRUCT_GETTER: expression.struct_getter.location

proc `$`*(expression: Expression): string =
  case expression.kind:
  of EK_FUNCTION_CALL: $(expression.function_call)
  of EK_STRUCT_GETTER: $(expression.struct_getter)
  of EK_STRUCT_INIT: $(expression.struct_init)

type
  Statement* = ref object of RootObj
    destination*: Token
    expression*: Expression

proc new_statement*(destination: Token, expression: Expression): Statement =
  Statement(destination: destination, expression: expression)

proc location*(statement: Statement): Location = statement.destination.location
proc `$`*(statement: Statement): string = fmt"{statement.destination} = {statement.expression}"
