import location, initializer, function_call

type
  StatementKind* = enum
    SK_INITIALIZER, SK_FUNCTION_CALL

  Statement* = ref object of RootObj
    location: Location
    level: int
    case kind: StatementKind
    of SK_INITIALIZER: init*: Initializer
    of SK_FUNCTION_CALL: fncall*: Functioncall

proc location*(statement: Statement): Location = statement.location
proc level*(statement: Statement): int = statement.level
proc kind*(statement: Statement): StatementKind = statement.kind
proc init*(statement: Statement): Initializer = statement.init
proc fncall*(statement: Statement): Functioncall = statement.fncall

proc `$`*(statement: Statement): string =
  case statement.kind:
  of SK_INITIALIZER: $(statement.init)
  of SK_FUNCTION_CALL: $(statement.fncall)

proc new_init_statement*(level: int, init: Initializer,
    location: Location): Statement =
  Statement(kind: SK_INITIALIZER, init: init, level: level,
      location: location)

proc new_fncall_statement*(level: int, fncall: Functioncall,
    location: Location): Statement =
  Statement(kind: SK_FUNCTION_CALL, fncall: fncall, level: level,
      location: location)
