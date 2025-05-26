import strutils, strformat, sequtils, results

import "../parser"; export parser;

type Atom* = ref object of RootObj
  value: string
  location: Location

proc `$`*(atom: Atom): string = atom.value
proc value*(atom: Atom): string = atom.value
proc location*(atom: Atom): Location = atom.location

proc new_atom*(value: string, location: Location): Atom =
  Atom(value: value, location: location)

# identifier.nim
type Identifier* = ref object of RootObj
  name: string
  location: Location

proc `$`*(identifier: Identifier): string = identifier.name
proc name*(identifier: Identifier): string = identifier.name
proc location*(identifier: Identifier): Location = identifier.location

proc new_identifier*(name: string, location: Location): Identifier =
  Identifier(name: name, location: location)

proc new_identifier*(name: string): Identifier =
  Identifier(name: name)

proc clone(identifier: Identifier): Identifier =
  Identifier(name: identifier.name, location: identifier.location)

# keyword_arg.nim
type
  KeywordArgValueKind* = enum
    KWAV_ATOM, KWAV_IDENTIFIER
  KeywordArgValue* = ref object of RootObj
    location: Location
    case kind: KeywordArgValueKind
    of KWAV_ATOM: atom*: Atom
    of KWAV_IDENTIFIER: identifier*: Identifier


proc kind*(kwarg_val: KeywordArgValue): KeywordArgValueKind = kwarg_val.kind
proc atom*(kwarg_val: KeywordArgValue): Atom = kwarg_val.atom
proc identifier*(kwarg_val: KeywordArgValue): Identifier = kwarg_val.identifier

proc `$`*(kwarg_val: KeywordArgValue): string =
  case kwarg_val.kind:
  of KWAV_ATOM: $(kwarg_val.atom)
  of KWAV_IDENTIFIER: $(kwarg_val.identifier)

proc new_keyword_arg_value*(atom: Atom): KeywordArgValue =
  KeywordArgValue(kind: KWAV_ATOM, atom: atom)

proc new_keyword_arg_value*(identifier: Identifier): KeywordArgValue =
  KeywordArgValue(kind: KWAV_IDENTIFIER, identifier: identifier)

type KeywordArg* = ref object of RootObj
  name: Identifier
  value: KeywordArgValue

proc name*(kwarg: KeywordArg): Identifier = kwarg.name
proc value*(kwarg: KeywordArg): KeywordArgValue = kwarg.value

proc `$`*(kwarg: KeywordArg): string =
  fmt"{kwarg.name}: {kwarg.value}"

proc new_keyword_arg*(name: Identifier, value: KeywordArgValue): KeywordArg =
  KeywordArg(name: name, value: value)

# struct.nim
type Struct* = ref object of RootObj
  kwargs: seq[KeywordArg]
  location: Location

proc kwargs*(struct: Struct): seq[KeywordArg] = struct.kwargs
proc location*(struct: Struct): Location = struct.location

proc `$`*(struct: Struct): string =
  let struct_fields = struct.kwargs.map(proc(x: KeywordArg): string = $(
      x)).join(", ")
  "{" & struct_fields & "}"

proc new_struct*(kwargs: seq[KeywordArg], location: Location): Struct =
  Struct(kwargs: kwargs)

# literal.nim
type
  LiteralKind* = enum
    LTK_NATIVE_NUMERIC, LTK_STRUCT
  Literal* = ref object of RootObj
    case kind: LiteralKind
    of LTK_NATIVE_NUMERIC: integer*: Atom
    of LTK_STRUCT: struct*: Struct

proc kind*(literal: Literal): LiteralKind = literal.kind
proc integer*(literal: Literal): Atom = literal.integer
proc struct*(literal: Literal): Struct = literal.struct
proc location*(literal: Literal): Location =
  case literal.kind:
  of LTK_NATIVE_NUMERIC: literal.integer.location
  of LTK_STRUCT: literal.struct.location

proc new_literal*(integer: Atom): Literal =
  Literal(kind: LTK_NATIVE_NUMERIC, integer: integer)

proc new_literal*(struct: Struct): Literal =
  Literal(kind: LTK_STRUCT, struct: struct)

proc `$`*(literal: Literal): string =
  case literal.kind:
  of LTK_NATIVE_NUMERIC: $(literal.integer)
  of LTK_STRUCT: $(literal.struct)

# init.nim
type Initializer* = ref object of RootObj
  module_name: Identifier
  literal: Literal
  location: Location

proc module_name*(init: Initializer): Identifier = init.module_name
proc literal*(init: Initializer): Literal = init.literal
proc location*(init: Initializer): Location = init.location

proc `$`*(init: Initializer): string =
  fmt"{init.module_name} {init.literal}"

proc new_init*(mod_name: Identifier, literal: Literal,
    location: Location): Initializer =
  Initializer(module_name: mod_name, literal: literal, location: location)

# struct.nim
type
  StructGetter* = ref object of RootObj
    target: Identifier
    field: Identifier
    location: Location

proc `$`*(struct_getter: StructGetter): string =
  fmt"{struct_getter.target}->{struct_getter.field}"

proc target*(struct_getter: StructGetter): Identifier = struct_getter.target
proc field*(struct_getter: StructGetter): Identifier = struct_getter.field

proc new_struct_getter*(target: Identifier, field: Identifier,
    location: Location): StructGetter =
  StructGetter(target: target, field: field, location: location)

# argument.nim
type
  ArgumentKind* = enum
    AK_IDENTIFIER, AK_LITERAL, AK_STRUCT_GETTER
  Argument* = ref object of RootObj
    case kind: ArgumentKind
    of AK_IDENTIFIER: name: Identifier
    of AK_LITERAL: literal: Literal
    of AK_STRUCT_GETTER: struct_getter: StructGetter

proc `$`*(arg: Argument): string =
  case arg.kind:
  of AK_IDENTIFIER: $(arg.name)
  of AK_LITERAL: $(arg.literal)
  of AK_STRUCT_GETTER: $(arg.struct_getter)

proc kind*(arg: Argument): ArgumentKind = arg.kind
proc name*(arg: Argument): Identifier = arg.name
proc literal*(arg: Argument): Literal = arg.literal
proc struct_getter*(arg: Argument): StructGetter = arg.struct_getter
proc location*(arg: Argument): Location =
  case arg.kind:
  of AK_IDENTIFIER: arg.name.location
  of AK_LITERAL: arg.literal.location
  of AK_STRUCT_GETTER: arg.struct_getter.location

proc new_argument*(literal: Literal): Argument =
  Argument(kind: AK_LITERAL, literal: literal)

proc new_argument*(name: Identifier): Argument =
  Argument(kind: AK_IDENTIFIER, name: name)

proc new_argument*(struct_getter: StructGetter): Argument =
  Argument(kind: AK_STRUCT_GETTER, struct_getter: struct_getter)

# fncall.nim
type FunctionCall* = ref object of RootObj
  module_name: Identifier
  fn_name: Identifier
  arglist: seq[Argument]
  location: Location

proc module_name*(fncall: FunctionCall): Identifier = fncall.module_name
proc fn_name*(fncall: FunctionCall): Identifier = fncall.fn_name
proc arglist*(fncall: FunctionCall): seq[Argument] = fncall.arglist
proc location*(fncall: FunctionCall): Location = fncall.location

proc new_fncall*(module_name: Identifier, fn_name: Identifier,
    arglist: seq[Argument], location: Location): FunctionCall =
  FunctionCall(module_name: module_name, fn_name: fn_name, arglist: arglist,
      location: location)

proc `$`*(fncall: FunctionCall): string =
  let arg_list_str = fncall.arglist.map(proc(x: Argument): string = $(x)).join(", ")
  fmt"{fncall.module_name}.{fncall.fn_name}({arg_list_str})"

# value.nim
type
  ExpressionKind* = enum
    EK_INIT, EK_FNCALL, EK_IDENTIFIER
  Expression* = ref object of RootObj
    location: Location
    case kind: ExpressionKind
    of EK_INIT: init: Initializer
    of EK_FNCALL: fncall: FunctionCall
    of EK_IDENTIFIER: identifier: Identifier

proc kind*(expression: Expression): ExpressionKind = expression.kind
proc init*(expression: Expression): Initializer = expression.init
proc fncall*(expression: Expression): FunctionCall = expression.fncall
proc identifier*(expression: Expression): Identifier = expression.identifier

proc safe_fncall(expression: Expression): Result[FunctionCall, string] =
  case expression.kind:
  of EK_FNCALL: return ok(expression.fncall)
  else: return err(fmt"{expression.kind} is not a function call")

proc safe_identifier(expression: Expression): Result[Identifier, string] =
  case expression.kind:
  of EK_IDENTIFIER: return ok(expression.identifier)
  else: return err(fmt"{expression.kind} is not an identifier")

proc new_value*(init: Initializer): Expression = Expression(kind: EK_INIT, init: init)
proc new_value*(fncall: FunctionCall): Expression = Expression(kind: EK_FNCALL,
    fncall: fncall)
proc new_value*(identifier: Identifier): Expression = Expression(
    kind: EK_IDENTIFIER, identifier: identifier)

proc `$`*(value: Expression): string =
  case value.kind:
  of EK_INIT: $(value.init)
  of EK_FNCALL: $(value.fncall)
  of EK_IDENTIFIER: $(value.identifier)

# assignment.nim
type Assignment* = ref object of RootObj
  dest: Identifier
  expression: Expression
  location: Location

proc dest*(assignment: Assignment): Identifier = assignment.dest
proc expression*(assignment: Assignment): Expression = assignment.expression

proc new_assignment*(dest: Identifier, expression: Expression,
    location: Location): Assignment =
  Assignment(dest: dest, expression: expression, location: location)

proc `$`*(assignment: Assignment): string =
  fmt"{assignment.dest} = {assignment.expression}"

# arg_def.nim
type ArgumentDefinition* = ref object of RootObj
  module: Identifier
  name: Identifier
  refcount: int = 0
  location: Location

proc name*(arg_def: ArgumentDefinition): Identifier = arg_def.name
proc module*(arg_def: ArgumentDefinition): Identifier = arg_def.module

proc new_arg_def*(module: Identifier, name: Identifier,
    refcount: int = 0): ArgumentDefinition =
  ArgumentDefinition(module: module, name: name, refcount: refcount)

proc clone*(arg_def: ArgumentDefinition): ArgumentDefinition =
  ArgumentDefinition(
    module: arg_def.module.clone,
    name: arg_def.name.clone,
    location: arg_def.location,
    refcount: arg_def.refcount
  )

proc `$`*(arg_def: ArgumentDefinition): string =
  fmt"{arg_def.module} {arg_def.name}"

# fn_def.nim
type FunctionDefinition* = ref object of RootObj
  name: Identifier
  returns: Identifier
  arg_def_list: seq[ArgumentDefinition]
  location: Location

proc name*(fn_def: FunctionDefinition): Identifier = fn_def.name
proc returns*(fn_def: FunctionDefinition): Identifier = fn_def.returns
proc arg_def_list*(fn_def: FunctionDefinition): seq[
    ArgumentDefinition] = fn_def.arg_def_list

proc new_fn_def*(name: Identifier, returns: Identifier,
    arg_def_list: seq[ArgumentDefinition]): FunctionDefinition =
  FunctionDefinition(name: name, returns: returns, arg_def_list: arg_def_list)

proc `$`*(fn_def: FunctionDefinition): string =
  let arglist = fn_def.arg_def_list.map(proc(x: ArgumentDefinition): string = $(
      x)).join(", ")
  fmt"fn {fn_def.name}({arglist}) returns {fn_def.returns}:"

# module_def.nim
type
  ModuleDefinitionKind* = enum
    MDK_APP, MDK_MODULE, MDK_STRUCT, MDK_UNION
  ModuleDefinition* = ref object of RootObj
    kind*: ModuleDefinitionKind
    name: Identifier
    location: Location

proc name*(module_def: ModuleDefinition): Identifier = module_def.name
proc location*(module_def: ModuleDefinition): Location = module_def.location

proc new_app_def*(name: Identifier, location: Location): ModuleDefinition =
  ModuleDefinition(kind: MDK_APP, name: name, location: location)

proc new_module_def*(name: Identifier, location: Location): ModuleDefinition =
  ModuleDefinition(kind: MDK_MODULE, name: name, location: location)

proc `$`*(module_def: ModuleDefinition): string =
  let prefix =
    case module_def.kind:
    of MDK_APP: "app"
    else: "module"
  fmt"{prefix} {module_def.name}:"

# match_def.nim
type MatchDefinition* = ref object of RootObj
  name: Identifier

proc name*(match_def: MatchDefinition): Identifier = match_def.name

proc `$`*(match_def: MatchDefinition): string =
  fmt"match {match_def.name}:"

proc new_match_def*(name: Identifier): MatchDefinition = MatchDefinition(name: name)

# case_def.nim
type CaseDefinition* = ref object of RootObj
  value: Atom

proc value*(case_def: CaseDefinition): Atom = case_def.value

proc `$`*(case_def: CaseDefinition): string =
  fmt"case {case_def.value}:"

proc new_case_def*(value: Atom): CaseDefinition = CaseDefinition(value: value)

type ElseDefinition = ref object of RootObj

proc `$`*(else_def: ElseDefinition): string = "else:"

proc new_else_def*(): ElseDefinition = ElseDefinition()

# struct_fields_def.nim

type StructFieldsMacro = ref object of RootObj
  location: Location

proc `$`*(else_def: StructFieldsMacro): string = "struct:"

proc new_struct_fields_macro*(location: Location): StructFieldsMacro = StructFieldsMacro(
    location: location)

# macro_call.nim
type
  MacroCallKind* = enum
    MCK_FN, MCK_MODULE, MCK_MATCH_DEF, MCK_CASE_DEF, MCK_ELSE_DEF, MCK_STRUCT_FIELDS_MACRO
  MacroCall* = ref object of RootObj
    case kind: MacroCallKind
    of MCK_FN: fn_def: FunctionDefinition
    of MCK_MODULE: module_def: ModuleDefinition
    of MCK_MATCH_DEF: match_def: MatchDefinition
    of MCK_CASE_DEF: case_def: CaseDefinition
    of MCK_ELSE_DEF: else_def: ElseDefinition
    of MCK_STRUCT_FIELDS_MACRO: struct_fields_macro: StructFieldsMacro

proc `$`*(macro_call: MacroCall): string =
  case macro_call.kind:
  of MCK_FN: $(macro_call.fn_def)
  of MCK_MODULE: $(macro_call.module_def)
  of MCK_MATCH_DEF: $(macro_call.match_def)
  of MCK_CASE_DEF: $(macro_call.case_def)
  of MCK_ELSE_DEF: $(macro_call.else_def)
  of MCK_STRUCT_FIELDS_MACRO: $(macro_call.struct_fields_macro)

proc kind*(macro_call: MacroCall): MacroCallKind = macro_call.kind
proc module_def*(macro_call: MacroCall): ModuleDefinition = macro_call.module_def
proc fn_def*(macro_call: MacroCall): FunctionDefinition = macro_call.fn_def
proc match_def*(macro_call: MacroCall): MatchDefinition = macro_call.match_def
proc case_def*(macro_call: MacroCall): CaseDefinition = macro_call.case_def
proc else_def*(macro_call: MacroCall): ElseDefinition = macro_call.else_def
proc struct_fields_macro*(macro_call: MacroCall): StructFieldsMacro = macro_call.struct_fields_macro

proc safe_module_def*(macro_call: MacroCall): Result[ModuleDefinition, string] =
  case macro_call.kind:
  of MCK_MODULE: ok(macro_call.module_def)
  else: return err(fmt"Macro {macro_call} is not a module")

proc safe_fn_def*(macro_call: MacroCall): Result[FunctionDefinition, string] =
  case macro_call.kind:
  of MCK_FN: ok(macro_call.fn_def)
  else: return err(fmt"Macro {macro_call} is not a function")

proc safe_match_def*(macro_call: MacroCall): Result[MatchDefinition, string] =
  case macro_call.kind:
  of MCK_MATCH_DEF: ok(macro_call.match_def)
  else: return err(fmt"Macro {macro_call} is not a match statement")

proc safe_case_def*(macro_call: MacroCall): Result[CaseDefinition, string] =
  case macro_call.kind:
  of MCK_CASE_DEF: ok(macro_call.case_def)
  else: return err(fmt"Macro {macro_call} is not a case statement")

proc safe_else_def*(macro_call: MacroCall): Result[ElseDefinition, string] =
  case macro_call.kind:
  of MCK_ELSE_DEF: ok(macro_call.else_def)
  else: return err(fmt"Macro {macro_call} is not a else statement")

proc safe_struct_fields_macro*(macro_call: MacroCall): Result[StructFieldsMacro, string] =
  case macro_call.kind:
  of MCK_STRUCT_FIELDS_MACRO: ok(macro_call.struct_fields_macro)
  else: return err(fmt"Macro {macro_call} is not a struct macro")

proc new_macro_call*(fn_def: FunctionDefinition): MacroCall =
  MacroCall(kind: MCK_FN, fn_def: fn_def)

proc new_macro_call*(module_def: ModuleDefinition): MacroCall =
  MacroCall(kind: MCK_MODULE, module_def: module_def)

proc new_macro_call*(match_def: MatchDefinition): MacroCall =
  MacroCall(kind: MCK_MATCH_DEF, match_def: match_def)

proc new_macro_call*(case_def: CaseDefinition): MacroCall =
  MacroCall(kind: MCK_CASE_DEF, case_def: case_def)

proc new_macro_call*(else_def: ElseDefinition): MacroCall =
  MacroCall(kind: MCK_ELSE_DEF, else_def: else_def)

proc new_macro_call*(struct_fields_def: StructFieldsMacro): MacroCall =
  MacroCall(kind: MCK_STRUCT_FIELDS_MACRO,
      struct_fields_macro: struct_fields_def)

# statement.nim
type
  StatementKind* = enum
    SK_ASSIGNMENT, SK_EXPR
  Statement* = ref object of RootObj
    location: Location
    case kind: StatementKind
    of SK_ASSIGNMENT: assign: Assignment
    of SK_EXPR: expression: Expression

proc `$`*(statement: Statement): string =
  case statement.kind:
  of SK_ASSIGNMENT: $(statement.assign)
  of SK_EXPR: $(statement.expression)

proc kind*(statement: Statement): StatementKind = statement.kind
proc assign*(statement: Statement): Assignment = statement.assign
proc expression*(statement: Statement): Expression = statement.expression

proc safe_assignment*(statement: Statement): Result[Assignment, string] =
  case statement.kind:
  of SK_ASSIGNMENT: ok(statement.assign)
  else: err(fmt"Statement {statement} is not an assignment")

proc safe_fncall*(statement: Statement): Result[FunctionCall, string] =
  case statement.kind:
  of SK_EXPR: statement.expression.safe_fncall
  else: err(fmt"Statement {statement} is not a function call")

proc safe_identifier*(statement: Statement): Result[Identifier, string] =
  case statement.kind:
  of SK_EXPR: statement.expression.safe_identifier
  else: err(fmt"Statement {statement} is not an identifier")

proc new_statement*(assign: Assignment): Statement =
  Statement(kind: SK_ASSIGNMENT, assign: assign)

proc new_statement*(expression: Expression): Statement =
  Statement(kind: SK_EXPR, expression: expression)

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
    LK_STATEMENT, LK_MACRO_CALL, LK_STRUCT_FIELD_DEF, LK_COMMENT, LK_EMPTY
  Line* = ref object of RootObj
    spaces: int
    case kind: LineKind
    of LK_STATEMENT: statement: Statement
    of LK_MACRO_CALL: macro_call: MacroCall
    of LK_STRUCT_FIELD_DEF: struct_field_def: ArgumentDefinition
    of LK_COMMENT: comment: Comment
    of LK_EMPTY: discard

proc `$`*(line: Line): string =
  let content =
    case line.kind:
    of LK_STATEMENT: $(line.statement)
    of LK_MACRO_CALL: $(line.macro_call)
    of LK_STRUCT_FIELD_DEF: $(line.struct_field_def)
    of LK_COMMENT: $(line.comment)
    of LK_EMPTY: ""

  (" ".repeat(line.spaces)) & content

proc kind*(line: Line): LineKind = line.kind
proc statement*(line: Line): Statement = line.statement
proc macro_call*(line: Line): MacroCall = line.macro_call
proc struct_field_def*(line: Line): ArgumentDefinition = line.struct_field_def
proc spaces*(line: Line): int = line.spaces

proc safe_struct_field_def*(line: Line): Result[ArgumentDefinition, string] =
  case line.kind:
  of LK_STRUCT_FIELD_DEF: ok(line.struct_field_def)
  else: err("Line {line} is not a struct field definition")

proc safe_statement*(line: Line): Result[Statement, string] =
  case line.kind:
  of LK_STATEMENT: ok(line.statement)
  else: err("Line {line} is not a statement")

proc safe_macro_call*(line: Line): Result[MacroCall, string] =
  case line.kind:
  of LK_MACRO_CALL: ok(line.macro_call)
  else: err("Line {line} is not a statement")

proc safe_module_def*(line: Line): Result[ModuleDefinition, string] =
  let macro_call = ? line.safe_macro_call()
  macro_call.safe_module_def()

proc safe_fn_def*(line: Line): Result[FunctionDefinition, string] =
  let macro_call = ? line.safe_macro_call()
  macro_call.safe_fn_def()

proc safe_match_def*(line: Line): Result[MatchDefinition, string] =
  let macro_call = ? line.safe_macro_call()
  macro_call.safe_match_def()

proc safe_case_def*(line: Line): Result[CaseDefinition, string] =
  let macro_call = ? line.safe_macro_call()
  macro_call.safe_case_def()

proc safe_else_def*(line: Line): Result[ElseDefinition, string] =
  let macro_call = ? line.safe_macro_call()
  macro_call.safe_else_def()

proc safe_struct_fields_macro*(line: Line): Result[StructFieldsMacro, string] =
  let macro_call = ? line.safe_macro_call()
  macro_call.safe_struct_fields_macro()

proc new_line*(statement: Statement, spaces: int): Line =
  Line(kind: LK_STATEMENT, statement: statement, spaces: spaces)

proc new_line*(macro_call: MacroCall, spaces: int): Line =
  Line(kind: LK_MACRO_CALL, macro_call: macro_call, spaces: spaces)

proc new_line*(struct_field_def: ArgumentDefinition, spaces: int): Line =
  Line(kind: LK_STRUCT_FIELD_DEF, struct_field_def: struct_field_def,
      spaces: spaces)

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
      LK_STATEMENT, LK_MACRO_CALL, LK_STRUCT_FIELD_DEF])
  return program

# parse_result.nim
type
  ParserResultKind* = enum
    PRK_ATOM,
    PRK_IDENTIFER,
    PRK_KEYWORD_ARG_VALUE,
    PRK_KEYWORD_ARG,
    PRK_STRUCT,
    PRK_LITERAL,
    PRK_INIT,
    # PRK_STRUCT_GETTER,
    PRK_ARG,
    PRK_ARGLIST,
    PRK_FNCALL,
    PRK_EXPR,
    PRK_ASSINGMENT,
    PRK_FN_MACRO,
    PRK_ARG_DEF,
    PRK_ARG_DEF_LIST,
    PRK_MODULE_MACRO,
    PRK_FIELDS_MACRO,
    PRK_MATCH_DEF_MACRO,
    PRK_CASE_DEF_MACRO,
    PRK_ELSE_DEF_MACRO,
    PRK_MACRO_CALL,
    PRK_COMMENT,
    PRK_STATEMENT,
    PRK_LINE,
    PRK_PROGRAM
  ParseResult* = ref object of RootObj
    case kind*: ParserResultKind
    of PRK_ATOM: atom*: Atom
    of PRK_IDENTIFER: identifier*: Identifier
    of PRK_KEYWORD_ARG_VALUE: kwarg_val*: KeywordArgValue
    of PRK_KEYWORD_ARG: kwarg*: KeywordArg
    of PRK_STRUCT: struct*: Struct
    of PRK_LITERAL: literal*: Literal
    of PRK_INIT: init*: Initializer
    of PRK_ARG: arg*: Argument
    of PRK_ARGLIST: arglist*: seq[Argument]
    of PRK_FNCALL: fncall*: FunctionCall
    of PRK_EXPR: expression*: Expression
    of PRK_ASSINGMENT: assign*: Assignment
    of PRK_FN_MACRO: fn_def*: FunctionDefinition
    of PRK_ARG_DEF: arg_def*: ArgumentDefinition
    of PRK_ARG_DEF_LIST: arg_def_list*: seq[ArgumentDefinition]
    of PRK_MODULE_MACRO: module_def*: ModuleDefinition
    of PRK_MATCH_DEF_MACRO: match_def*: MatchDefinition
    of PRK_CASE_DEF_MACRO: case_def*: CaseDefinition
    of PRK_ELSE_DEF_MACRO: else_def*: ElseDefinition
    of PRK_FIELDS_MACRO: struct_fields_macro*: StructFieldsMacro
    of PRK_MACRO_CALL: macro_call*: MacroCall
    of PRK_COMMENT: comment*: Comment
    of PRK_STATEMENT: statement*: Statement
    of PRK_LINE: line*: Line
    of PRK_PROGRAM: program*: Program

proc `$`*(pr: ParseResult): string =
  case pr.kind:
  of PRK_ATOM: $(pr.atom)
  of PRK_IDENTIFER: $(pr.identifier)
  of PRK_KEYWORD_ARG_VALUE: $(pr.kwarg_val)
  of PRK_KEYWORD_ARG: $(pr.kwarg)
  of PRK_STRUCT: $(pr.struct)
  of PRK_LITERAL: $(pr.literal)
  of PRK_INIT: $(pr.init)
  of PRK_ARG: $(pr.arg)
  of PRK_ARGLIST: $(pr.arglist)
  of PRK_FNCALL: $(pr.fncall)
  of PRK_EXPR: $(pr.expression)
  of PRK_ASSINGMENT: $(pr.assign)
  of PRK_FN_MACRO: $(pr.fn_def)
  of PRK_ARG_DEF: $(pr.arg_def)
  of PRK_ARG_DEF_LIST: $(pr.arg_def_list)
  of PRK_MODULE_MACRO: $(pr.module_def)
  of PRK_MATCH_DEF_MACRO: $(pr.match_def)
  of PRK_CASE_DEF_MACRO: $(pr.case_def)
  of PRK_ELSE_DEF_MACRO: $(pr.else_def)
  of PRK_FIELDS_MACRO: $(pr.struct_fields_macro)
  of PRK_MACRO_CALL: $(pr.macro_call)
  of PRK_COMMENT: $(pr.comment)
  of PRK_STATEMENT: $(pr.statement)
  of PRK_LINE: $(pr.line)
  of PRK_PROGRAM: $(pr.program)

proc to_parse_result*(atom: Atom): ParseResult =
  ParseResult(kind: PRK_ATOM, atom: atom)

proc to_parse_result*(identifier: Identifier): ParseResult =
  ParseResult(kind: PRK_IDENTIFER, identifier: identifier)

proc to_parse_result*(kwarg_val: KeywordArgValue): ParseResult =
  ParseResult(kind: PRK_KEYWORD_ARG_VALUE, kwarg_val: kwarg_val)

proc to_parse_result*(kwarg: KeywordArg): ParseResult =
  ParseResult(kind: PRK_KEYWORD_ARG, kwarg: kwarg)

proc to_parse_result*(struct: Struct): ParseResult =
  ParseResult(kind: PRK_STRUCT, struct: struct)

proc to_parse_result*(literal: Literal): ParseResult =
  ParseResult(kind: PRK_LITERAL, literal: literal)

proc to_parse_result*(init: Initializer): ParseResult =
  ParseResult(kind: PRK_INIT, init: init)

proc to_parse_result*(arg: Argument): ParseResult =
  ParseResult(kind: PRK_ARG, arg: arg)

proc to_parse_result*(arglist: seq[Argument]): ParseResult =
  ParseResult(kind: PRK_ARGLIST, arglist: arglist)

proc to_parse_result*(fncall: FunctionCall): ParseResult =
  ParseResult(kind: PRK_FNCALL, fncall: fncall)

proc to_parse_result*(expression: Expression): ParseResult =
  ParseResult(kind: PRK_EXPR, expression: expression)

proc to_parse_result*(assign: Assignment): ParseResult =
  ParseResult(kind: PRK_ASSINGMENT, assign: assign)

proc to_parse_result*(fn_def: FunctionDefinition): ParseResult =
  ParseResult(kind: PRK_FN_MACRO, fn_def: fn_def)

proc to_parse_result*(arg_def: ArgumentDefinition): ParseResult =
  ParseResult(kind: PRK_ARG_DEF, arg_def: arg_def)

proc to_parse_result*(arg_def_list: seq[ArgumentDefinition]): ParseResult =
  ParseResult(kind: PRK_ARG_DEF_LIST, arg_def_list: arg_def_list)

proc to_parse_result*(module_def: ModuleDefinition): ParseResult =
  ParseResult(kind: PRK_MODULE_MACRO, module_def: module_def)

proc to_parse_result*(match_def: MatchDefinition): ParseResult =
  ParseResult(kind: PRK_MATCH_DEF_MACRO, match_def: match_def)

proc to_parse_result*(case_def: CaseDefinition): ParseResult =
  ParseResult(kind: PRK_CASE_DEF_MACRO, case_def: case_def)

proc to_parse_result*(else_def: ElseDefinition): ParseResult =
  ParseResult(kind: PRK_ELSE_DEF_MACRO, else_def: else_def)

proc to_parse_result*(struct_fields_macro: StructFieldsMacro): ParseResult =
  ParseResult(kind: PRK_FIELDS_MACRO, struct_fields_macro: struct_fields_macro)

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
