import results, strformat, sets, options

import "../blocks"
import function_call
import struct_init
import struct_getter

type
  ResolvedStatementKind* = enum
    RSK_STRUCT_INIT
    RSK_STRUCT_GETTER
    RSK_FUNCTION_CALL
  ResolvedStatement* = ref object of RootObj
    destination*: Token
    case kind: ResolvedStatementKind
    of RSK_STRUCT_INIT:
      struct_init: ResolvedStructInit
    of RSK_STRUCT_GETTER:
      struct_getter: ResolvedStructGetter
    of RSK_FUNCTION_CALL:
      function_call: ResolvedFunctionCall

proc function_set*(statement: ResolvedStatement): Hashset[Function] =
  case statement.kind:
  of RSK_FUNCTION_CALL:
    var function_set: Hashset[Function]
    let maybe_ext_function = statement.function_call.user_function
    if maybe_ext_function.is_some:
      function_set.incl(maybe_ext_function.get)
    function_set
  else:
    init_hashset[Function]()

proc return_argument*(statement: ResolvedStatement): ArgumentDefinition =
  case statement.kind:
  of RSK_STRUCT_INIT:
    new_argument_definition(statement.struct_init.struct.name,
        statement.destination)
  of RSK_STRUCT_GETTER:
    new_argument_definition(statement.struct_getter.field.arg_type,
        statement.destination)
  of RSK_FUNCTION_CALL:
    new_argument_definition(statement.function_call.return_type,
        statement.destination)

proc c*(statement: ResolvedStatement): string =
  let rhs =
    case statement.kind:
    of RSK_STRUCT_INIT: statement.struct_init.c
    of RSK_STRUCT_GETTER: statement.struct_getter.c
    of RSK_FUNCTION_CALL: statement.function_call.c

  fmt"{statement.return_argument.c} = {rhs};"

proc new_resolved_statement*(struct_init: ResolvedStructInit,
    destination: Token): ResolvedStatement =
  ResolvedStatement(kind: RSK_STRUCT_INIT, struct_init: struct_init,
      destination: destination)

proc new_resolved_statement*(struct_getter: ResolvedStructGetter,
    destination: Token): ResolvedStatement =
  ResolvedStatement(kind: RSK_STRUCT_GETTER, struct_getter: struct_getter,
      destination: destination)

proc new_resolved_statement*(function_call: ResolvedFunctionCall,
    destination: Token): ResolvedStatement =
  ResolvedStatement(kind: RSK_FUNCTION_CALL, function_call: function_call,
      destination: destination)
