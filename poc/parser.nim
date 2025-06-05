import results, strformat, strutils, sequtils, sets

import tokenizer
export tokenizer

type Parser = ref object of RootObj
  tokens: seq[Token]
  index: int = 0

proc location(parser: Parser): Location =
  if parser.index < parser.tokens.len:
    parser.tokens[parser.index].location
  else:
    parser.tokens[^1].location

proc expect(parser: Parser, kind: TokenKind): Result[Token, string] =
  if parser.index >= parser.tokens.len:
    return err(fmt"expected a {kind} but reached end of file")
  if parser.tokens[parser.index].kind != kind:
    return err(fmt"{parser.tokens[parser.index].location} expected a {kind} but found {parser.tokens[parser.index].kind}")

  let token = parser.tokens[parser.index]
  parser.index += 1
  return ok(token)

proc expect_any(parser: Parser, kind: TokenKind): seq[Token] =
  var tokens: seq[Token]
  var maybe_match = parser.expect(kind)
  while maybe_match.is_ok:
    tokens.add(maybe_match.get)
    maybe_match = parser.expect(kind)
  return tokens

proc expect_at_least_one(parser: Parser, kind: TokenKind): Result[seq[Token], string] =
  var tokens = @[ ? parser.expect(kind)]
  tokens.add(parser.expect_any(kind))
  return ok(tokens)

proc expect_one_of(parser: Parser, specs: seq[TokenKind]): Result[
    Token, string] =
  for kind in specs:
    let maybe_match = parser.expect(kind)
    if maybe_match.is_ok: return maybe_match
  return err(fmt"{parser.location} failed to match parse specs")

# parser specific utils
proc expect_line_end(parser: Parser): Result[void, string] =
  discard ? parser.expect_one_of(@[TK_NEWLINE, TK_EOF])
  ok()

proc expect_empty_line(parser: Parser): Result[void, string] =
  discard parser.expect_any(TK_SPACE)
  ? parser.expect_line_end()
  ok()

proc expect_comment(parser: Parser): Result[void, string] =
  discard parser.expect_any(TK_SPACE)
  discard ? parser.expect(TK_HASHTAG)

  while true:
    let maybe_line_end = parser.expect_line_end()
    if maybe_line_end.is_ok: break
    parser.index += 1

  ok()

proc expect_ignorable_line(parser: Parser): Result[void, string] =
  var maybe_empty_line = parser.expect_empty_line()
  if maybe_empty_line.is_ok: return ok()

  var maybe_comment = parser.expect_comment()
  if maybe_comment.is_ok: return ok()

  return err(fmt"{parser.location} failed to match empty line or comment")

type ArgumentDefinition* = ref object of RootObj
  arg_type*: Token
  arg_name*: Token

proc location*(arg_def: ArgumentDefinition): Location =
  arg_def.arg_type.location

proc `$`*(arg_def: ArgumentDefinition): string =
  fmt"{arg_def.arg_type} {arg_def.arg_name}"

proc new_argument_definition*(arg_type: Token,
    arg_name: Token): ArgumentDefinition =
  ArgumentDefinition(arg_type: arg_type, arg_name: arg_name)

proc expect_argument_definition(parser: Parser): Result[ArgumentDefinition, string] =
  let arg_type = ? parser.expect(TK_ID)
  discard ? parser.expect_at_least_one(TK_SPACE)
  let arg_name = ? parser.expect(TK_ID)
  ok(new_argument_definition(arg_type, arg_name))

proc expect_argument_definition_list(parser: Parser): Result[seq[
    ArgumentDefinition], string] =
  discard ? parser.expect(TK_OPAREN)
  var arg_def_list: seq[ArgumentDefinition]
  var arg_name_set = init_hashset[string]()

  while true:
    discard parser.expect_any(TK_SPACE)
    let arg_def = ? parser.expect_argument_definition()

    let arg_name = arg_def.arg_name
    if $(arg_name) in arg_name_set:
      return err(fmt"{arg_def.location} {arg_name} is defined twice")
    arg_name_set.incl($(arg_name))

    arg_def_list.add(arg_def)
    discard parser.expect_any(TK_SPACE)

    let maybe_comma = parser.expect(TK_COMMA)
    if maybe_comma.is_err: break

  discard parser.expect_any(TK_SPACE)
  discard ? parser.expect(TK_CPAREN)
  ok(arg_def_list)

type FunctionDefinition* = ref object of RootObj
  name*: Token
  arg_def_list*: seq[ArgumentDefinition]
  return_type*: Token
  location*: Location

proc `$`*(func_def: FunctionDefinition): string =
  let arg_def_list_str = func_def.arg_def_list.map_it($(it)).join(", ")
  fmt"fn {func_def.name}({arg_def_list_str}): {func_def.return_type}"

proc new_function_definition*(name: Token, arg_def_list: seq[
    ArgumentDefinition], return_type: Token,
        location: Location): FunctionDefinition =
  FunctionDefinition(name: name, arg_def_list: arg_def_list,
      return_type: return_type, location: location)

proc expect_function_definition(parser: Parser): Result[FunctionDefinition, string] =
  let fn = ? parser.expect(TK_FN)
  discard ? parser.expect_at_least_one(TK_SPACE)
  let function_name = ? parser.expect(TK_ID)
  discard parser.expect_any(TK_SPACE)
  let arg_def_list = ? parser.expect_argument_definition_list()
  discard parser.expect_any(TK_SPACE)
  discard ? parser.expect(TK_COLON)
  discard parser.expect_any(TK_SPACE)
  let return_type = ? parser.expect(TK_ID)
  ok(new_function_definition(function_name, arg_def_list, return_type, fn.location))

proc expect_argument_list(parser: Parser): Result[seq[Token], string] =
  discard ? parser.expect(TK_OPAREN)
  var arg_list: seq[Token]

  while true:
    discard parser.expect_any(TK_SPACE)
    arg_list.add( ? parser.expect_one_of(@[TK_ID, TK_STRING, TK_FLOAT, TK_INTEGER]))
    discard parser.expect_any(TK_SPACE)
    let maybe_comma = parser.expect(TK_COMMA)
    if maybe_comma.is_err: break

  discard parser.expect_any(TK_SPACE)
  discard ? parser.expect(TK_CPAREN)
  ok(arg_list)

type FunctionCall* = ref object of RootObj
  name: Token
  arg_list: seq[Token]

proc location*(function_call: FunctionCall): Location =
  function_call.name.location

proc `$`*(function_call: FunctionCall): string =
  let arg_list_str = function_call.arg_list.map_it($(it)).join(", ")
  fmt"{function_call.name}({arg_list_str})"

proc new_function_call*(name: Token, arg_list: seq[Token]): FunctionCall =
  FunctionCall(name: name, arg_list: arg_list)

proc expect_function_call(parser: Parser): Result[FunctionCall, string] =
  let name = ? parser.expect(TK_ID)
  discard parser.expect_any(TK_SPACE)
  let arg_list = ? parser.expect_argument_list()
  ok(new_function_call(name, arg_list))

type Statement* = ref object of RootObj
  destination*: Token
  function_call*: FunctionCall

proc location*(statement: Statement): Location =
  statement.destination.location

proc `$`*(statement: Statement): string =
  fmt"{statement.destination} = {statement.function_call}"

proc new_statement*(destination: Token, function_call: FunctionCall): Statement =
  Statement(destination: destination, function_call: function_call)

proc expect_statement(parser: Parser): Result[Statement, string] =
  let destination = ? parser.expect(TK_ID)
  discard parser.expect_any(TK_SPACE)
  discard ? parser.expect(TK_EQUAL)
  discard parser.expect_any(TK_SPACE)
  let function_call = ? parser.expect_function_call()
  ok(new_statement(destination, function_call))

type
  LineKind* = enum
    LK_FUNCTION_DEFINITION, LK_STATEMENT
  Line* = ref object of RootObj
    case kind*: LineKind
    of LK_FUNCTION_DEFINITION: func_def*: FunctionDefinition
    of LK_STATEMENT: statement*: Statement

proc location*(line: Line): Location =
  case line.kind:
  of LK_FUNCTION_DEFINITION: line.func_def.location
  of LK_STATEMENT: line.statement.location

proc `$`*(line: Line): string =
  case line.kind:
  of LK_FUNCTION_DEFINITION: $(line.func_def)
  of LK_STATEMENT: $(line.statement)

proc new_line*(func_def: FunctionDefinition): Line =
  Line(kind: LK_FUNCTION_DEFINITION, func_def: func_def)

proc new_line*(statement: Statement): Line =
  Line(kind: LK_STATEMENT, statement: statement)

proc expect_line(parser: Parser): Result[Line, string] =
  let maybe_func_def = parser.expect_function_definition()
  if maybe_func_def.is_ok: return ok(new_line(maybe_func_def.get))

  let maybe_statement = parser.expect_statement()
  if maybe_statement.is_ok: return ok(new_line(maybe_statement.get))

  err(fmt"{parser.location} expected a function definition or a statement")

proc parse*(tokens: seq[Token]): Result[seq[Line], string] =
  var parser = Parser(tokens: tokens)
  var lines: seq[Line]
  while parser.index < parser.tokens.len:
    # ignore empty lines/comments
    var maybe_ignorable_line = parser.expect_ignorable_line()
    while maybe_ignorable_line.is_ok:
      maybe_ignorable_line = parser.expect_ignorable_line()

    if parser.index >= parser.tokens.len: break

    # parse main line content
    discard parser.expect_any(TK_SPACE)
    lines.add( ? parser.expect_line())
  ok(lines)
