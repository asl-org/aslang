import results, strformat, sets, options, tables, strutils

import arg
import function_ref

import function_call
import struct_init
import struct_getter

type
  ResolvedExpressionKind* = enum
    REK_ARGUMENT
    REK_FUNCTION_CALL
    REK_STRUCT_INIT
    REK_STRUCT_GETTER
    REK_UNION_INIT
  ResolvedExpression* = ref object of RootObj
    case kind*: ResolvedExpressionKind
    of REK_ARGUMENT: argument: ResolvedArgument
    of REK_FUNCTION_CALL: function_call: ResolvedFunctionCall
    of REK_STRUCT_INIT: struct_init: ResolvedStructInit
    of REK_STRUCT_GETTER: struct_getter: ResolvedStructGetter
    of REK_UNION_INIT: union_init: ResolvedUnionInit

proc new_resolved_expression*(argument: ResolvedArgument): ResolvedExpression =
  ResolvedExpression(kind: REK_ARGUMENT, argument: argument)

proc new_resolved_expression*(function_call: ResolvedFunctionCall): ResolvedExpression =
  ResolvedExpression(kind: REK_FUNCTION_CALL, function_call: function_call)

proc new_resolved_expression*(struct_init: ResolvedStructInit): ResolvedExpression =
  ResolvedExpression(kind: REK_STRUCT_INIT, struct_init: struct_init)

proc new_resolved_expression*(struct_getter: ResolvedStructGetter): ResolvedExpression =
  ResolvedExpression(kind: REK_STRUCT_GETTER, struct_getter: struct_getter)

proc new_resolved_expression*(union_init: ResolvedUnionInit): ResolvedExpression =
  ResolvedExpression(kind: REK_UNION_INIT, union_init: union_init)

proc function_refs*(expression: ResolvedExpression): Hashset[
    ResolvedFunctionRef] =
  var function_set: Hashset[ResolvedFunctionRef]
  case expression.kind:
  of REK_FUNCTION_CALL:
    let maybe_func_ref = expression.function_call.user_function
    if maybe_func_ref.is_some: function_set.incl(maybe_func_ref.get)
  of REK_STRUCT_INIT:
    function_set.incl(expression.struct_init.function_refs)
  of REK_UNION_INIT:
    function_set.incl(expression.union_init.function_refs)
  else: discard
  return function_set

proc generic_impls*(expression: ResolvedExpression): Table[string, Table[string,
    HashSet[string]]] =
  case expression.kind:
  of REK_UNION_INIT: expression.union_init.generic_impls
  of REK_STRUCT_INIT: expression.struct_init.generic_impls
  of REK_FUNCTION_CALL: expression.function_call.generic_impls
  else: init_table[string, Table[string, HashSet[string]]]()

proc resolved_return_type*(expression: ResolvedExpression): ResolvedArgumentType =
  case expression.kind:
  of REK_ARGUMENT: expression.argument.resolved_return_type
  of REK_FUNCTION_CALL: expression.function_call.resolved_return_type
  of REK_STRUCT_INIT: expression.struct_init.resolved_return_type
  of REK_STRUCT_GETTER: expression.struct_getter.resolved_return_type
  of REK_UNION_INIT: expression.union_init.resolved_return_type

proc c*(expression: ResolvedExpression, return_argument: ResolvedArgumentDefinition): string =
  case expression.kind:
  of REK_ARGUMENT:
    fmt"{return_argument.c} = {expression.argument.c};"
  of REK_FUNCTION_CALL:
    fmt"{return_argument.c} = {expression.function_call.c};"
  of REK_STRUCT_INIT:
    fmt"{return_argument.c} = {expression.struct_init.c};"
  of REK_STRUCT_GETTER:
    fmt"{return_argument.c} = {expression.struct_getter.c};"
  of REK_UNION_INIT:
    if expression.union_init.generic_impls.len == 0:
      fmt"{return_argument.c} = {expression.union_init.c};"
    else:
      var lines = expression.union_init.c.split("\n")
      lines[^1] = fmt"{return_argument.c} = {lines[^1]};";
      lines.join("\n")

type
  ResolvedStatement* = ref object of RootObj
    destination*: Token
    expression*: ResolvedExpression

proc function_refs*(statement: ResolvedStatement): Hashset[
    ResolvedFunctionRef] = statement.expression.function_refs

proc generic_impls*(statement: ResolvedStatement): Table[string, Table[string,
    HashSet[string]]] =
  statement.expression.generic_impls

proc resolved_return_argument*(statement: ResolvedStatement): ResolvedArgumentDefinition =
  new_resolved_argument_definition(statement.destination,
      statement.expression.resolved_return_type)

proc c*(statement: ResolvedStatement): string =
  statement.expression.c(statement.resolved_return_argument)

proc new_resolved_statement*(destination: Token,
    expression: ResolvedExpression): ResolvedStatement =
  ResolvedStatement(destination: destination, expression: expression)
