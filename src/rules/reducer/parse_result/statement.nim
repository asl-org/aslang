import results, strformat

import assignment
import macro_call
import location

type
  StatementKind* = enum
    SK_ASSIGNMENT, SK_MACRO_CALL
  Statement* = ref object of RootObj
    location: Location
    case kind: StatementKind
    of SK_ASSIGNMENT: assign: Assignment
    of SK_MACRO_CALL: macro_call: MacroCall

proc `$`*(statement: Statement): string =
  case statement.kind:
  of SK_ASSIGNMENT: $(statement.assign)
  of SK_MACRO_CALL: $(statement.macro_call)

proc kind*(statement: Statement): StatementKind = statement.kind
proc macro_call*(statement: Statement): MacroCall = statement.macro_call
proc assign*(statement: Statement): Assignment = statement.assign

proc safe_macro_call*(statement: Statement): Result[MacroCall, string] =
  case statement.kind:
  of SK_ASSIGNMENT: err(fmt"Statement {statement} is not a macro call")
  of SK_MACRO_CALL: ok(statement.macro_call)

proc safe_assignment*(statement: Statement): Result[Assignment, string] =
  case statement.kind:
  of SK_ASSIGNMENT: ok(statement.assign)
  of SK_MACRO_CALL: err(fmt"Statement {statement} is not an assignment")

proc safe_app_macro*(statement: Statement): Result[AppMacro, string] =
  let macro_call = ? statement.safe_macro_call()
  return macro_call.safe_app_macro()

proc safe_fn_macro*(statement: Statement): Result[FunctionMacro, string] =
  let macro_call = ? statement.safe_macro_call()
  return macro_call.safe_fn_macro()

proc safe_args_macro*(statement: Statement): Result[ArgumentDefintionList, string] =
  let macro_call = ? statement.safe_macro_call()
  return macro_call.safe_args_macro()

proc new_statement*(assign: Assignment): Statement =
  Statement(kind: SK_ASSIGNMENT, assign: assign)

proc new_statement*(macro_call: MacroCall): Statement =
  Statement(kind: SK_MACRO_CALL, macro_call: macro_call)
