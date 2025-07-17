import results, strformat, sets, options

import "../blocks"
import function_call
import struct_init
import struct_getter

type
  ResolvedExpressionKind* = enum
    REK_VARIABLE
    REK_STRUCT_INIT
    REK_STRUCT_GETTER
    REK_FUNCTION_CALL
    REK_LITERAL_INIT
    REK_UNION_INIT
  ResolvedExpression* = ref object of RootObj
    case kind*: ResolvedExpressionKind
    of REK_VARIABLE: variable*: ArgumentDefinition
    of REK_STRUCT_INIT: struct_init: ResolvedStructInit
    of REK_STRUCT_GETTER: struct_getter: ResolvedStructGetter
    of REK_FUNCTION_CALL: function_call: ResolvedFunctionCall
    of REK_LITERAL_INIT: literal_init: LiteralInit
    of REK_UNION_INIT: union_init: ResolvedUnionInit

proc new_resolved_expression*(variable: ArgumentDefinition): ResolvedExpression =
  ResolvedExpression(kind: REK_VARIABLE, variable: variable)

proc new_resolved_expression*(struct_init: ResolvedStructInit): ResolvedExpression =
  ResolvedExpression(kind: REK_STRUCT_INIT, struct_init: struct_init)

proc new_resolved_expression*(struct_getter: ResolvedStructGetter): ResolvedExpression =
  ResolvedExpression(kind: REK_STRUCT_GETTER, struct_getter: struct_getter)

proc new_resolved_expression*(function_call: ResolvedFunctionCall): ResolvedExpression =
  ResolvedExpression(kind: REK_FUNCTION_CALL, function_call: function_call)

proc new_resolved_expression*(literal_init: LiteralInit): ResolvedExpression =
  ResolvedExpression(kind: REK_LITERAL_INIT, literal_init: literal_init)

proc new_resolved_expression*(union_init: ResolvedUnionInit): ResolvedExpression =
  ResolvedExpression(kind: REK_UNION_INIT, union_init: union_init)

proc function_refs*(expression: ResolvedExpression): Hashset[
    ResolvedFunctionRef] =
  var function_set: Hashset[ResolvedFunctionRef]
  case expression.kind:
  of REK_FUNCTION_CALL:
    let maybe_func_ref = expression.function_call.user_function
    if maybe_func_ref.is_some: function_set.incl(maybe_func_ref.get)
  else: discard
  return function_set

proc return_type*(expression: ResolvedExpression): Token =
  case expression.kind:
  of REK_VARIABLE: expression.variable.arg_type
  of REK_STRUCT_INIT: expression.struct_init.module.name
  of REK_STRUCT_GETTER: expression.struct_getter.field.arg_type
  of REK_FUNCTION_CALL: expression.function_call.return_type
  of REK_LITERAL_INIT: expression.literal_init.arg_type
  of REK_UNION_INIT: expression.union_init.module.name

proc c*(expression: ResolvedExpression): string =
  let native_code =
    case expression.kind:
    of REK_VARIABLE: $(expression.variable.arg_name)
    of REK_STRUCT_INIT: expression.struct_init.c
    of REK_STRUCT_GETTER: expression.struct_getter.c
    of REK_FUNCTION_CALL: expression.function_call.c
    of REK_LITERAL_INIT: $(expression.literal_init.arg_value)
    of REK_UNION_INIT: expression.union_init.c
  fmt"{native_code};"

type
  ResolvedStatement* = ref object of RootObj
    destination*: Token
    expression*: ResolvedExpression

proc function_refs*(statement: ResolvedStatement): Hashset[
    ResolvedFunctionRef] = statement.expression.function_refs

proc return_argument*(statement: ResolvedStatement): ArgumentDefinition =
  new_argument_definition(statement.expression.return_type,
      statement.destination)

proc c*(statement: ResolvedStatement): string =
  fmt"{statement.return_argument.c} = {statement.expression.c}"

proc new_resolved_statement*(destination: Token,
    expression: ResolvedExpression): ResolvedStatement =
  ResolvedStatement(destination: destination, expression: expression)
