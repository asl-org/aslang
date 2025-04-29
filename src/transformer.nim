import sequtils

import common/main

type
  ParseResultKind = enum
    PRK_NONE,
    PRK_RAW,
    PRK_IDENTIFIER,
    PRK_NATIVE_LITERAL,
    PRK_NATIVE_ARGUMENT,
    PRK_KWARG,
    PRK_STRUCT,
    PRK_LITERAL,
    PRK_INITIALIZER,
    PRK_ARGUMENT_LIST,
    PRK_FUNCTION_CALL,
    PRK_STATEMENT,
    PRK_FN_MACRO,
    PRK_ARGUMENT_DEF,
    PRK_ARGUMENT_DEF_LIST,
    PRK_MACRO,
    PRK_LINE,
    PRK_PROGRAM,

  ParseResult = ref object of RootObj
    case kind: ParseResultKind
    of PRK_RAW:
      location: Location
      raw_value: string
    of PRK_NONE: discard
    of PRK_IDENTIFIER: identifier: Identifier
    of PRK_NATIVE_LITERAL: native_literal: NativeLiteral
    of PRK_NATIVE_ARGUMENT: native_argument: NativeArgument
    of PRK_KWARG: kwarg: KeywordArgument
    of PRK_STRUCT: struct_literal: Struct
    of PRK_LITERAL: literal: Literal
    of PRK_INITIALIZER: init: Initializer
    of PRK_ARGUMENT_LIST: arglist: ArgumentList
    of PRK_FUNCTION_CALL: fncall: FunctionCall
    of PRK_STATEMENT: statement: Statement
    of PRK_FN_MACRO: fn_macro: FunctionMacro
    of PRK_ARGUMENT_DEF: arg_def: ArgumentDef
    of PRK_ARGUMENT_DEF_LIST: arg_defs: ArgumentDefList
    of PRK_MACRO: macro_header: MacroHeader
    of PRK_LINE: line: Line
    of PRK_PROGRAM: program*: Program

proc `$`*(parse_result: ParseResult): string =
  case parse_result.kind:
  of PRK_RAW: parse_result.raw_value
  of PRK_NONE: ""
  of PRK_IDENTIFIER: $(parse_result.identifier)
  of PRK_NATIVE_LITERAL: $(parse_result.native_literal)
  of PRK_NATIVE_ARGUMENT: $(parse_result.native_argument)
  of PRK_KWARG: $(parse_result.kwarg)
  of PRK_STRUCT: $(parse_result.struct_literal)
  of PRK_LITERAL: $(parse_result.literal)
  of PRK_INITIALIZER: $(parse_result.init)
  of PRK_ARGUMENT_LIST: $(parse_result.arglist)
  of PRK_FUNCTION_CALL: $(parse_result.fncall)
  of PRK_STATEMENT: $(parse_result.statement)
  of PRK_FN_MACRO: $(parse_result.fn_macro)
  of PRK_ARGUMENT_DEF: $(parse_result.arg_def)
  of PRK_ARGUMENT_DEF_LIST: $(parse_result.arg_defs)
  of PRK_MACRO: $(parse_result.macro_header)
  of PRK_LINE: $(parse_result.line)
  of PRK_PROGRAM: $(parse_result.program)

proc raw_terminal*(value: string, location: Location): ParseResult =
  ParseResult(kind: PRK_RAW, location: location, raw_value: value)

proc raw_non_terminal*(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  var value: string
  for prod in parts:
    for symbol in prod:
      for item in symbol:
        value.add($(item))
  ParseResult(kind: PRK_RAW, location: location, raw_value: value)

proc native_literal*(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  var native_literal: NativeLiteral
  if parts[0].len > 0:
    native_literal = new_native_float_literal(parts[0][0][0].raw_value, location)
  elif parts[1].len > 0:
    native_literal = new_native_int_literal(parts[1][0][0].raw_value, location)
  elif parts[2].len > 0:
    native_literal = new_native_str_literal(parts[2][0][0].raw_value, location)

  ParseResult(kind: PRK_NATIVE_LITERAL, native_literal: native_literal)

proc identifier*(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  var value: string
  for prod in parts:
    for symbol in prod:
      for item in symbol:
        value.add($(item))
  ParseResult(kind: PRK_IDENTIFIER, identifier: new_identifier(value, location))

proc native_argument*(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  var native_argument: NativeArgument
  if parts[0].len > 0:
    native_argument = new_native_literal_argument(parts[0][0][0].native_literal, location)
  elif parts[1].len > 0:
    native_argument = new_native_identifier_argument(parts[1][0][0].identifier, location)

  ParseResult(kind: PRK_NATIVE_ARGUMENT, native_argument: native_argument)

proc struct_kwarg*(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  let kwarg = new_kwarg(parts[0][0][0].identifier, parts[0][4][
      0].native_argument, location)
  ParseResult(kind: PRK_KWARG, kwarg: kwarg)

proc struct_literal*(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  let kwargs = (parts[0][2] & parts[0][3]).map(proc(
      s: ParseResult): KeywordArgument = s.kwarg)
  ParseResult(kind: PRK_STRUCT, struct_literal: new_struct(kwargs, location))

proc literal*(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  var literal: Literal
  if parts[0].len > 0:
    literal = new_native_literal(parts[0][0][0].native_literal, location)
  elif parts[1].len > 0:
    literal = new_struct_literal(parts[1][0][0].struct_literal, location)
  ParseResult(kind: PRK_LITERAL, literal: literal)

proc initializer*(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  let dest = parts[0][0][0].identifier
  let module = parts[0][4][0].identifier
  let literal = parts[0][6][0].literal
  ParseResult(kind: PRK_INITIALIZER, init: new_initializer(dest, module,
      literal, location))

proc call_argument*(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult = parts[0][0][0]

proc call_argument_list*(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  let arguments = (parts[0][2] & parts[0][3]).map(proc(
      x: ParseResult): NativeArgument = x.native_argument)
  ParseResult(kind: PRK_ARGUMENT_LIST, arglist: new_argument_list(arguments, location))

proc function_call*(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  let dest = parts[0][0][0].identifier
  let module = parts[0][4][0].identifier
  let name = parts[0][6][0].identifier
  let arglist = parts[0][8][0].arglist
  ParseResult(kind: PRK_FUNCTION_CALL, fncall: new_function_call(name, dest,
      module, arglist, location))

proc statement*(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  var statement: Statement
  if parts[0].len > 0:
    statement = new_init_statement(parts[0][0].len, parts[0][1][0].init, location)
  elif parts[1].len > 0:
    statement = new_fncall_statement(parts[1][
        0].len, parts[1][1][0].fncall, location)

  ParseResult(kind: PRK_STATEMENT, statement: statement)

proc fn_macro*(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  let name = parts[0][1][0].identifier
  let returns = parts[0][3][0].identifier
  ParseResult(kind: PRK_FN_MACRO, fn_macro: new_fn_macro(name, returns, location))

proc args_macro_argument*(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  let module = parts[0][0][0].identifier
  let name = parts[0][2][0].identifier
  ParseResult(kind: PRK_ARGUMENT_DEF, arg_def: new_args_def(name, module, location))

proc args_macro_argument_list*(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  var leading_arg_defs = parts[0][2].map(proc(
      x: ParseResult): ArgumentDef = x.arg_def)
  let module = parts[0][3][0].identifier
  let name = parts[0][5][0].identifier
  leading_arg_defs.add(new_args_def(name, module, parts[0][5][0].location))
  ParseResult(kind: PRK_ARGUMENT_DEF_LIST, arg_defs: new_args_def_list(
      leading_arg_defs, location))

proc args_macro*(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  parts[0][2][0]

proc macro_header*(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  echo parts
  if parts[0].len > 0:
    return ParseResult(kind: PRK_MACRO, macro_header: new_fn_macro_header(parts[
        0][0][0].fn_macro))
  elif parts[1].len > 0:
    return ParseResult(kind: PRK_MACRO, macro_header: new_args_macro_header(
        parts[1][0][0].arg_defs))

proc line*(parts: seq[seq[seq[ParseResult]]], location: Location): ParseResult =
  if parts[0].len > 0:
    return ParseResult(kind: PRK_LINE, line: new_statement_line(parts[0][0][0].statement))
  elif parts[1].len > 0:
    return ParseResult(kind: PRK_LINE, line: new_macro_header_line(parts[1][0][
        0].macro_header))
  else:
    return ParseResult(kind: PRK_LINE, line: new_ignorable_line())

proc program*(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  let lines = parts[0][0].map(proc(p: ParseResult): Line = p.line)
  ParseResult(kind: PRK_PROGRAM, program: new_program(lines, location))
