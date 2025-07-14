import results, strformat, sets, options

import "../blocks"
import function_call
import struct_init
import struct_getter

type
  ResolvedExpressionKind* = enum
    REK_STRUCT_INIT
    REK_STRUCT_GETTER
    REK_FUNCTION_CALL
  ResolvedExpression* = ref object of RootObj
    case kind*: ResolvedExpressionKind
    of REK_STRUCT_INIT: struct_init: ResolvedStructInit
    of REK_STRUCT_GETTER: struct_getter: ResolvedStructGetter
    of REK_FUNCTION_CALL: function_call: ResolvedFunctionCall

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
  of REK_STRUCT_INIT: expression.struct_init.module.name
  of REK_STRUCT_GETTER: expression.struct_getter.field.arg_type
  of REK_FUNCTION_CALL: expression.function_call.return_type

proc c*(expression: ResolvedExpression): string =
  let native_code =
    case expression.kind:
    of REK_STRUCT_INIT: expression.struct_init.c
    of REK_STRUCT_GETTER: expression.struct_getter.c
    of REK_FUNCTION_CALL: expression.function_call.c
  fmt"{native_code};"

proc new_resolved_expression*(struct_init: ResolvedStructInit): ResolvedExpression =
  ResolvedExpression(kind: REK_STRUCT_INIT, struct_init: struct_init)

proc new_resolved_expression*(struct_getter: ResolvedStructGetter): ResolvedExpression =
  ResolvedExpression(kind: REK_STRUCT_GETTER, struct_getter: struct_getter)

proc new_resolved_expression*(function_call: ResolvedFunctionCall): ResolvedExpression =
  ResolvedExpression(kind: REK_FUNCTION_CALL, function_call: function_call)

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
  fmt"{statement.return_argument.c} = {statement.expression.c};"

proc new_resolved_statement*(destination: Token,
    expression: ResolvedExpression): ResolvedStatement =
  ResolvedStatement(destination: destination, expression: expression)
