import results, strformat, strutils, sequtils

import common

type Cursor = object
  content: seq[Token]
  index: int
  checkpoints: seq[int]

type
  ParserSpecKind = enum
    PSK_TERMINAL
    PSK_RULE
  ParserSpec[T] = object
    expected: string
    rule: proc(cursor: var Cursor): Result[T, string]

proc head(cursor: Cursor): Token = cursor.content[cursor.index]
proc move(cursor: var Cursor): Cursor =
  cursor.index += 1
  return cursor

proc pin(cursor: var Cursor, expected: string): Result[Cursor, string] =
  if cursor.index >= cursor.content.len:
    return err(fmt"Expected {expected} but reached EOF")
  cursor.checkpoints.add(cursor.index)
  return ok(cursor)

proc rollback(cursor: var Cursor, expected: string): string =
  let head = cursor.head()
  cursor.index = cursor.checkpoints.pop()
  return fmt"Expected {expected} but found {head}"

proc commit[T](cursor: var Cursor, data: T): T =
  let location = cursor.checkpoints.pop()
  return data

proc expect[T](cursor: var Cursor, parser_spec: ParserSpec[T]): Result[T, string] =
  cursor = ? cursor.pin(parser_spec.expected)
  let maybe_parsed = parser_spec.rule(cursor)
  if maybe_parsed.is_err: return err(cursor.rollback(parser_spec.expected))
  return ok(cursor.commit(maybe_parsed.get))

proc expect_any[T](cursor: var Cursor, parser_spec: ParserSpec[T]): Result[seq[T], string] =
  var maybe_parsed = cursor.expect(parser_spec)
  var items: seq[T] = @[]
  while maybe_parsed.is_ok():
    items.add(maybe_parsed.get)
    maybe_parsed = cursor.expect(parser_spec)
  return ok(items)

proc expect_at_least_one[T](cursor: var Cursor, parser_spec: ParserSpec[T]): Result[seq[T], string] =
  var maybe_parsed = cursor.expect(parser_spec)
  var items: seq[T] = @[]
  while maybe_parsed.is_ok():
    items.add(maybe_parsed.get)
    maybe_parsed = cursor.expect(parser_spec)
  if len(items) == 0: return err(maybe_parsed.error)
  return ok(items)

proc expect_at_most_one[T](cursor: var Cursor, parser_spec: ParserSpec[T]): Result[seq[T], string] =
  var items: seq[T] = @[]
  var maybe_parsed = cursor.expect(parser_spec)
  if maybe_parsed.is_ok(): items.add(maybe_parsed.get)
  return ok(items)

proc expect_one_of[T](cursor: var Cursor, parser_specs: seq[ParserSpec[T]]): Result[T, string] =
  for spec in parser_specs:
    let maybe_parsed = cursor.expect(spec)
    if maybe_parsed.is_ok:
      return ok(maybe_parsed.get)
  return err("")

proc new_line_spec(cursor: var Cursor): Result[Token, string] =
  let head = cursor.head()
  if head.kind != TokenKind.TK_NEW_LINE: return err("")
  cursor = cursor.move()
  return ok(head)

const new_line_parser_spec = ParserSpec[Token](expected: "new line", rule: new_line_spec)

proc space_spec(cursor: var Cursor): Result[Token, string] =
  let head = cursor.head()
  if head.kind != TokenKind.TK_SPACE: return err("")
  cursor = cursor.move()
  return ok(head)

const space_parser_spec = ParserSpec[Token](expected: "space", rule: space_spec)

proc underscore_spec(cursor: var Cursor): Result[Token, string] =
  let head = cursor.head()
  if head.kind != TokenKind.TK_UNDERSCORE: return err("")
  cursor = cursor.move()
  return ok(head)

const underscore_parser_spec = ParserSpec[Token](expected: "underscore", rule: underscore_spec)

proc equal_spec(cursor: var Cursor): Result[Token, string] =
  let head = cursor.head()
  if head.kind != TokenKind.TK_EQUAL: return err("")
  cursor = cursor.move()
  return ok(head)

const equal_parser_spec = ParserSpec[Token](expected: "equal", rule: equal_spec)

proc comma_spec(cursor: var Cursor): Result[Token, string] =
  let head = cursor.head()
  if head.kind != TokenKind.TK_COMMA: return err("")
  cursor = cursor.move()
  return ok(head)

const comma_parser_spec = ParserSpec[Token](expected: "comma", rule: comma_spec)

proc open_parenthesis_spec(cursor: var Cursor): Result[Token, string] =
  let head = cursor.head()
  if head.kind != TokenKind.TK_OPEN_PARENTHESIS: return err("")
  cursor = cursor.move()
  return ok(head)

const open_parenthesis_parser_spec = ParserSpec[Token](expected: "open parethesis", rule: open_parenthesis_spec)

proc close_parenthesis_spec(cursor: var Cursor): Result[Token, string] =
  let head = cursor.head()
  if head.kind != TokenKind.TK_CLOSE_PARENTHESIS: return err("")
  cursor = cursor.move()
  return ok(head)

const close_parenthesis_parser_spec = ParserSpec[Token](expected: "close parenthesis", rule: close_parenthesis_spec)

proc alphabets_spec(cursor: var Cursor): Result[Token, string] =
  let head = cursor.head()
  if head.kind != TokenKind.TK_ALPHABETS: return err("")
  cursor = cursor.move()
  return ok(head)

const alphabets_parser_spec = ParserSpec[Token](expected: "alphabets", rule: alphabets_spec)

proc digits_spec(cursor: var Cursor): Result[Token, string] =
  let head = cursor.head()
  if head.kind != TokenKind.TK_DIGITS: return err("")
  cursor = cursor.move()
  return ok(head)

const digits_parser_spec = ParserSpec[Token](expected: "digits", rule: digits_spec)

proc identifier_head_spec(cursor: var Cursor): Result[Token, string] =
  return cursor.expect_one_of(@[
    underscore_parser_spec,
    alphabets_parser_spec,
  ])

const identifier_head_parser_spec = ParserSpec[Token](expected: "alphabet/underscore", rule: identifier_head_spec)

proc identifier_tail_spec(cursor: var Cursor): Result[Token, string] =
  return cursor.expect_one_of(@[
    underscore_parser_spec,
    alphabets_parser_spec,
    digits_parser_spec,
  ])

const identifier_tail_parser_spec = ParserSpec[Token](expected: "alphabet/digit/underscore", rule: identifier_tail_spec)

proc identifier_spec(cursor: var Cursor): Result[Identifier, string] =
  let id_head = ? cursor.expect(identifier_head_parser_spec)
  var id_tail = ? cursor.expect_any(identifier_tail_parser_spec)
  let id_name = (@[id_head] & id_tail).map(proc(t: Token): string = t.symbol).join("")
  return ok(Identifier(name: id_name, location: id_head.location))

const identifier_parser_spec = ParserSpec[Identifier](expected: "identifier", rule: identifier_spec)

proc datatype_spec(cursor: var Cursor): Result[Datatype, string] =
  var dt_nodes: seq[Identifier] = @[]

  var dt_head = ? cursor.expect(identifier_parser_spec)
  dt_nodes.add(dt_head)

  var dt_tail = cursor.expect(identifier_parser_spec)
  while dt_tail.is_ok:
    dt_nodes.add(dt_tail.get)
    dt_tail = cursor.expect(identifier_parser_spec)

  return ok(Datatype(refs: dt_nodes, location: dt_head.location))

const datatype_parser_spec = ParserSpec[DataType](expected: "datatype", rule: datatype_spec)

proc literal_spec(cursor: var Cursor): Result[Literal, string] =
  if cursor.head.kind != TokenKind.TK_DIGITS: return err("")

  var int_value: uint64
  try:
    int_value = parseUInt(cursor.head.symbol)
  except ValueError:
    return err(fmt"Expected an integer literal upto {high(uint64)} but found {cursor.head}")

  let literal = Literal(kind: LiteralKind.LK_INTEGER, int_value: int_value, location: cursor.head.location)
  cursor = cursor.move()
  return ok(literal)

const literal_parser_spec = ParserSpec[Literal](expected: "literal", rule: literal_spec)

proc initializer_spec(cursor: var Cursor): Result[Initializer, string] =
  let datatype = ? cursor.expect(datatype_parser_spec)
  var space = ? cursor.expect_at_least_one(space_parser_spec)
  let variable = ? cursor.expect(identifier_parser_spec)
  space = ? cursor.expect_any(space_parser_spec)
  let equal = ? cursor.expect(equal_parser_spec)
  space = ? cursor.expect_any(space_parser_spec)
  let literal = ? cursor.expect(literal_parser_spec)
  space = ? cursor.expect_any(space_parser_spec)
  let new_line = ? cursor.expect(new_line_parser_spec)
  let initializer = Initializer(datatype: datatype, variable: variable, literal: literal, location: datatype.location)
  return ok(initializer)

const initializer_parser_spec = ParserSpec[Initializer](expected: "initializer", rule: initializer_spec)

proc argument_spec(cursor: var Cursor): Result[Argument, string] =
  let maybe_identifier = cursor.expect(identifier_parser_spec)
  if maybe_identifier.is_ok():
    return ok(Argument(kind: ArgumentKind.AK_IDENTIFIER, identifier: maybe_identifier.get, location: maybe_identifier.get.location))

  let maybe_literal = cursor.expect(literal_parser_spec)
  if maybe_literal.is_ok():
    return ok(Argument(kind: ArgumentKind.AK_LITERAL, literal: maybe_literal.get, location: maybe_literal.get.location))

  return err("")

const argument_parser_spec = ParserSpec[Argument](expected: "argument", rule: argument_spec)

proc leading_argument_spec(cursor: var Cursor): Result[Argument, string] =
  var spaces = ? cursor.expect_any(space_parser_spec)
  let arg = ? cursor.expect(argument_parser_spec)
  spaces = ? cursor.expect_any(space_parser_spec)
  let comma = ? cursor.expect(comma_parser_spec)
  return ok(arg)

const leading_argument_parser_spec = ParserSpec[Argument](expected: "leading argument", rule: leading_argument_spec)

proc trailing_argument_spec(cursor: var Cursor): Result[Argument, string] =
  var spaces = ? cursor.expect_any(space_parser_spec)
  let arg = ? cursor.expect(argument_parser_spec)
  spaces = ? cursor.expect_any(space_parser_spec)
  return ok(arg)

const trailing_argument_parser_spec = ParserSpec[Argument](expected: "trailing argument", rule: trailing_argument_spec)

proc argument_list_spec(cursor: var Cursor): Result[ArgumentList, string] =
  let open_paren = ? cursor.expect(open_parenthesis_parser_spec)
  let leading_args = ? cursor.expect_any(leading_argument_parser_spec)
  let trailing_arg = ? cursor.expect(trailing_argument_parser_spec)
  let close_paren = ? cursor.expect(close_parenthesis_parser_spec)
  ok(ArgumentList(args: leading_args & @[trailing_arg], location: open_paren.location))

const argument_list_parser_spec = ParserSpec[ArgumentList](expected: "argument list", rule: argument_list_spec)

proc function_call_spec(cursor: var Cursor): Result[FunctionCall, string] =
  let variable = ? cursor.expect(identifier_parser_spec)
  var spaces = ? cursor.expect_any(space_parser_spec)
  let equal = ? cursor.expect(equal_parser_spec)
  spaces = ? cursor.expect_any(space_parser_spec)
  let function_name = ? cursor.expect(identifier_parser_spec)
  spaces = ? cursor.expect_any(space_parser_spec)
  let arglist = ? cursor.expect(argument_list_parser_spec)
  spaces = ? cursor.expect_any(space_parser_spec)
  let new_line = ? cursor.expect_at_least_one(new_line_parser_spec)
  let fncall = FunctionCall(variable: variable, name: function_name, arglist: arglist, location: variable.location)
  return ok(fncall)

const function_call_parser_spec = ParserSpec[FunctionCall](expected: "function call", rule: function_call_spec)

proc statement_spec(cursor: var Cursor): Result[Statement, string] =
  let maybe_initializer = cursor.expect(initializer_parser_spec)
  if maybe_initializer.is_ok:
    return ok(Statement(kind: StatementKind.SK_INIT, initializer: maybe_initializer.get, location: maybe_initializer.get.location))

  let maybe_function_call = cursor.expect(function_call_parser_spec)
  if maybe_function_call.is_ok:
    return ok(Statement(kind: StatementKind.SK_FNCALL, fncall: maybe_function_call.get, location: maybe_function_call.get.location))

  return err("")

const statement_parser_spec = ParserSpec[Statement](expected: "statement", rule: statement_spec)

proc parse*(tokens: seq[Token]): Result[seq[Statement], string] =
  var cursor = Cursor(content: tokens)
  var statements = ? cursor.expect_at_least_one(statement_parser_spec)
  ok(statements)