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
  "(" & defs & ")"

# fn_def.nim
type FunctionDefinition* = ref object of RootObj
  name: Identifier
  returns: Identifier
  arg_def_list: ArgumentDefintionList
  location: Location

proc name*(fn_def: FunctionDefinition): Identifier = fn_def.name
proc returns*(fn_def: FunctionDefinition): Identifier = fn_def.returns
proc arg_def_list*(fn_def: FunctionDefinition): ArgumentDefintionList = fn_def.arg_def_list

proc new_fn_def*(name: Identifier, returns: Identifier,
    arg_def_list: ArgumentDefintionList): FunctionDefinition =
  FunctionDefinition(name: name, returns: returns, arg_def_list: arg_def_list)

proc `$`*(fn_def: FunctionDefinition): string =
  fmt"fn {fn_def.name}{fn_def.arg_def_list} returns {fn_def.returns}:"

# app_def.nim
type AppDefinition* = ref object of RootObj
  name: Identifier
  location: Location

proc name*(app_def: AppDefinition): Identifier = app_def.name

proc new_app_def*(name: Identifier): AppDefinition =
  AppDefinition(name: name)

proc `$`*(app_def: AppDefinition): string =
  fmt"app {app_def.name}:"

# module_def.nim
type ModuleDefinition* = ref object of RootObj
  name: Identifier
  location: Location

proc name*(module_def: ModuleDefinition): Identifier = module_def.name

proc new_module_def*(name: Identifier): ModuleDefinition =
  ModuleDefinition(name: name)

proc `$`*(module_def: ModuleDefinition): string =
  fmt"module {module_def.name}:"

# struct_def.nim
type StructDefinition* = ref object of RootObj
  name: Identifier
  location: Location

proc name*(struct_def: StructDefinition): Identifier = struct_def.name

proc new_struct_def*(name: Identifier): StructDefinition =
  StructDefinition(name: name)

proc `$`*(struct_def: StructDefinition): string =
  fmt"struct {struct_def.name}:"

# union_def.nim
type UnionDefinition* = ref object of RootObj
  name: Identifier
  location: Location

proc name*(union_def: UnionDefinition): Identifier = union_def.name

proc new_union_def*(name: Identifier): UnionDefinition =
  UnionDefinition(name: name)

proc `$`*(union_def: UnionDefinition): string =
  fmt"union {union_def.name}:"

# macro_call.nim
type
  MacroCallKind* = enum
    MCK_FN, MCK_APP
  MacroCall* = ref object of RootObj
    case kind: MacroCallKind
    of MCK_FN: fn_def: FunctionDefinition
    of MCK_APP: app_def: AppDefinition

proc `$`*(macro_call: MacroCall): string =
  case macro_call.kind:
  of MCK_FN: $(macro_call.fn_def)
  of MCK_APP: $(macro_call.app_def)

proc kind*(macro_call: MacroCall): MacroCallKind = macro_call.kind
proc app_def*(macro_call: MacroCall): AppDefinition = macro_call.app_def
proc fn_def*(macro_call: MacroCall): FunctionDefinition = macro_call.fn_def

proc safe_app_def*(macro_call: MacroCall): Result[AppDefinition, string] =
  case macro_call.kind:
  of MCK_APP: ok(macro_call.app_def)
  else: return err(fmt"Macro {macro_call} is not an app macro")

proc safe_fn_def*(macro_call: MacroCall): Result[FunctionDefinition, string] =
  case macro_call.kind:
  of MCK_FN: ok(macro_call.fn_def)
  else: return err(fmt"Macro {macro_call} is not an app macro")

proc new_macro_call*(fn_def: FunctionDefinition): MacroCall =
  MacroCall(kind: MCK_FN, fn_def: fn_def)

proc new_macro_call*(app_def: AppDefinition): MacroCall =
  MacroCall(kind: MCK_APP, app_def: app_def)

# statement.nim
type
  StatementKind* = enum
    SK_ASSIGNMENT, SK_FNCALL
  Statement* = ref object of RootObj
    location: Location
    case kind: StatementKind
    of SK_ASSIGNMENT: assign: Assignment
    of SK_FNCALL: fncall: FunctionCall

proc `$`*(statement: Statement): string =
  case statement.kind:
  of SK_ASSIGNMENT: $(statement.assign)
  of SK_FNCALL: $(statement.fncall)

proc kind*(statement: Statement): StatementKind = statement.kind
proc assign*(statement: Statement): Assignment = statement.assign
proc fncall*(statement: Statement): FunctionCall = statement.fncall

proc safe_assignment*(statement: Statement): Result[Assignment, string] =
  case statement.kind:
  of SK_ASSIGNMENT: ok(statement.assign)
  of SK_FNCALL: err(fmt"Statement {statement} is not an assignment")

proc safe_fncall*(statement: Statement): Result[FunctionCall, string] =
  case statement.kind:
  of SK_FNCALL: ok(statement.fncall)
  of SK_ASSIGNMENT: err(fmt"Statement {statement} is not a function call")

proc new_statement*(assign: Assignment): Statement =
  Statement(kind: SK_ASSIGNMENT, assign: assign)

proc new_statement*(fncall: FunctionCall): Statement =
  Statement(kind: SK_FNCALL, fncall: fncall)

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
    LK_STATEMENT, LK_MACRO_CALL, LK_COMMENT, LK_EMPTY
  Line* = ref object of RootObj
    spaces: int
    case kind: LineKind
    of LK_STATEMENT: statement: Statement
    of LK_MACRO_CALL: macro_call: MacroCall
    of LK_COMMENT: comment: Comment
    of LK_EMPTY: discard

proc `$`*(line: Line): string =
  let content =
    case line.kind:
    of LK_STATEMENT: $(line.statement)
    of LK_MACRO_CALL: $(line.macro_call)
    of LK_COMMENT: $(line.comment)
    of LK_EMPTY: ""

  (" ".repeat(line.spaces)) & content

proc kind*(line: Line): LineKind = line.kind
proc statement*(line: Line): Statement = line.statement
proc macro_call*(line: Line): MacroCall = line.macro_call
proc spaces*(line: Line): int = line.spaces

proc safe_statement*(line: Line): Result[Statement, string] =
  case line.kind:
  of LK_STATEMENT: ok(line.statement)
  else: err("Line {line} is not a statement")

proc safe_macro_call*(line: Line): Result[MacroCall, string] =
  case line.kind:
  of LK_MACRO_CALL: ok(line.macro_call)
  else: err("Line {line} is not a statement")

proc safe_app_def*(line: Line): Result[AppDefinition, string] =
  let macro_call = ? line.safe_macro_call()
  macro_call.safe_app_def()

proc safe_fn_def*(line: Line): Result[FunctionDefinition, string] =
  let macro_call = ? line.safe_macro_call()
  macro_call.safe_fn_def()

proc new_line*(statement: Statement, spaces: int): Line =
  Line(kind: LK_STATEMENT, statement: statement, spaces: spaces)

proc new_line*(macro_call: MacroCall, spaces: int): Line =
  Line(kind: LK_MACRO_CALL, macro_call: macro_call, spaces: spaces)

proc new_line*(comment: Comment, spaces: int): Line =
  Line(kind: LK_COMMENT, comment: comment, spaces: spaces)

proc new_empty_line*(spaces: int): Line =
  Line(kind: LK_EMPTY, spaces: spaces)

# program.nim
type Program* = ref object of RootObj
  lines: seq[Line]

proc `$`*(program: Program): string =
  program.lines.map(proc(x: Line): string = $(x)).join("\n")

proc new_program*(lines: seq[Line]): Program =
  Program(lines: lines)

proc lines*(program: Program): seq[Line] = program.lines

proc only_statements*(program: Program): Program =
  program.lines = program.lines.filter(proc(l: Line): bool = l.kind in @[
      LK_STATEMENT, LK_MACRO_CALL])
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
    PRK_MODULE_MACRO,
    PRK_STRUCT_MACRO,
    PRK_UNION_MACRO,
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
    of PRK_FN_MACRO: fn_def*: FunctionDefinition
    of PRK_ARG_DEF: arg_def*: ArgumentDefintion
    of PRK_ARG_DEF_LIST: arg_def_list*: ArgumentDefintionList
    of PRK_APP_MACRO: app_def*: AppDefinition
    of PRK_MODULE_MACRO: module_def*: ModuleDefinition
    of PRK_STRUCT_MACRO: struct_def*: StructDefinition
    of PRK_UNION_MACRO: union_def*: UnionDefinition
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
  of PRK_FN_MACRO: $(pr.fn_def)
  of PRK_ARG_DEF: $(pr.arg_def)
  of PRK_ARG_DEF_LIST: $(pr.arg_def_list)
  of PRK_APP_MACRO: $(pr.app_def)
  of PRK_MODULE_MACRO: $(pr.module_def)
  of PRK_STRUCT_MACRO: $(pr.struct_def)
  of PRK_UNION_MACRO: $(pr.union_def)
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

proc to_parse_result*(fn_def: FunctionDefinition): ParseResult =
  ParseResult(kind: PRK_FN_MACRO, fn_def: fn_def)

proc to_parse_result*(arg_def: ArgumentDefintion): ParseResult =
  ParseResult(kind: PRK_ARG_DEF, arg_def: arg_def)

proc to_parse_result*(arg_def_list: ArgumentDefintionList): ParseResult =
  ParseResult(kind: PRK_ARG_DEF_LIST, arg_def_list: arg_def_list)

proc to_parse_result*(app_def: AppDefinition): ParseResult =
  ParseResult(kind: PRK_APP_MACRO, app_def: app_def)

proc to_parse_result*(module_def: ModuleDefinition): ParseResult =
  ParseResult(kind: PRK_MODULE_MACRO, module_def: module_def)

proc to_parse_result*(struct_def: StructDefinition): ParseResult =
  ParseResult(kind: PRK_STRUCT_MACRO, struct_def: struct_def)

proc to_parse_result*(union_def: UnionDefinition): ParseResult =
  ParseResult(kind: PRK_UNION_MACRO, union_def: union_def)

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
