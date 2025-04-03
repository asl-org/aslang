import results, strformat, strutils, sequtils

import common

type Cursor = object
  content: seq[Token]
  index: int
  checkpoints: seq[int]

type
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

proc commit(cursor: var Cursor): Cursor =
  discard cursor.checkpoints.pop()
  return cursor

proc expect[T](cursor: var Cursor, parser_spec: ParserSpec[T]): Result[T, string] =
  cursor = ? cursor.pin(parser_spec.expected)
  let maybe_parsed = parser_spec.rule(cursor)
  if maybe_parsed.is_err: return err(cursor.rollback(parser_spec.expected))
  cursor = cursor.commit()
  return ok(maybe_parsed.get)

proc expect_any[T](cursor: var Cursor, parser_spec: ParserSpec[T]): Result[seq[
    T], string] =
  var maybe_parsed = cursor.expect(parser_spec)
  var items: seq[T] = @[]
  while maybe_parsed.is_ok():
    items.add(maybe_parsed.get)
    maybe_parsed = cursor.expect(parser_spec)
  return ok(items)

proc expect_at_least_one[T](cursor: var Cursor, parser_spec: ParserSpec[
    T]): Result[seq[T], string] =
  var first = ? cursor.expect(parser_spec)
  var items = ? cursor.expect_any(parser_spec)
  return ok(@[first] & items)

proc expect_at_most_one[T](cursor: var Cursor, parser_spec: ParserSpec[
    T]): Result[seq[T], string] =
  var items: seq[T] = @[]
  var maybe_parsed = cursor.expect(parser_spec)
  if maybe_parsed.is_ok(): items.add(maybe_parsed.get)
  return ok(items)

proc expect_one_of[T](cursor: var Cursor, parser_specs: seq[ParserSpec[
    T]]): Result[T, string] =
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

const new_line_parser_spec = ParserSpec[Token](expected: "new line",
    rule: new_line_spec)

proc space_spec(cursor: var Cursor): Result[Token, string] =
  let head = cursor.head()
  if head.kind != TokenKind.TK_SPACE: return err("")
  cursor = cursor.move()
  return ok(head)

const space_parser_spec = ParserSpec[Token](expected: "space", rule: space_spec)

proc period_spec(cursor: var Cursor): Result[Token, string] =
  let head = cursor.head()
  if head.kind != TokenKind.TK_PERIOD: return err("")
  cursor = cursor.move()
  return ok(head)

const period_parser_spec = ParserSpec[Token](expected: "period",
    rule: period_spec)

proc underscore_spec(cursor: var Cursor): Result[Token, string] =
  let head = cursor.head()
  if head.kind != TokenKind.TK_UNDERSCORE: return err("")
  cursor = cursor.move()
  return ok(head)

const underscore_parser_spec = ParserSpec[Token](expected: "underscore",
    rule: underscore_spec)

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

const open_parenthesis_parser_spec = ParserSpec[Token](
    expected: "open parethesis", rule: open_parenthesis_spec)

proc close_parenthesis_spec(cursor: var Cursor): Result[Token, string] =
  let head = cursor.head()
  if head.kind != TokenKind.TK_CLOSE_PARENTHESIS: return err("")
  cursor = cursor.move()
  return ok(head)

const close_parenthesis_parser_spec = ParserSpec[Token](
    expected: "close parenthesis", rule: close_parenthesis_spec)

proc alphabets_spec(cursor: var Cursor): Result[Token, string] =
  let head = cursor.head()
  if head.kind != TokenKind.TK_ALPHABETS: return err("")
  cursor = cursor.move()
  return ok(head)

const alphabets_parser_spec = ParserSpec[Token](expected: "alphabets",
    rule: alphabets_spec)

proc digits_spec(cursor: var Cursor): Result[Token, string] =
  let head = cursor.head()
  if head.kind != TokenKind.TK_DIGITS: return err("")
  cursor = cursor.move()
  return ok(head)

const digits_parser_spec = ParserSpec[Token](expected: "digits",
    rule: digits_spec)

proc identifier_head_spec(cursor: var Cursor): Result[Token, string] =
  return cursor.expect_one_of(@[
    underscore_parser_spec,
    alphabets_parser_spec,
  ])

const identifier_head_parser_spec = ParserSpec[Token](
    expected: "identifier head", rule: identifier_head_spec)

proc identifier_tail_spec(cursor: var Cursor): Result[Token, string] =
  return cursor.expect_one_of(@[
    underscore_parser_spec,
    alphabets_parser_spec,
    digits_parser_spec,
  ])

const identifier_tail_parser_spec = ParserSpec[Token](
    expected: "identifier tail", rule: identifier_tail_spec)

proc identifier_spec(cursor: var Cursor): Result[Identifier, string] =
  let id_head = ? cursor.expect(identifier_head_parser_spec)
  var id_tail = ? cursor.expect_any(identifier_tail_parser_spec)
  let id_name = (@[id_head] & id_tail).map(proc(
      t: Token): string = t.symbol).join("")
  return ok(Identifier(name: id_name, location: id_head.location))

const identifier_parser_spec = ParserSpec[Identifier](expected: "identifier",
    rule: identifier_spec)

proc leading_datatype_spec(cursor: var Cursor): Result[Identifier, string] =
  var dt_head = ? cursor.expect(identifier_parser_spec)
  var period = ? cursor.expect(period_parser_spec)
  discard period
  return ok(dt_head)

const leading_datatype_parser_spec = ParserSpec[Identifier](
    expected: "leading datatype", rule: leading_datatype_spec)

proc trailing_datatype_spec(cursor: var Cursor): Result[Identifier, string] =
  cursor.expect(identifier_parser_spec)

const trailing_datatype_parser_spec = ParserSpec[Identifier](
    expected: "trailing datatype", rule: trailing_datatype_spec)

proc datatype_spec(cursor: var Cursor): Result[Datatype, string] =
  var dt_leading: seq[Identifier] = ? cursor.expect_any(leading_datatype_parser_spec)
  var dt_trailing: Identifier = ? cursor.expect(trailing_datatype_parser_spec)
  dt_leading.add(dt_trailing)
  let name = dt_leading.map(proc(d: Identifier): string = d.name).join(".")
  return ok(Datatype(name: name, location: dt_leading[0].location))

const datatype_parser_spec = ParserSpec[DataType](expected: "datatype",
    rule: datatype_spec)

proc integer_literal_spec(cursor: var Cursor): Result[Literal, string] =
  let integer = ? cursor.expect(digits_parser_spec)
  let literal = Literal(kind: LiteralKind.LK_INTEGER, value: integer.symbol,
      location: cursor.head.location)
  return ok(literal)

const integer_literal_parser_spec = ParserSpec[Literal](
    expected: "integer literal", rule: integer_literal_spec)

proc float_literal_spec(cursor: var Cursor): Result[Literal, string] =
  let first_half = ? cursor.expect(digits_parser_spec)
  let period = ? cursor.expect(period_parser_spec)
  let second_half = ? cursor.expect(digits_parser_spec)
  let float_value = first_half.symbol & period.symbol & second_half.symbol

  let literal = Literal(kind: LiteralKind.LK_FLOAT, value: float_value,
      location: cursor.head.location)
  return ok(literal)

const float_literal_parser_spec = ParserSpec[Literal](
    expected: "float literal", rule: float_literal_spec)

proc literal_spec(cursor: var Cursor): Result[Literal, string] =
  cursor.expect_one_of(@[
    float_literal_parser_spec,
    integer_literal_parser_spec,
  ])

const literal_parser_spec = ParserSpec[Literal](expected: "literal",
    rule: literal_spec)

proc initializer_spec(cursor: var Cursor): Result[Initializer, string] =
  let datatype = ? cursor.expect(datatype_parser_spec)
  var space = ? cursor.expect_at_least_one(space_parser_spec)
  let variable_id = ? cursor.expect(identifier_parser_spec)
  space = ? cursor.expect_any(space_parser_spec)
  let equal = ? cursor.expect(equal_parser_spec)
  discard equal
  space = ? cursor.expect_any(space_parser_spec)
  let literal = ? cursor.expect(literal_parser_spec)
  space = ? cursor.expect_any(space_parser_spec)
  let new_line = ? cursor.expect(new_line_parser_spec)
  discard new_line
  let variable = Variable(datatype: datatype, name: variable_id.name)
  let initializer = Initializer(variable: variable, literal: literal,
      location: datatype.location)
  return ok(initializer)

const initializer_parser_spec = ParserSpec[Initializer](expected: "initializer",
    rule: initializer_spec)

proc argument_identifier_spec(cursor: var Cursor): Result[Argument, string] =
  let identifier = ? cursor.expect(identifier_parser_spec)
  let argument = Argument(kind: ArgumentKind.AK_IDENTIFIER,
      identifier: identifier, location: identifier.location)
  ok(argument)

const argument_identifier_parser_spec = ParserSpec[Argument](
    expected: "argument identifier", rule: argument_identifier_spec)

proc argument_literal_spec(cursor: var Cursor): Result[Argument, string] =
  let literal = ? cursor.expect(literal_parser_spec)
  let argument = Argument(kind: ArgumentKind.AK_LITERAL,
      literal: literal, location: literal.location)
  ok(argument)

const argument_literal_parser_spec = ParserSpec[Argument](
    expected: "argument literal", rule: argument_literal_spec)

proc argument_spec(cursor: var Cursor): Result[Argument, string] =
  cursor.expect_one_of(@[
    argument_identifier_parser_spec,
    argument_literal_parser_spec,
  ])

const argument_parser_spec = ParserSpec[Argument](expected: "argument",
    rule: argument_spec)

proc leading_argument_spec(cursor: var Cursor): Result[Argument, string] =
  var spaces = ? cursor.expect_any(space_parser_spec)
  let arg = ? cursor.expect(argument_parser_spec)
  spaces = ? cursor.expect_any(space_parser_spec)
  let comma = ? cursor.expect(comma_parser_spec)
  discard comma
  return ok(arg)

const leading_argument_parser_spec = ParserSpec[Argument](
    expected: "leading argument", rule: leading_argument_spec)

proc trailing_argument_spec(cursor: var Cursor): Result[Argument, string] =
  var spaces = ? cursor.expect_any(space_parser_spec)
  let arg = ? cursor.expect(argument_parser_spec)
  spaces = ? cursor.expect_any(space_parser_spec)
  return ok(arg)

const trailing_argument_parser_spec = ParserSpec[Argument](
    expected: "trailing argument", rule: trailing_argument_spec)

proc argument_list_spec(cursor: var Cursor): Result[ArgumentList, string] =
  let open_paren = ? cursor.expect(open_parenthesis_parser_spec)
  let leading_args = ? cursor.expect_any(leading_argument_parser_spec)
  let trailing_arg = ? cursor.expect(trailing_argument_parser_spec)
  let close_paren = ? cursor.expect(close_parenthesis_parser_spec)
  discard close_paren
  ok(ArgumentList(args: leading_args & @[trailing_arg],
      location: open_paren.location))

const argument_list_parser_spec = ParserSpec[ArgumentList](
    expected: "argument list", rule: argument_list_spec)

proc function_call_spec(cursor: var Cursor): Result[FunctionCall, string] =
  let variable = ? cursor.expect(identifier_parser_spec)
  var spaces = ? cursor.expect_any(space_parser_spec)
  let equal = ? cursor.expect(equal_parser_spec)
  discard equal
  spaces = ? cursor.expect_any(space_parser_spec)
  let function_name = ? cursor.expect(identifier_parser_spec)
  spaces = ? cursor.expect_any(space_parser_spec)
  let arglist = ? cursor.expect(argument_list_parser_spec)
  spaces = ? cursor.expect_any(space_parser_spec)
  let new_line = ? cursor.expect_at_least_one(new_line_parser_spec)
  discard new_line
  let fncall = FunctionCall(variable: variable, name: function_name,
      arglist: arglist, location: variable.location)
  return ok(fncall)

const function_call_parser_spec = ParserSpec[FunctionCall](
    expected: "function call", rule: function_call_spec)

proc initializer_statement_spec(cursor: var Cursor): Result[Statement, string] =
  let initializer = ? cursor.expect(initializer_parser_spec)
  let statement = Statement(kind: StatementKind.SK_INIT,
      initializer: initializer, location: initializer.location)
  return ok(statement)

const initializer_statement_parser_spec = ParserSpec[Statement](
    expected: "initializer statement", rule: initializer_statement_spec)

proc function_call_statement_spec(cursor: var Cursor): Result[Statement, string] =
  let function_call = ? cursor.expect(function_call_parser_spec)
  let statement = Statement(kind: StatementKind.SK_FNCALL,
      fncall: function_call, location: function_call.location)
  return ok(statement)

const function_call_statement_parser_spec = ParserSpec[Statement](
    expected: "function call statement", rule: function_call_statement_spec)

proc statement_spec(cursor: var Cursor): Result[Statement, string] =
  return cursor.expect_one_of(@[
    initializer_statement_parser_spec,
    function_call_statement_parser_spec,
  ])

const statement_parser_spec = ParserSpec[Statement](expected: "statement",
    rule: statement_spec)

proc parse*(tokens: seq[Token]): Result[seq[Statement], string] =
  var cursor = Cursor(content: tokens)
  var statements = ? cursor.expect_at_least_one(statement_parser_spec)
  ok(statements)
