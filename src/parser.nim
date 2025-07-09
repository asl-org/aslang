import results, strformat

import blocks

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

proc expect_argument_definition(parser: Parser): Result[ArgumentDefinition, string] =
  let arg_type = ? parser.expect(TK_ID)
  discard ? parser.expect_at_least_one(TK_SPACE)
  let arg_name = ? parser.expect(TK_ID)
  ok(new_argument_definition(arg_type, arg_name))

proc expect_argument_definition_list(parser: Parser): Result[seq[
    ArgumentDefinition], string] =
  discard ? parser.expect(TK_OPAREN)
  var arg_def_list: seq[ArgumentDefinition]

  while true:
    discard parser.expect_any(TK_SPACE)
    let arg_def = ? parser.expect_argument_definition()
    arg_def_list.add(arg_def)
    discard parser.expect_any(TK_SPACE)

    let maybe_comma = parser.expect(TK_COMMA)
    if maybe_comma.is_err: break

  discard parser.expect_any(TK_SPACE)
  discard ? parser.expect(TK_CPAREN)
  ok(arg_def_list)

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

proc expect_function_call(parser: Parser): Result[FunctionCall, string] =
  let name = ? parser.expect(TK_ID)
  let maybe_period = parser.expect(TK_PERIOD)
  # MODULE function call
  if maybe_period.is_ok:
    let function_name = ? parser.expect(TK_ID)
    discard parser.expect_any(TK_SPACE)
    let arg_list = ? parser.expect_argument_list()
    return ok(new_function_call(name, function_name, arg_list))
  # LOCAL function call
  discard parser.expect_any(TK_SPACE)
  let arg_list = ? parser.expect_argument_list()
  return ok(new_function_call(name, arg_list))

proc expect_struct_init_fields(parser: Parser): Result[seq[(Token, Token)], string] =
  var fields: seq[(Token, Token)]
  while true:
    let name = ? parser.expect(TK_ID)
    discard parser.expect_any(TK_SPACE)
    discard ? parser.expect(TK_COLON)
    discard parser.expect_any(TK_SPACE)
    let value = ? parser.expect(TK_ID)
    discard parser.expect_any(TK_SPACE)
    fields.add((name, value))

    let maybe_comma = parser.expect(TK_COMMA)
    if maybe_comma.is_err: break
    discard parser.expect_any(TK_SPACE)
  ok(fields)

proc expect_struct_init(parser: Parser): Result[StructInit, string] =
  let struct = ? parser.expect(TK_ID)
  discard parser.expect_any(TK_SPACE)
  discard ? parser.expect(TK_OCURLY)
  discard parser.expect_any(TK_SPACE)
  let fields = ? parser.expect_struct_init_fields()
  discard parser.expect_any(TK_SPACE)
  discard ? parser.expect(TK_CCURLY)
  ok(new_struct_init(struct, fields))

proc expect_struct_getter(parser: Parser): Result[StructGetter, string] =
  let struct = ? parser.expect(TK_ID)
  discard ? parser.expect(TK_PERIOD)
  let field = ? parser.expect(TK_ID)
  ok(new_struct_getter(struct, field))

proc expect_statement(parser: Parser): Result[Statement, string] =
  let destination = ? parser.expect(TK_ID)
  discard parser.expect_any(TK_SPACE)
  discard ? parser.expect(TK_EQUAL)
  discard parser.expect_any(TK_SPACE)

  let start = parser.index

  let maybe_function_call = parser.expect_function_call()
  if maybe_function_call.is_ok:
    return ok(new_statement(destination, maybe_function_call.get))
  else: parser.index = start

  let maybe_struct_init = parser.expect_struct_init()
  if maybe_struct_init.is_ok:
    return ok(new_statement(destination, maybe_struct_init.get))
  else: parser.index = start

  let maybe_struct_getter = parser.expect_struct_getter()
  if maybe_struct_getter.is_ok:
    return ok(new_statement(destination, maybe_struct_getter.get))
  else: parser.index = start

  return err(fmt"{parser.location} expected a function call or struct init/getter")

proc expect_match_definition(parser: Parser): Result[MatchDefinition, string] =
  let destination = ? parser.expect(TK_ID)
  discard parser.expect_any(TK_SPACE)
  discard ? parser.expect(TK_EQUAL)
  discard parser.expect_any(TK_SPACE)
  discard ? parser.expect(TK_MATCH)
  discard ? parser.expect_at_least_one(TK_SPACE)
  let operand = ? parser.expect(TK_ID)
  discard ? parser.expect(TK_COLON)
  ok(new_match_definition(destination, operand))

proc expect_case_definition(parser: Parser): Result[CaseDefinition, string] =
  let case_token = ? parser.expect(TK_CASE)
  discard ? parser.expect_at_least_one(TK_SPACE)
  # TODO: Add float/string/struct support later.
  let value = ? parser.expect_one_of(@[TK_INTEGER])
  discard ? parser.expect(TK_COLON)
  ok(new_case_definition(value, case_token.location))

proc expect_else_definition(parser: Parser): Result[ElseDefinition, string] =
  let else_token = ? parser.expect(TK_ELSE)
  discard parser.expect_any(TK_SPACE)
  discard ? parser.expect(TK_COLON)
  ok(new_else_definition(else_token.location))

proc expect_struct_definition(parser: Parser): Result[StructDefinition, string] =
  let struct_token = ? parser.expect(TK_STRUCT)
  discard parser.expect_any(TK_SPACE)
  discard ? parser.expect(TK_COLON)
  ok(new_struct_definition(struct_token.location))

proc expect_struct_field_definition(parser: Parser): Result[ArgumentDefinition, string] =
  parser.expect_argument_definition()

proc expect_module_definition(parser: Parser): Result[ModuleDefinition, string] =
  let module_token = ? parser.expect(TK_MODULE)
  discard ? parser.expect_at_least_one(TK_SPACE)
  let name = ? parser.expect(TK_ID)
  discard parser.expect_any(TK_SPACE)
  discard ? parser.expect(TK_COLON)
  ok(new_module_definition(name, module_token.location))

proc expect_line(parser: Parser): Result[Line, string] =
  let start = parser.index

  let maybe_func_def = parser.expect_function_definition()
  if maybe_func_def.is_ok: return ok(new_line(maybe_func_def.get))
  else: parser.index = start

  let maybe_statement = parser.expect_statement()
  if maybe_statement.is_ok: return ok(new_line(maybe_statement.get))
  else: parser.index = start

  let maybe_match_def = parser.expect_match_definition()
  if maybe_match_def.is_ok: return ok(new_line(maybe_match_def.get))
  else: parser.index = start

  let maybe_case_def = parser.expect_case_definition()
  if maybe_case_def.is_ok: return ok(new_line(maybe_case_def.get))
  else: parser.index = start

  let maybe_else_def = parser.expect_else_definition()
  if maybe_else_def.is_ok: return ok(new_line(maybe_else_def.get))
  else: parser.index = start

  # module level struct block
  let maybe_struct_def = parser.expect_struct_definition()
  if maybe_struct_def.is_ok: return ok(new_line(maybe_struct_def.get))
  else: parser.index = start

  let maybe_struct_field_def = parser.expect_struct_field_definition()
  if maybe_struct_field_def.is_ok: return ok(new_line(
      maybe_struct_field_def.get))
  else: parser.index = start

  let maybe_module_def = parser.expect_module_definition()
  if maybe_module_def.is_ok: return ok(new_line(maybe_module_def.get))
  else: parser.index = start

  err(fmt"{parser.location} expected one of the following: statement, function/match/case/else/struct definition")

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
