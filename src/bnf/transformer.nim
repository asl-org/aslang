import sequtils

import common

type
  ParseResultKind = enum
    PRK_NONE,
    PRK_RAW,
    PRK_IDENTIFIER,
    PRK_LITERAL,
    PRK_ARGUMENT,
    PRK_KWARG,
    PRK_STRUCT,
    PRK_INITIALIZER,
    PRK_ARGUMENT_LIST,
    PRK_FUNCTION_CALL,
    PRK_STATEMENT,
    PRK_PROGRAM,

  ParseResult = ref object of RootObj
    case kind: ParseResultKind
    of PRK_RAW:
      location: Location
      raw_value: string
    of PRK_NONE: discard
    of PRK_IDENTIFIER: identifier: Identifier
    of PRK_LITERAL: literal: Literal
    of PRK_ARGUMENT: argument: Argument
    of PRK_KWARG: kwarg: KeywordArgument
    of PRK_STRUCT: struct_literal: Struct
    of PRK_INITIALIZER: init: Initializer
    of PRK_ARGUMENT_LIST: arglist: ArgumentList
    of PRK_FUNCTION_CALL: fncall: FunctionCall
    of PRK_STATEMENT: statement: Statement
    of PRK_PROGRAM: program*: Program

proc `$`*(struct: ParseResult): string =
  case struct.kind:
  of PRK_RAW: struct.raw_value
  of PRK_NONE: ""
  of PRK_IDENTIFIER: $(struct.identifier)
  of PRK_LITERAL: $(struct.literal)
  of PRK_ARGUMENT: $(struct.argument)
  of PRK_KWARG: $(struct.kwarg)
  of PRK_STRUCT: $(struct.struct_literal)
  of PRK_INITIALIZER: $(struct.init)
  of PRK_ARGUMENT_LIST: $(struct.arglist)
  of PRK_FUNCTION_CALL: $(struct.fncall)
  of PRK_STATEMENT: $(struct.statement)
  of PRK_PROGRAM: $(struct.program)

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

proc literal*(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  var literal: Literal
  if parts[0].len > 0:
    literal = new_float_literal(parts[0][0][0].raw_value, location)
  elif parts[1].len > 0:
    literal = new_int_literal(parts[1][0][0].raw_value, location)
  elif parts[2].len > 0:
    literal = new_str_literal(parts[2][0][0].raw_value, location)

  ParseResult(kind: PRK_LITERAL, literal: literal)

proc identifier*(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  var value: string
  for prod in parts:
    for symbol in prod:
      for item in symbol:
        value.add($(item))
  ParseResult(kind: PRK_IDENTIFIER, identifier: new_identifier(value, location))

proc argument*(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  var argument: Argument
  if parts[0].len > 0:
    argument = new_literal_argument(parts[0][0][0].literal, location)
  elif parts[1].len > 0:
    argument = new_identifier_argument(parts[1][0][0].identifier, location)

  ParseResult(kind: PRK_ARGUMENT, argument: argument)

proc struct_kwarg*(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  let kwarg = new_kwarg(parts[0][0][0].identifier, parts[0][4][0].argument, location)
  ParseResult(kind: PRK_KWARG, kwarg: kwarg)

proc struct_literal*(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  let kwargs = (parts[0][2] & parts[0][3]).map(proc(
      s: ParseResult): KeywordArgument = s.kwarg)
  ParseResult(kind: PRK_STRUCT, struct_literal: new_struct(kwargs, location))

proc initializer*(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  let dest = parts[0][0][0].identifier
  let module = parts[0][4][0].identifier
  let struct = parts[0][6][0].struct_literal
  ParseResult(kind: PRK_INITIALIZER, init: new_initializer(dest, module, struct, location))

proc call_argument*(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult = parts[0][0][0]

proc call_argument_list*(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  let arguments = (parts[0][2] & parts[0][3]).map(proc(
      x: ParseResult): Argument = x.argument)
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
    statement = new_init_statement(parts[0][0][0].init, location)
  elif parts[1].len > 0:
    statement = new_fncall_statement(parts[1][0][0].fncall, location)

  ParseResult(kind: PRK_STATEMENT, statement: statement)

proc line*(parts: seq[seq[seq[ParseResult]]], location: Location): ParseResult =
  if parts[0].len > 0: parts[0][0][0] else: ParseResult(kind: PRK_NONE)

proc program*(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  let statements = parts[0][0].filter(proc(p: ParseResult): bool = p.kind !=
      PRK_NONE).map(proc(p: ParseResult): Statement = p.statement)
  ParseResult(kind: PRK_PROGRAM, program: new_program(statements, location))
