import parse_result/location; export location
import parse_result/identifier; export identifier
import parse_result/init; export init
import parse_result/arglist; export arglist
import parse_result/fncall; export fncall
import parse_result/value; export value
import parse_result/assignment; export assignment
import parse_result/macro_call; export macro_call
import parse_result/statement; export statement
import parse_result/program; export program

type
  ParserResultKind* = enum
    PRK_RAW_STRING,
    PRK_IDENTIFER,
    PRK_INIT,
    PRK_ARGLIST,
    PRK_FNCALL,
    PRK_VALUE,
    PRK_ASSINGMENT,
    PRK_FN_MACRO,
    PRK_ARG_DEF,
    PRK_ARG_DEF_LIST,
    PRK_APP_MACRO,
    PRK_MACRO_CALL,
    PRK_COMMENT,
    PRK_STATEMENT,
    PRK_LINE,
    PRK_PROGRAM
  ParseResult* = ref object of RootObj
    case kind*: ParserResultKind
    of PRK_RAW_STRING: raw_string*: string
    of PRK_IDENTIFER: identifier*: Identifier
    of PRK_INIT: init*: Initializer
    of PRK_ARGLIST: arglist*: ArgumentList
    of PRK_FNCALL: fncall*: FunctionCall
    of PRK_VALUE: value*: Value
    of PRK_ASSINGMENT: assign*: Assignment
    of PRK_FN_MACRO: fn_macro*: FunctionMacro
    of PRK_ARG_DEF: arg_def*: ArgumentDefintion
    of PRK_ARG_DEF_LIST: arg_def_list*: ArgumentDefintionList
    of PRK_APP_MACRO: app_macro*: AppMacro
    of PRK_MACRO_CALL: macro_call*: MacroCall
    of PRK_COMMENT: comment*: Comment
    of PRK_STATEMENT: statement*: Statement
    of PRK_LINE: line*: Line
    of PRK_PROGRAM: program*: Program

proc `$`*(pr: ParseResult): string =
  case pr.kind:
  of PRK_RAW_STRING: pr.raw_string
  of PRK_IDENTIFER: $(pr.identifier)
  of PRK_INIT: $(pr.init)
  of PRK_ARGLIST: $(pr.arglist)
  of PRK_FNCALL: $(pr.fncall)
  of PRK_VALUE: $(pr.value)
  of PRK_ASSINGMENT: $(pr.assign)
  of PRK_FN_MACRO: $(pr.fn_macro)
  of PRK_ARG_DEF: $(pr.arg_def)
  of PRK_ARG_DEF_LIST: $(pr.arg_def_list)
  of PRK_APP_MACRO: $(pr.app_macro)
  of PRK_MACRO_CALL: $(pr.macro_call)
  of PRK_COMMENT: $(pr.comment)
  of PRK_STATEMENT: $(pr.statement)
  of PRK_LINE: $(pr.line)
  of PRK_PROGRAM: $(pr.program)

proc to_parse_result*(raw_string: string): ParseResult =
  ParseResult(kind: PRK_RAW_STRING, raw_string: raw_string)

proc to_parse_result*(identifier: Identifier): ParseResult =
  ParseResult(kind: PRK_IDENTIFER, identifier: identifier)

proc to_parse_result*(init: Initializer): ParseResult =
  ParseResult(kind: PRK_INIT, init: init)

proc to_parse_result*(arglist: ArgumentList): ParseResult =
  ParseResult(kind: PRK_ARGLIST, arglist: arglist)

proc to_parse_result*(fncall: FunctionCall): ParseResult =
  ParseResult(kind: PRK_FNCALL, fncall: fncall)

proc to_parse_result*(value: Value): ParseResult =
  ParseResult(kind: PRK_VALUE, value: value)

proc to_parse_result*(assign: Assignment): ParseResult =
  ParseResult(kind: PRK_ASSINGMENT, assign: assign)

proc to_parse_result*(fn_macro: FunctionMacro): ParseResult =
  ParseResult(kind: PRK_FN_MACRO, fn_macro: fn_macro)

proc to_parse_result*(arg_def: ArgumentDefintion): ParseResult =
  ParseResult(kind: PRK_ARG_DEF, arg_def: arg_def)

proc to_parse_result*(arg_def_list: ArgumentDefintionList): ParseResult =
  ParseResult(kind: PRK_ARG_DEF_LIST, arg_def_list: arg_def_list)

proc to_parse_result*(app_macro: AppMacro): ParseResult =
  ParseResult(kind: PRK_APP_MACRO, app_macro: app_macro)

proc to_parse_result*(macro_call: MacroCall): ParseResult =
  ParseResult(kind: PRK_MACRO_CALL, macro_call: macro_call)

proc to_parse_result*(statement: Statement): ParseResult =
  ParseResult(kind: PRK_STATEMENT, statement: statement)

proc to_parse_result*(comment: Comment): ParseResult =
  ParseResult(kind: PRK_COMMENT, comment: comment)

proc to_parse_result*(line: Line): ParseResult =
  ParseResult(kind: PRK_LINE, line: line)

proc to_parse_result*(program: Program): ParseResult =
  ParseResult(kind: PRK_PROGRAM, program: program)
