import strformat, sequtils, strutils

import token, function_call, arg_def

type StructInit* = ref object of RootObj
  struct*: ArgumentType
  fields*: seq[(Token, Token)]

proc new_struct_init*(struct: ArgumentType, fields: seq[(Token,
    Token)]): StructInit =
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

type LiteralInit* = ref object of RootObj
  arg_type*: Token
  arg_value*: Token

proc new_literal_init*(arg_type: Token, arg_value: Token): LiteralInit =
  LiteralInit(arg_type: arg_type, arg_value: arg_value)

proc location*(literal_init: LiteralInit): Location =
  literal_init.arg_type.location

proc `$`*(literal_init: LiteralInit): string =
  fmt"{literal_init.arg_type} {literal_init.arg_value}"

type UnionInit* = ref object of RootObj
  name*: ArgumentType
  field_name*: Token
  union_fields*: seq[(Token, Token)]

proc new_union_init*(name: ArgumentType, field_name: Token, union_fields: seq[(
    Token, Token)]): UnionInit =
  UnionInit(name: name, field_name: field_name, union_fields: union_fields)

proc location*(union_init: UnionInit): Location =
  union_init.name.location

proc `$`*(union_init: UnionInit): string =
  let fields = union_init.union_fields.map_it(fmt"{it[0]}: {it[1]}").join(", ")
  $(union_init.name) & "." & $(union_init.field_name) & " { " & fields & " }"

type
  ExpressionKind* = enum
    EK_VARIABLE, EK_FUNCTION_CALL,
    EK_STRUCT_INIT, EK_STRUCT_GETTER
    EK_LITERAL_INIT, EK_UNION_INIT
  Expression* = ref object of RootObj
    case kind*: ExpressionKind
    of EK_VARIABLE: variable*: Token
    of EK_FUNCTION_CALL: function_call*: FunctionCall
    of EK_STRUCT_INIT: struct_init*: StructInit
    of EK_STRUCT_GETTER: struct_getter*: StructGetter
    of EK_LITERAL_INIT: literal_init*: LiteralInit
    of EK_UNION_INIT: union_init*: UnionInit

proc new_expression*(variable: Token): Expression =
  Expression(kind: EK_VARIABLE, variable: variable)

proc new_expression*(function_call: FunctionCall): Expression =
  Expression(kind: EK_FUNCTION_CALL, function_call: function_call)

proc new_expression*(struct_init: StructInit): Expression =
  Expression(kind: EK_STRUCT_INIT, struct_init: struct_init)

proc new_expression*(struct_getter: StructGetter): Expression =
  Expression(kind: EK_STRUCT_GETTER, struct_getter: struct_getter)

proc new_expression*(literal_init: LiteralInit): Expression =
  Expression(kind: EK_LITERAL_INIT, literal_init: literal_init)

proc new_expression*(union_init: UnionInit): Expression =
  Expression(kind: EK_UNION_INIT, union_init: union_init)

proc location*(expression: Expression): Location =
  case expression.kind:
  of EK_VARIABLE: expression.variable.location
  of EK_FUNCTION_CALL: expression.function_call.location
  of EK_STRUCT_INIT: expression.struct_init.location
  of EK_STRUCT_GETTER: expression.struct_getter.location
  of EK_LITERAL_INIT: expression.literal_init.location
  of EK_UNION_INIT: expression.union_init.location

proc `$`*(expression: Expression): string =
  case expression.kind:
  of EK_VARIABLE: $(expression.variable)
  of EK_FUNCTION_CALL: $(expression.function_call)
  of EK_STRUCT_GETTER: $(expression.struct_getter)
  of EK_STRUCT_INIT: $(expression.struct_init)
  of EK_LITERAL_INIT: $(expression.literal_init)
  of EK_UNION_INIT: $(expression.union_init)

type
  StatementKind* = enum
    SK_ASSIGNMENT, SK_EXPRESSION
  Statement* = ref object of RootObj
    expression*: Expression
    case kind*: StatementKind
    of SK_ASSIGNMENT: destination*: Token
    of SK_EXPRESSION: discard

proc new_statement*(destination: Token, expression: Expression): Statement =
  Statement(kind: SK_ASSIGNMENT, expression: expression,
      destination: destination)

proc new_statement*(expression: Expression): Statement =
  Statement(kind: SK_EXPRESSION, expression: expression)

proc set_destination*(statement: Statement, temp_var_name: string): Statement =
  temp_var_name.new_id_token().new_statement(statement.expression)

proc location*(statement: Statement): Location =
  case statement.kind:
  of SK_ASSIGNMENT: statement.destination.location
  of SK_EXPRESSION: statement.expression.location

proc `$`*(statement: Statement): string =
  case statement.kind:
  of SK_ASSIGNMENT: fmt"{statement.destination} = {statement.expression}"
  of SK_EXPRESSION: fmt"{statement.expression}"
