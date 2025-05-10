import strutils, strformat, sequtils, results

# location.nim
type Location* = object
  file: string
  line*: int = 1
  col*: int = 1

proc `$`*(location: Location): string =
  fmt"{location.file}({location.line},{location.col})"

proc new_location*(file: string): Location =
  Location(file: file)

# identifier.nim
type Identifier* = ref object of RootObj
  name: string
  location: Location

proc `$`*(identifier: Identifier): string = identifier.name
proc name*(identifier: Identifier): string = identifier.name
proc location*(identifier: Identifier): Location = identifier.location

proc new_identifier*(name: string, location: Location): Identifier =
  Identifier(name: name, location: location)

# init.nim
type Initializer* = ref object of RootObj
  module_name: Identifier
  literal: Identifier
  location: Location

proc `$`*(init: Initializer): string =
  fmt"{init.module_name} {init.literal}"

proc new_init*(mod_name: Identifier, literal: Identifier,
    location: Location): Initializer =
  Initializer(module_name: mod_name, literal: literal, location: location)

# arglist.nim
type ArgumentList* = ref object of RootObj
  args: seq[Identifier]
  location: Location

proc new_arglist*(args: seq[Identifier], location: Location): ArgumentList =
  ArgumentList(args: args, location: location)

proc `$`*(arglist: ArgumentList): string =
  "(" & arglist.args.join(", ") & ")"

# fncall.nim
type FunctionCall* = ref object of RootObj
  module_name: Identifier
  fn_name: Identifier
  arglist: ArgumentList
  location: Location

proc new_fncall*(module_name: Identifier, fn_name: Identifier,
    arglist: ArgumentList): FunctionCall =
  FunctionCall(module_name: module_name, fn_name: fn_name, arglist: arglist)

proc `$`*(fncall: FunctionCall): string =
  fmt"{fncall.module_name}.{fncall.fn_name}{fncall.arglist}"

# value.nim
type
  ValueKind = enum
    VK_INIT, VK_FNCALL
  Value* = ref object of RootObj
    location: Location
    case kind: ValueKind
    of VK_INIT: init: Initializer
    of VK_FNCALL: fncall: FunctionCall

proc new_value*(init: Initializer): Value = Value(kind: VK_INIT, init: init)
proc new_value*(fncall: FunctionCall): Value = Value(kind: VK_FNCALL,
    fncall: fncall)

proc `$`*(value: Value): string =
  case value.kind:
  of VK_INIT: $(value.init)
  of VK_FNCALL: $(value.fncall)

# assignment.nim
type Assignment* = ref object of RootObj
  dest: Identifier
  value: Value
  location: Location

proc new_assignment*(dest: Identifier, value: Value,
    location: Location): Assignment =
  Assignment(dest: dest, value: value, location: location)

proc `$`*(assignment: Assignment): string =
  fmt"{assignment.dest} = {assignment.value}"

# arg_def.nim
type ArgumentDefintion* = ref object of RootObj
  module: Identifier
  name: Identifier
  location: Location

proc new_arg_def*(module: Identifier, name: Identifier): ArgumentDefintion =
  ArgumentDefintion(module: module, name: name)

proc `$`*(arg_def: ArgumentDefintion): string =
  fmt"{arg_def.module} {arg_def.name}"

# arg_def_list.nim
type ArgumentDefintionList* = ref object of RootObj
  defs: seq[ArgumentDefintion]
  location: Location

proc defs*(arg_def_list: ArgumentDefintionList): seq[
    ArgumentDefintion] = arg_def_list.defs

proc new_arg_def_list*(defs: seq[ArgumentDefintion]): ArgumentDefintionList =
  ArgumentDefintionList(defs: defs)

proc `$`*(arg_def_list: ArgumentDefintionList): string =
  let defs = arg_def_list.defs.map(proc(x: ArgumentDefintion): string = $(
      x)).join(", ")
  "args(" & defs & "):"

# fn_macro.nim
type FunctionMacro* = ref object of RootObj
  name: Identifier
  returns: Identifier
  location: Location

proc name*(fn_macro: FunctionMacro): Identifier = fn_macro.name
proc returns*(fn_macro: FunctionMacro): Identifier = fn_macro.returns

proc new_fn_macro*(name: Identifier, returns: Identifier): FunctionMacro =
  FunctionMacro(name: name, returns: returns)

proc `$`*(fn_macro: FunctionMacro): string =
  fmt"function {fn_macro.name} returns {fn_macro.returns}:"

# app_macro.nim
type AppMacro* = ref object of RootObj
  name: Identifier
  location: Location

proc name*(app_macro: AppMacro): Identifier = app_macro.name

proc new_app_macro*(name: Identifier): AppMacro =
  AppMacro(name: name)

proc `$`*(app_macro: AppMacro): string =
  fmt"app {app_macro.name}:"

# macro_call.nim
type
  MacroCallKind* = enum
    MCK_FN, MCK_ARGS, MCK_APP
  MacroCall* = ref object of RootObj
    case kind: MacroCallKind
    of MCK_FN: fn_macro: FunctionMacro
    of MCK_ARGS: arg_def_list: ArgumentDefintionList
    of MCK_APP: app_macro: AppMacro

proc `$`*(macro_call: MacroCall): string =
  case macro_call.kind:
  of MCK_FN: $(macro_call.fn_macro)
  of MCK_ARGS: $(macro_call.arg_def_list)
  of MCK_APP: $(macro_call.app_macro)

proc kind*(macro_call: MacroCall): MacroCallKind = macro_call.kind
proc app_macro*(macro_call: MacroCall): AppMacro = macro_call.app_macro
proc fn_macro*(macro_call: MacroCall): FunctionMacro = macro_call.fn_macro
proc arg_def_list*(macro_call: MacroCall): ArgumentDefintionList = macro_call.arg_def_list

proc safe_app_macro*(macro_call: MacroCall): Result[AppMacro, string] =
  case macro_call.kind:
  of MCK_APP: ok(macro_call.app_macro)
  else: return err(fmt"Macro {macro_call} is not an app macro")

proc safe_fn_macro*(macro_call: MacroCall): Result[FunctionMacro, string] =
  case macro_call.kind:
  of MCK_FN: ok(macro_call.fn_macro)
  else: return err(fmt"Macro {macro_call} is not an app macro")

proc safe_args_macro*(macro_call: MacroCall): Result[ArgumentDefintionList, string] =
  case macro_call.kind:
  of MCK_ARGS: ok(macro_call.arg_def_list)
  else: return err(fmt"Macro {macro_call} is not an app macro")

proc new_macro_call*(fn_macro: FunctionMacro): MacroCall =
  MacroCall(kind: MCK_FN, fn_macro: fn_macro)

proc new_macro_call*(arg_def_list: ArgumentDefintionList): MacroCall =
  MacroCall(kind: MCK_ARGS, arg_def_list: arg_def_list)

proc new_macro_call*(app_macro: AppMacro): MacroCall =
  MacroCall(kind: MCK_APP, app_macro: app_macro)

# statement.nim
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

# comment.nim
type Comment* = ref object of RootObj
  content: string

proc new_comment*(content: string): Comment =
  Comment(content: content)

proc `$`*(comment: Comment): string =
  fmt"# {comment.content}"

# line.nim
type
  LineKind* = enum
    LK_STATEMENT, LK_COMMENT, LK_EMPTY
  Line* = ref object of RootObj
    spaces: int
    case kind: LineKind
    of LK_STATEMENT: statement: Statement
    of LK_COMMENT: comment: Comment
    of LK_EMPTY: discard

proc kind*(line: Line): LineKind = line.kind
proc statement*(line: Line): Statement = line.statement
proc spaces*(line: Line): int = line.spaces

proc safe_statement*(line: Line): Result[Statement, string] =
  case line.kind:
  of LK_STATEMENT: ok(line.statement)
  else: err("Line {line} is not a statement")

proc safe_assignment*(line: Line): Result[Assignment, string] =
  let statement = ? line.safe_statement()
  statement.safe_assignment()

proc safe_app_macro*(line: Line): Result[AppMacro, string] =
  let statement = ? line.safe_statement()
  statement.safe_app_macro()

proc safe_fn_macro*(line: Line): Result[FunctionMacro, string] =
  let statement = ? line.safe_statement()
  statement.safe_fn_macro()

proc safe_args_macro*(line: Line): Result[ArgumentDefintionList, string] =
  let statement = ? line.safe_statement()
  statement.safe_args_macro()

proc new_line*(statement: Statement, spaces: int): Line =
  Line(kind: LK_STATEMENT, statement: statement, spaces: spaces)

proc new_line*(comment: Comment, spaces: int): Line =
  Line(kind: LK_COMMENT, comment: comment, spaces: spaces)

proc new_empty_line*(spaces: int): Line =
  Line(kind: LK_EMPTY, spaces: spaces)

proc `$`*(line: Line): string =
  let content =
    case line.kind:
    of LK_STATEMENT: $(line.statement)
    of LK_COMMENT: $(line.comment)
    of LK_EMPTY: ""

  (" ".repeat(line.spaces)) & content

# program.nim
type Program* = ref object of RootObj
  lines: seq[Line]

proc `$`*(program: Program): string =
  program.lines.map(proc(x: Line): string = $(x)).join("\n")

proc new_program*(lines: seq[Line]): Program =
  Program(lines: lines)

proc lines*(program: Program): seq[Line] = program.lines

proc only_statements*(program: Program): Program =
  program.lines = program.lines.filter(proc(l: Line): bool = l.kind == LK_STATEMENT)
  return program

# parse_result.nim
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
