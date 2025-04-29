import macro_header, statement

type
  LineKind* = enum
    LK_MACRO, LK_STATEMENT, LK_COMMENT, LK_EMPTY
  Line* = ref object of RootObj
    case kind: LineKind
    of LK_MACRO: macro_header: MacroHeader
    of LK_STATEMENT: statement: Statement
    else: discard

proc kind*(line: Line): LineKind = line.kind
proc statement*(line: Line): Statement = line.statement

proc `$`*(line: Line): string =
  case line.kind:
  of LK_MACRO: $(line.macro_header)
  of LK_STATEMENT: $(line.statement)
  else: ""

proc new_macro_header_line*(macro_header: MacroHeader): Line =
  Line(kind: LK_MACRO, macro_header: macro_header)

proc new_statement_line*(statement: Statement): Line =
  Line(kind: LK_STATEMENT, statement: statement)

proc new_ignorable_line*(): Line =
  Line(kind: LK_EMPTY)
