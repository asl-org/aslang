import assignment
import macro_call

type
  StatementKind = enum
    SK_ASSIGNMENT, SK_MACRO_CALL
  Statement* = ref object of RootObj
    case kind: StatementKind
    of SK_ASSIGNMENT: assign: Assignment
    of SK_MACRO_CALL: macro_call: MacroCall

proc new_statement*(assign: Assignment): Statement =
  Statement(kind: SK_ASSIGNMENT, assign: assign)

proc new_statement*(macro_call: MacroCall): Statement =
  Statement(kind: SK_MACRO_CALL, macro_call: macro_call)

proc `$`*(statement: Statement): string =
  case statement.kind:
  of SK_ASSIGNMENT: $(statement.assign)
  of SK_MACRO_CALL: $(statement.macro_call)
