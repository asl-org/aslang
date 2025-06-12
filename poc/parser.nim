import results, strformat, strutils, sequtils, hashes

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

proc hash*(arg_def: ArgumentDefinition): Hash = arg_def.arg_type.hash

proc `$`*(arg_def: ArgumentDefinition): string =
  fmt"{arg_def.arg_type} {arg_def.arg_name}"

proc new_argument_definition*(arg_type: Token,
    arg_name: Token): ArgumentDefinition =
  ArgumentDefinition(arg_type: arg_type, arg_name: arg_name)

proc new_argument_definition*(arg_type: string,
    arg_name: string): ArgumentDefinition =
  let arg_type_token = Token(kind: TK_ID, content: arg_type, location: Location())
  let arg_name_token = Token(kind: TK_ID, content: arg_name, location: Location())
  new_argument_definition(arg_type_token, arg_name_token)

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

type FunctionDefinition* = ref object of RootObj
  name*: Token
  arg_def_list*: seq[ArgumentDefinition]
  return_type*: Token
  location*: Location

proc hash*(func_def: FunctionDefinition): Hash =
  var essence = func_def.name.hash !& func_def.location.hash
  for arg_def in func_def.arg_def_list:
    essence = essence !& arg_def.hash
  return essence

proc `$`*(func_def: FunctionDefinition): string =
  let arg_def_list_str = func_def.arg_def_list.map_it($(it)).join(", ")
  fmt"fn {func_def.name}({arg_def_list_str}): {func_def.return_type}"

proc c*(func_def: FunctionDefinition): string =
  let args_def_str = func_def.arg_def_list.map_it($(it.arg_type)).join(", ")
  fmt"{func_def.return_type} {func_def.name}({args_def_str});"

proc new_function_definition*(name: Token, arg_def_list: seq[
    ArgumentDefinition], return_type: Token,
        location: Location): FunctionDefinition =
  FunctionDefinition(name: name, arg_def_list: arg_def_list,
      return_type: return_type, location: location)

proc new_function_definition*(name: string, arg_def_list: seq[(string, string)],
    return_type: string): FunctionDefinition =
  let name_token = Token(kind: TK_ID, content: name, location: Location())
  let return_type_token = Token(kind: TK_ID, content: return_type,
      location: Location())
  let arg_def_list_token = arg_def_list.map_it(new_argument_definition(it[0], it[1]))
  new_function_definition(name_token, arg_def_list_token, return_type_token,
      Location())

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
  name*: Token
  arg_list*: seq[Token]

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

type MatchDefinition* = ref object of RootObj
  destination*: Token
  operand*: Token

proc location*(match_definition: MatchDefinition): Location =
  match_definition.destination.location

proc `$`*(match_definition: MatchDefinition): string =
  fmt"{match_definition.destination} = match {match_definition.operand}:"

proc new_match_definition*(destination: Token,
    operand: Token): MatchDefinition =
  MatchDefinition(destination: destination, operand: operand)

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

type CaseDefinition* = ref object of RootObj
  value*: Token
  location*: Location

proc `$`*(case_definition: CaseDefinition): string =
  fmt"case {case_definition.value}:"

proc new_case_definition*(value: Token, location: Location): CaseDefinition =
  CaseDefinition(value: value, location: location)

proc expect_case_definition(parser: Parser): Result[CaseDefinition, string] =
  let case_token = ? parser.expect(TK_CASE)
  discard ? parser.expect_at_least_one(TK_SPACE)
  # TODO: Add float/string/struct support later.
  let value = ? parser.expect_one_of(@[TK_INTEGER])
  discard ? parser.expect(TK_COLON)
  ok(new_case_definition(value, case_token.location))

type ElseDefinition* = ref object of RootObj
  location*: Location

proc `$`*(else_definition: ElseDefinition): string =
  fmt"else:"

proc new_else_definition*(location: Location): ElseDefinition =
  ElseDefinition(location: location)

proc expect_else_definition(parser: Parser): Result[ElseDefinition, string] =
  let else_token = ? parser.expect(TK_ELSE)
  discard parser.expect_any(TK_SPACE)
  discard ? parser.expect(TK_COLON)
  ok(new_else_definition(else_token.location))

type
  LineKind* = enum
    LK_FUNCTION_DEFINITION, LK_STATEMENT, LK_MATCH_DEFINITION,
      LK_CASE_DEFINITION, LK_ELSE_DEFINITION
  Line* = ref object of RootObj
    case kind*: LineKind
    of LK_FUNCTION_DEFINITION: func_def*: FunctionDefinition
    of LK_STATEMENT: statement*: Statement
    of LK_MATCH_DEFINITION: match_def*: MatchDefinition
    of LK_CASE_DEFINITION: case_def*: CaseDefinition
    of LK_ELSE_DEFINITION: else_def*: ElseDefinition

proc location*(line: Line): Location =
  case line.kind:
  of LK_FUNCTION_DEFINITION: line.func_def.location
  of LK_STATEMENT: line.statement.location
  of LK_MATCH_DEFINITION: line.match_def.location
  of LK_CASE_DEFINITION: line.case_def.location
  of LK_ELSE_DEFINITION: line.else_def.location

proc `$`*(line: Line): string =
  case line.kind:
  of LK_FUNCTION_DEFINITION: $(line.func_def)
  of LK_STATEMENT: $(line.statement)
  of LK_MATCH_DEFINITION: $(line.match_def)
  of LK_CASE_DEFINITION: $(line.case_def)
  of LK_ELSE_DEFINITION: $(line.else_def)

proc new_line*(func_def: FunctionDefinition): Line =
  Line(kind: LK_FUNCTION_DEFINITION, func_def: func_def)

proc new_line*(statement: Statement): Line =
  Line(kind: LK_STATEMENT, statement: statement)

proc new_line*(match_def: MatchDefinition): Line =
  Line(kind: LK_MATCH_DEFINITION, match_def: match_def)

proc new_line*(case_def: CaseDefinition): Line =
  Line(kind: LK_CASE_DEFINITION, case_def: case_def)

proc new_line*(else_def: ElseDefinition): Line =
  Line(kind: LK_ELSE_DEFINITION, else_def: else_def)

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

  err(fmt"{parser.location} expected one of the following: statement, function/match/case/else definition")

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
