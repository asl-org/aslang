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

proc expect_one_of(parser: Parser, specs: seq[TokenKind]): Result[Token, string] =
  for kind in specs:
    let maybe_match = parser.expect(kind)
    if maybe_match.is_ok: return maybe_match
  return err(fmt"{parser.location} failed to match parse specs")

# parser specific utils
proc expect_line_end(parser: Parser): Result[void, string] =
  discard ? parser.expect_one_of(@[tkNewline, tkEof])
  ok()

proc expect_empty_line(parser: Parser): Result[void, string] =
  discard parser.expect_any(tkIndent)
  ? parser.expect_line_end()
  ok()

proc expect_comment(parser: Parser): Result[void, string] =
  discard parser.expect_any(tkIndent)
  let _ = ? parser.expect(tkHashtag)
  var maybe_line_end = parser.expect_line_end()
  while not maybe_line_end.is_ok:
    parser.index += 1
    maybe_line_end = parser.expect_line_end()
  ok()

proc expect_ignorable_line(parser: Parser): Result[void, string] =
  let start = parser.index
  var maybe_empty_line = parser.expect_empty_line()
  if maybe_empty_line.is_ok: return ok()
  else: parser.index = start
  var maybe_comment = parser.expect_comment()
  if maybe_comment.is_ok: return ok()
  else: parser.index = start
  return err(fmt"{parser.location} failed to match empty line or comment")

proc expect_argument_definition(parser: Parser): Result[ArgumentDefinition, string] =
  let arg_type = ? parser.expect(tkIdentifier)
  let arg_name = ? parser.expect(tkIdentifier)
  ok(new_argument_definition(arg_type, arg_name))

proc expect_argument_definition_list(parser: Parser): Result[seq[ArgumentDefinition], string] =
  discard ? parser.expect(tkLeftParen)
  var arg_def_list: seq[ArgumentDefinition]
  while true:
    let arg_def = ? parser.expect_argument_definition()
    arg_def_list.add(arg_def)
    let maybe_comma = parser.expect(tkComma)
    if maybe_comma.is_err: break
  discard ? parser.expect(tkRightParen)
  ok(arg_def_list)

proc expect_function_definition(parser: Parser): Result[FunctionDefinition, string] =
  let fn = ? parser.expect(tkFn)
  let function_name = ? parser.expect(tkIdentifier)
  let arg_def_list = ? parser.expect_argument_definition_list()
  discard ? parser.expect(tkColon)
  let return_type = ? parser.expect(tkIdentifier)
  ok(new_function_definition(function_name, arg_def_list, return_type, fn.location))

proc expect_argument_list(parser: Parser): Result[seq[Token], string] =
  discard ? parser.expect(tkLeftParen)
  var arg_list: seq[Token]
  while true:
    arg_list.add( ? parser.expect_one_of(@[tkIdentifier, tkString, tkFloat, tkInteger]))
    let maybe_comma = parser.expect(tkComma)
    if maybe_comma.is_err: break
  discard ? parser.expect(tkRightParen)
  ok(arg_list)

proc expect_function_ref(parser: Parser): Result[FunctionRef, string] =
  var name = ? parser.expect(tkIdentifier)
  let maybe_period = parser.expect(tkDot)
  if maybe_period.is_err:
    return ok(new_function_ref(name))
  let module = name
  name = ? parser.expect(tkIdentifier)
  ok(new_function_ref(module, name))

proc expect_function_call(parser: Parser): Result[FunctionCall, string] =
  let function_ref = ? parser.expect_function_ref()
  let arg_list = ? parser.expect_argument_list()
  return ok(new_function_call(function_ref, arg_list))

proc expect_struct_init_fields(parser: Parser): Result[seq[(Token, Token)], string] =
  var fields: seq[(Token, Token)]
  while true:
    let name = ? parser.expect(tkIdentifier)
    discard ? parser.expect(tkColon)
    let value = ? parser.expect(tkIdentifier)
    fields.add((name, value))
    let maybe_comma = parser.expect(tkComma)
    if maybe_comma.is_err: break
  ok(fields)

proc expect_struct_init(parser: Parser): Result[StructInit, string] =
  let struct = ? parser.expect(tkIdentifier)
  discard ? parser.expect(tkLeftBrace)
  let fields = ? parser.expect_struct_init_fields()
  discard ? parser.expect(tkRightBrace)
  ok(new_struct_init(struct, fields))

proc expect_struct_getter(parser: Parser): Result[StructGetter, string] =
  let struct = ? parser.expect(tkIdentifier)
  discard ? parser.expect(tkDot)
  let field = ? parser.expect(tkIdentifier)
  ok(new_struct_getter(struct, field))

proc expect_literal_init(parser: Parser): Result[LiteralInit, string] =
  let arg_type = ? parser.expect(tkIdentifier)
  let arg_value = ? parser.expect(tkInteger)
  ok(new_literal_init(arg_type, arg_value))

proc expect_union_init_fields(parser: Parser): Result[seq[(Token, Token)], string] =
  var fields: seq[(Token, Token)]
  while true:
    let name = ? parser.expect(tkIdentifier)
    discard ? parser.expect(tkColon)
    let value = ? parser.expect(tkIdentifier)
    fields.add((name, value))
    let maybe_comma = parser.expect(tkComma)
    if maybe_comma.is_err: break
  ok(fields)

proc expect_union_init(parser: Parser): Result[UnionInit, string] =
  let union_name = ? parser.expect(tkIdentifier)
  discard ? parser.expect(tkDot)
  let union_field_name = ? parser.expect(tkIdentifier)
  discard ? parser.expect(tkLeftBrace)
  let fields = ? parser.expect_union_init_fields()
  discard ? parser.expect(tkRightBrace)
  ok(new_union_init(union_name, union_field_name, fields))

proc expect_expression(parser: Parser): Result[Expression, string] =
  let start = parser.index
  let maybe_function_call = parser.expect_function_call()
  if maybe_function_call.is_ok:
    return ok(new_expression(maybe_function_call.get))
  else: parser.index = start
  let maybe_struct_init = parser.expect_struct_init()
  if maybe_struct_init.is_ok:
    return ok(new_expression(maybe_struct_init.get))
  else: parser.index = start
  let maybe_union_init = parser.expect_union_init()
  if maybe_union_init.is_ok:
    return ok(new_expression(maybe_union_init.get))
  else: parser.index = start
  let maybe_struct_getter = parser.expect_struct_getter()
  if maybe_struct_getter.is_ok:
    return ok(new_expression(maybe_struct_getter.get))
  else: parser.index = start
  let maybe_literal_init = parser.expect_literal_init()
  if maybe_literal_init.is_ok:
    return ok(new_expression(maybe_literal_init.get))
  else: parser.index = start
  let maybe_variable = parser.expect(tkIdentifier)
  if maybe_variable.is_ok:
    return ok(new_expression(maybe_variable.get))
  else: parser.index = start
  return err(fmt"{parser.location} expected a function call or struct init/getter")

proc expect_assignment_statement(parser: Parser): Result[Statement, string] =
  let destination = ? parser.expect(tkIdentifier)
  discard ? parser.expect(tkEqual)
  let expression = ? parser.expect_expression()
  ok(new_statement(destination, expression))

proc expect_statement(parser: Parser): Result[Statement, string] =
  let start = parser.index
  let maybe_assignment = parser.expect_assignment_statement()
  if maybe_assignment.is_ok: return maybe_assignment
  else: parser.index = start
  let maybe_expression = parser.expect_expression()
  if maybe_expression.is_ok: return ok(new_statement(maybe_expression.get))
  else: parser.index = start
  err(fmt"{parser.location} expected a statement or expression")

proc expect_match_definition(parser: Parser): Result[MatchDefinition, string] =
  let destination = ? parser.expect(tkIdentifier)
  discard ? parser.expect(tkEqual)
  discard ? parser.expect(tkMatch)
  let operand = ? parser.expect(tkIdentifier)
  discard ? parser.expect(tkColon)
  ok(new_match_definition(destination, operand))

proc expect_pattern_fields(parser: Parser): Result[seq[(Token, Token)], string] =
  var fields: seq[(Token, Token)]
  while true:
    let name = ? parser.expect(tkIdentifier)
    discard ? parser.expect(tkColon)
    let value = ? parser.expect(tkIdentifier)
    fields.add((name, value))
    let maybe_comma = parser.expect(tkComma)
    if maybe_comma.is_err: break
  ok(fields)

proc expect_union_pattern(parser: Parser): Result[UnionPattern, string] =
  let union_field_def_name = ? parser.expect(tkIdentifier)
  discard ? parser.expect(tkLeftBrace)
  let union_field_def_fields = ? parser.expect_pattern_fields()
  discard ? parser.expect(tkRightBrace)
  ok(new_union_pattern(union_field_def_name, union_field_def_fields))

proc expect_case_pattern(parser: Parser): Result[Pattern, string] =
  let start = parser.index
  let maybe_union_pattern = parser.expect_union_pattern()
  if maybe_union_pattern.is_ok:
    return ok(new_pattern(maybe_union_pattern.get))
  else: parser.index = start
  let value = ? parser.expect_one_of(@[tkInteger])
  ok(new_pattern(value))

proc expect_case_definition(parser: Parser): Result[CaseDefinition, string] =
  let case_token = ? parser.expect(tkCase)
  let pattern = ? parser.expect_case_pattern()
  discard ? parser.expect(tkColon)
  ok(new_case_definition(pattern, case_token.location))

proc expect_else_definition(parser: Parser): Result[ElseDefinition, string] =
  let else_token = ? parser.expect(tkElse)
  discard ? parser.expect(tkColon)
  ok(new_else_definition(else_token.location))

proc expect_struct_definition(parser: Parser): Result[StructDefinition, string] =
  let struct_token = ? parser.expect(tkStruct)
  discard ? parser.expect(tkColon)
  ok(new_struct_definition(struct_token.location))

proc expect_struct_field_definition(parser: Parser): Result[ArgumentDefinition, string] =
  parser.expect_argument_definition()

proc expect_union_definition(parser: Parser): Result[UnionDefinition, string] =
  let union_token = ? parser.expect(tkUnion)
  discard ? parser.expect(tkColon)
  ok(new_union_definition(union_token.location))

proc expect_generic_definition(parser: Parser): Result[Generic, string] =
  let generic_token = ? parser.expect(tkGeneric)
  let name = ? parser.expect(tkIdentifier)
  let maybe_extended = parser.expect(tkColon)
  if maybe_extended.is_ok:
    ok(new_extended_generic(name, generic_token.location))
  else:
    ok(new_generic(name, generic_token.location))

proc expect_union_field_definition(parser: Parser): Result[UnionFieldDefinition, string] =
  let name = ? parser.expect(tkIdentifier)
  discard ? parser.expect(tkColon)
  ok(new_union_field_definition(name))

proc expect_module_definition(parser: Parser): Result[ModuleDefinition, string] =
  let module_token = ? parser.expect(tkModule)
  let name = ? parser.expect(tkIdentifier)
  discard ? parser.expect(tkColon)
  ok(new_module_definition(name, module_token.location))

proc expect_line(parser: Parser): Result[Line, string] =
  let indents = parser.expect_any(tkIndent).len
  let start = parser.index
  let maybe_func_def = parser.expect_function_definition()
  if maybe_func_def.is_ok: return ok(new_line(indents, maybe_func_def.get))
  else: parser.index = start
  let maybe_match_def = parser.expect_match_definition()
  if maybe_match_def.is_ok: return ok(new_line(indents, maybe_match_def.get))
  else: parser.index = start
  let maybe_case_def = parser.expect_case_definition()
  if maybe_case_def.is_ok: return ok(new_line(indents, maybe_case_def.get))
  else: parser.index = start
  let maybe_else_def = parser.expect_else_definition()
  if maybe_else_def.is_ok: return ok(new_line(indents, maybe_else_def.get))
  else: parser.index = start
  let maybe_struct_def = parser.expect_struct_definition()
  if maybe_struct_def.is_ok: return ok(new_line(indents, maybe_struct_def.get))
  else: parser.index = start
  let maybe_struct_field_def = parser.expect_struct_field_definition()
  if maybe_struct_field_def.is_ok: return ok(new_line(indents, maybe_struct_field_def.get))
  else: parser.index = start
  let maybe_union_def = parser.expect_union_definition()
  if maybe_union_def.is_ok: return ok(new_line(indents, maybe_union_def.get))
  else: parser.index = start
  let maybe_generic_def = parser.expect_generic_definition()
  if maybe_generic_def.is_ok: return ok(new_line(indents, maybe_generic_def.get))
  else: parser.index = start
  let maybe_union_field_def = parser.expect_union_field_definition()
  if maybe_union_field_def.is_ok: return ok(new_line(indents, maybe_union_field_def.get))
  else: parser.index = start
  let maybe_module_def = parser.expect_module_definition()
  if maybe_module_def.is_ok: return ok(new_line(indents, maybe_module_def.get))
  else: parser.index = start
  let maybe_statement = parser.expect_statement()
  if maybe_statement.is_ok: return ok(new_line(indents, maybe_statement.get))
  else: parser.index = start
  err(fmt"{parser.location} expected one of the following: statement, function/match/case/else/struct definition")

proc parse*(tokens: seq[Token]): Result[seq[Line], string] =
  var parser = Parser(tokens: tokens)
  var lines: seq[Line]
  while parser.index < parser.tokens.len:
    var maybe_ignorable_line = parser.expect_ignorable_line()
    while maybe_ignorable_line.is_ok:
      maybe_ignorable_line = parser.expect_ignorable_line()
    if parser.index >= parser.tokens.len: break
    lines.add( ? parser.expect_line())
  ok(lines)
