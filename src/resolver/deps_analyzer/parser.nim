import results, strformat, options

import parser/tokenizer
export tokenizer

import parser/ast
export ast

# parser constants
const INDENT_SIZE = 2 # spaces

# NOTE: The parser assumes that the editor used to write code
# must automatically strip off the trailing spaces and also
# add the new line at the end of file if not present. This is
# a conscious choice to ensure the consistent syntax with
# minimal configuration.
type Parser = ref object of RootObj
  path: string
  tokens: seq[Token]
  index: int = 0
  indent: int
  checkpoints: seq[int]

type AtomSpec[T] = proc(parser: Parser): Result[T, string]
type BlockSpec[T] = proc(parser: Parser, indent: int): Result[T, string]

proc can_parse(parser: Parser): bool =
  parser.index < parser.tokens.len

proc peek(parser: Parser): Result[Token, string] =
  if parser.can_parse():
    ok(parser.tokens[parser.index])
  else:
    err(fmt"reached end of token stream")

proc expect[T](parser: Parser, spec: AtomSpec[T]): Result[T, string] =
  let start = parser.index
  let maybe_value = spec(parser)
  if maybe_value.is_err:
    parser.index = start
    return err(maybe_value.error)
  return maybe_value

proc expect[T](parser: Parser, spec: BlockSpec[T], indent: int): Result[
    T, string] =
  let start = parser.index
  let maybe_value = spec(parser, indent)
  if maybe_value.is_err:
    parser.index = start
    return err(maybe_value.error)
  return maybe_value

proc token_spec_util(parser: Parser, kind: TokenKind): Result[Token, string] =
  let token = ? parser.peek()
  if token.kind == kind:
    parser.index += 1
    ok(token)
  else:
    err(fmt"{token.location} expected token kind `{kind}` but found `{token.kind}`")

proc keyword_spec_util(parser: Parser, keyword: string): Result[Token, string] =
  let alphabet = ? parser.token_spec_util(TK_ALPHABETS)
  if alphabet.value == keyword:
    ok(alphabet)
  else:
    err(fmt"{alphabet.location} expected keyword `{keyword}` but found `{alphabet.value}`")

# keyword specs
proc module_keyword_spec(parser: Parser): Result[Token,
    string] = parser.keyword_spec_util("module")

proc fn_keyword_spec(parser: Parser): Result[Token,
    string] = parser.keyword_spec_util("fn")

proc match_keyword_spec(parser: Parser): Result[Token,
    string] = parser.keyword_spec_util("match")

proc case_keyword_spec(parser: Parser): Result[Token,
    string] = parser.keyword_spec_util("case")

proc else_keyword_spec(parser: Parser): Result[Token,
    string] = parser.keyword_spec_util("else")

proc struct_keyword_spec(parser: Parser): Result[Token,
    string] = parser.keyword_spec_util("struct")

proc generic_keyword_spec(parser: Parser): Result[Token,
    string] = parser.keyword_spec_util("generic")

proc comment_spec(parser: Parser): Result[Token,
    string] = parser.token_spec_util(TK_COMMENT)

# special character spec
proc colon_spec(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_COLON)

proc comma_spec(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_COMMA)

proc dot_spec(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_DOT)

proc equal_spec(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_EQUAL)

proc open_paren_bracket_spec(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_OPEN_PAREN)

proc close_paren_bracket_spec(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_CLOSE_PAREN)

proc open_curly_bracket_spec(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_OPEN_CURLY)

proc close_curly_bracket_spec(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_CLOSE_CURLY)

proc open_square_bracket_spec(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_OPEN_SQUARE)

proc close_square_bracket_spec(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_CLOSE_SQUARE)

# spaces spec
proc new_line_spec(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_NEW_LINE)

proc space_spec(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_SPACE)

# NOTE: It just consumes all the spaces and always succeeds
proc optional_space_spec(parser: Parser): Result[int, string] =
  var count = 0
  while parser.expect(space_spec).is_ok:
    count += 1
  ok(count)

proc strict_space_spec(parser: Parser): Result[int, string] =
  var count = 0
  # NOTE: Must have one strict space
  discard ? parser.expect(space_spec)
  count += 1
  while parser.expect(space_spec).is_ok:
    count += 1
  ok(count)

# NOTE: This spec is also used to consume trailing line content
proc empty_line_spec(parser: Parser): Result[void, string] =
  # NOTE: Existence of space does not matter at all.
  discard ? parser.expect(optional_space_spec)
  # NOTE: Existence of comment does not matter at all.
  discard parser.expect(comment_spec)
  # NOTE: Every line must end with a new line.
  discard ? parser.expect(new_line_spec)
  ok()

proc optional_empty_line_spec(parser: Parser): Result[int, string] =
  var count = 0
  while parser.expect(empty_line_spec).is_ok:
    count += 1
  ok(count)

proc strict_empty_line_spec(parser: Parser): Result[int, string] =
  var count = 0
  # NOTE: Must have one strict space
  ? parser.expect(empty_line_spec)
  count += 1
  while parser.expect(empty_line_spec).is_ok:
    count += 1
  ok(count)

# NOTE: Configure indent size here.
proc indent_spec(parser: Parser, indent: int): Result[int, string] =
  # NOTE: this token is the start of line
  let token = ? parser.peek()

  let spaces = ? parser.expect(optional_space_spec)
  if spaces == indent * parser.indent:
    ok(spaces)
  else:
    err(fmt"{token.location} indentation error: expected `{indent * parser.indent}` space but found `{spaces}`")

# identifier specs
proc identifier_head_spec(parser: Parser): Result[Token, string] =
  let maybe_underscore = parser.token_spec_util(TK_UNDERSCORE)
  if maybe_underscore.is_ok:
    maybe_underscore
  else:
    parser.token_spec_util(TK_ALPHABETS)

proc identifier_tail_spec(parser: Parser): Result[Token, string] =
  let maybe_id_head = parser.expect(identifier_head_spec)
  if maybe_id_head.is_ok:
    maybe_id_head
  else:
    parser.token_spec_util(TK_DIGITS)

proc identifier_spec(parser: Parser): Result[Identifier, string] =
  let id_head = ? parser.expect(identifier_head_spec)
  var name = id_head.value
  var location = id_head.location

  var maybe_id_tail = parser.expect(identifier_tail_spec)
  while maybe_id_tail.is_ok:
    name.add(maybe_id_tail.get.value)
    maybe_id_tail = parser.expect(identifier_tail_spec)

  new_identifier(name, location)

# module spec
proc module_definition_spec(parser: Parser): Result[UserModuleDefinition, string] =
  let module_keyword = ? parser.expect(module_keyword_spec)
  discard ? parser.expect(strict_space_spec)
  let name = ? parser.expect(identifier_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(colon_spec)
  ok(new_module_definition(name, module_keyword.location))

proc struct_default_definition_spec(parser: Parser): Result[
    StructDefinition, string] =
  let struct_keyword = ? parser.expect(struct_keyword_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(colon_spec)
  ok(new_struct_definition(struct_keyword.location))

proc struct_named_definition_spec(parser: Parser): Result[
    StructDefinition, string] =
  let struct_keyword = ? parser.expect(struct_keyword_spec)
  discard ? parser.expect(strict_space_spec)
  let name = ? parser.expect(identifier_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(colon_spec)
  ok(new_struct_definition(name, struct_keyword.location))

proc struct_definition_spec(parser: Parser): Result[
    StructDefinition, string] =
  let maybe_struct_default_def = parser.expect(struct_default_definition_spec)
  if maybe_struct_default_def.is_ok:
    maybe_struct_default_def
  else:
    parser.expect(struct_named_definition_spec)

proc module_ref_spec(parser: Parser): Result[ModuleRef, string] =
  let module_ref = ? parser.expect(identifier_spec)

  var maybe_open_square_bracket = parser.expect(open_square_bracket_spec)
  if maybe_open_square_bracket.is_err:
    return ok(new_module_ref(module_ref))

  var children: seq[ModuleRef]
  discard ? parser.expect(optional_space_spec)
  children.add( ? parser.expect(module_ref_spec))
  discard ? parser.expect(optional_space_spec)

  while parser.expect(comma_spec).is_ok:
    discard ? parser.expect(optional_space_spec)
    children.add( ? parser.expect(module_ref_spec))
    discard ? parser.expect(optional_space_spec)

  discard ? parser.expect(close_square_bracket_spec)
  new_module_ref(module_ref, children)

proc argument_definition_spec(parser: Parser): Result[
    ArgumentDefinition, string] =
  let module_ref = ? parser.expect(module_ref_spec)
  discard ? parser.expect(strict_space_spec)
  let name = ? parser.expect(identifier_spec)
  ok(new_argument_definition(name, module_ref))

# TODO: Fix this later.
proc struct_field_definition_spec(parser: Parser, indent: int): Result[
    ArgumentDefinition, string] =
  discard ? parser.expect(indent_spec, indent)
  let field = ? parser.expect(argument_definition_spec)
  ok(field)

proc struct_spec(parser: Parser, indent: int): Result[Struct, string] =
  discard ? parser.expect(indent_spec, indent)
  let def = ? parser.expect(struct_definition_spec)
  discard ? parser.expect(strict_empty_line_spec)

  var fields: seq[ArgumentDefinition]
  # NOTE: struct must always at least have 1 field.
  fields.add( ? parser.expect(struct_field_definition_spec, indent + 1))
  discard ? parser.expect(strict_empty_line_spec)

  var maybe_field = parser.expect(struct_field_definition_spec, indent + 1)
  while maybe_field.is_ok:
    fields.add(maybe_field.get)
    discard ? parser.expect(strict_empty_line_spec)
    maybe_field = parser.expect(struct_field_definition_spec, indent + 1)

  new_struct(def, fields)

proc argument_definition_list_spec(parser: Parser): Result[seq[
    ArgumentDefinition], string] =
  var argdefs: seq[ArgumentDefinition]
  discard ? parser.expect(open_paren_bracket_spec)
  discard ? parser.expect(optional_space_spec)
  # NOTE: Every function must have an input argument
  argdefs.add( ? parser.expect(argument_definition_spec))
  discard ? parser.expect(optional_space_spec)

  while parser.expect(comma_spec).is_ok:
    discard ? parser.expect(optional_space_spec)
    argdefs.add( ? parser.expect(argument_definition_spec))
    discard ? parser.expect(optional_space_spec)

  discard ? parser.expect(close_paren_bracket_spec)
  ok(argdefs)

proc function_definition_spec(parser: Parser, indent: int): Result[
    FunctionDefinition, string] =
  discard ? parser.expect(indent_spec, indent)
  let fn_keyword = ? parser.expect(fn_keyword_spec)

  discard ? parser.expect(strict_space_spec)
  let name = ? parser.expect(identifier_spec)

  discard ? parser.expect(optional_space_spec)
  let args = ? parser.expect(argument_definition_list_spec)

  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(colon_spec)

  discard ? parser.expect(optional_space_spec)
  let returns = ? parser.expect(module_ref_spec)

  new_function_definition(name, args, returns, fn_keyword.location)

proc sign_spec(parser: Parser): Result[Token, string] =
  let maybe_plus = parser.token_spec_util(TK_PLUS)
  if maybe_plus.is_ok:
    maybe_plus
  else:
    parser.token_spec_util(TK_MINUS)

proc unsigned_integer_spec(parser: Parser): Result[UnsignedIntegerLiteral, string] =
  # TODO: Support underscore separated values as integers as well.
  let int_value_token = ? parser.token_spec_util(TK_DIGITS)
  ok(new_unsigned_integer(int_value_token))

proc signed_integer_spec(parser: Parser): Result[SignedIntegerLiteral, string] =
  var sign = ? parser.expect(sign_spec)
  let unsigned_intvalue = ? parser.expect(unsigned_integer_spec)
  new_signed_integer(sign, unsigned_intvalue)

proc integer_spec(parser: Parser): Result[IntegerLiteral, string] =
  let maybe_unsigned_integer = parser.expect(unsigned_integer_spec)
  if maybe_unsigned_integer.is_ok:
    ok(new_integer(maybe_unsigned_integer.get))
  else:
    let signed_integer = ? parser.expect(signed_integer_spec)
    ok(new_integer(signed_integer))

proc float_spec(parser: Parser): Result[FloatLiteral, string] =
  # TODO: Improve float parsing to support scientific notation as well.
  let first = ? parser.expect(integer_spec)
  discard ? parser.expect(dot_spec)
  let second = ? parser.expect(unsigned_integer_spec)
  ok(new_float(first, second))

proc string_spec(parser: Parser): Result[StringLiteral, string] =
  let token = ? parser.token_spec_util(TK_STRING)
  new_string(token)

proc literal_spec(parser: Parser): Result[Literal, string] =
  let maybe_integer = parser.expect(integer_spec)
  if maybe_integer.is_ok:
    return ok(new_literal(maybe_integer.get))

  let maybe_float = parser.expect(float_spec)
  if maybe_float.is_ok:
    return ok(new_literal(maybe_integer.get))

  let maybe_string = parser.expect(string_spec)
  if maybe_string.is_ok:
    return ok(new_literal(maybe_string.get))

proc argument_spec(parser: Parser): Result[Argument, string] =
  let maybe_identifier = parser.expect(identifier_spec)
  if maybe_identifier.is_ok:
    ok(new_argument(maybe_identifier.get))
  else:
    let literal = ? parser.expect(literal_spec)
    ok(new_argument(literal))

proc function_ref_local_spec(parser: Parser): Result[FunctionRef, string] =
  let name = ? parser.expect(identifier_spec)
  ok(new_function_ref(name))

proc function_ref_module_spec(parser: Parser): Result[FunctionRef, string] =
  let module_ref = ? parser.expect(module_ref_spec)
  discard ? parser.expect(dot_spec)
  let name = ? parser.expect(identifier_spec)
  ok(new_function_ref(name, module_ref))

proc function_ref_spec(parser: Parser): Result[FunctionRef, string] =
  let maybe_module_fnref = parser.expect(function_ref_module_spec)
  if maybe_module_fnref.is_ok:
    maybe_module_fnref
  else:
    parser.expect(function_ref_local_spec)

proc argument_list_spec(parser: Parser): Result[seq[Argument], string] =
  discard ? parser.expect(open_paren_bracket_spec)

  var args: seq[Argument]
  discard ? parser.expect(optional_space_spec)
  # NOTE: every function call must have at least one argument
  args.add( ? parser.expect(argument_spec))
  discard ? parser.expect(optional_space_spec)

  while parser.expect(comma_spec).is_ok:
    discard ? parser.expect(optional_space_spec)
    args.add( ? parser.expect(argument_spec))
    discard ? parser.expect(optional_space_spec)

  discard ? parser.expect(close_paren_bracket_spec)
  ok(args)

proc function_call_spec(parser: Parser): Result[FunctionCall, string] =
  let fnref = ? parser.expect(function_ref_spec)
  let args = ? parser.expect(argument_list_spec)
  new_function_call(fnref, args)

proc literal_init_spec(parser: Parser): Result[LiteralInit, string] =
  let module_ref = ? parser.expect(module_ref_spec)
  discard ? parser.expect(strict_space_spec)
  let literal = ? parser.expect(literal_spec)
  ok(new_literal_init(module_ref, literal))

proc keyword_argument_spec(parser: Parser): Result[KeywordArgument, string] =
  let name = ? parser.expect(identifier_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(colon_spec)
  discard ? parser.expect(optional_space_spec)
  let value = ? parser.expect(argument_spec)
  ok(new_keyword_argument(name, value))

proc struct_ref_spec(parser: Parser): Result[StructRef, string] =
  let module = ? parser.expect(module_ref_spec)

  let maybe_dot = parser.expect(dot_spec)
  if maybe_dot.is_err:
    return ok(new_struct_ref(module))

  let struct = ? parser.expect(identifier_spec)
  ok(new_struct_ref(module, struct))

proc keyword_argument_list_spec(parser: Parser): Result[seq[KeywordArgument], string] =
  var args: seq[KeywordArgument]
  discard ? parser.expect(open_curly_bracket_spec)

  discard ? parser.expect(optional_space_spec)
  # NOTE: every struct init must have at least one keyword argument
  args.add( ? parser.expect(keyword_argument_spec))
  discard ? parser.expect(optional_space_spec)
  var maybe_comma = parser.expect(comma_spec)
  while maybe_comma.is_ok:
    discard ? parser.expect(optional_space_spec)
    args.add( ? parser.expect(keyword_argument_spec))
    discard ? parser.expect(optional_space_spec)
    maybe_comma = parser.expect(comma_spec)

  discard ? parser.expect(close_curly_bracket_spec)
  ok(args)

proc struct_init_spec(parser: Parser): Result[StructInit, string] =
  let struct_ref = ? parser.expect(struct_ref_spec)
  discard ? parser.expect(optional_space_spec)
  let kwargs = ? parser.expect(keyword_argument_list_spec)
  new_struct_init(struct_ref, kwargs)

proc initializer_spec(parser: Parser): Result[Initializer, string] =
  let maybe_literal_init = parser.expect(literal_init_spec)
  if maybe_literal_init.is_ok:
    ok(new_initializer(maybe_literal_init.get))
  else:
    let struct_init = ? parser.expect(struct_init_spec)
    ok(new_initializer(struct_init))

proc struct_get_spec(parser: Parser): Result[StructGet, string] =
  let name = ? parser.expect(identifier_spec)
  discard ? parser.expect(dot_spec)
  let field = ? parser.expect(identifier_spec)
  ok(new_struct_get(name, field))

proc expression_spec(parser: Parser): Result[Expression, string] =
  let maybe_fncall = parser.expect(function_call_spec)
  if maybe_fncall.is_ok:
    return ok(new_expression(maybe_fncall.get))

  let maybe_init = parser.expect(initializer_spec)
  if maybe_init.is_ok:
    return ok(new_expression(maybe_init.get))

  let maybe_struct_get = parser.expect(struct_get_spec)
  if maybe_struct_get.is_ok:
    return ok(new_expression(maybe_struct_get.get))
  else:
    let variable = ? parser.expect(identifier_spec)
    ok(new_expression(variable))

proc assigned_statement_spec(parser: Parser): Result[Statement, string] =
  let arg = ? parser.expect(identifier_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(equal_spec)
  discard ? parser.expect(optional_space_spec)
  let expression = ? parser.expect(expression_spec)
  ok(new_statement(arg, expression))

proc statement_spec(parser: Parser, indent: int): Result[Statement, string] =
  discard ? parser.expect(indent_spec, indent)

  let maybe_assigned_statement = parser.expect(assigned_statement_spec)
  if maybe_assigned_statement.is_ok:
    return ok(maybe_assigned_statement.get)

  let maybe_expression = parser.expect(expression_spec)
  if maybe_expression.is_ok:
    return ok(new_statement(maybe_expression.get))

proc match_definition_default_spec(parser: Parser): Result[
    MatchDefinition, string] =
  let match_keyword = ? parser.expect(match_keyword_spec)
  discard ? parser.expect(strict_space_spec)
  let operand = ? parser.expect(identifier_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(colon_spec)
  new_match_definition(operand, match_keyword.location)

proc match_definition_spec(parser: Parser): Result[MatchDefinition, string] =
  let maybe_match_def_default = parser.expect(match_definition_default_spec)
  if maybe_match_def_default.is_ok:
    return maybe_match_def_default

  let arg = ? parser.expect(identifier_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(equal_spec)
  discard ? parser.expect(optional_space_spec)
  let match_def_default = ? parser.expect(match_definition_default_spec)
  ok(new_match_definition(match_def_default, arg))

proc keyword_value_identifier_spec(parser: Parser): Result[(Identifier,
    Identifier), string] =
  let name = ? parser.expect(identifier_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(colon_spec)
  discard ? parser.expect(optional_space_spec)
  let value = ? parser.expect(identifier_spec)
  ok((name, value))

proc struct_pattern_default_spec(parser: Parser): Result[StructPattern, string] =
  let open_curly = ? parser.expect(open_curly_bracket_spec)
  discard ? parser.expect(optional_space_spec)

  var keywords: seq[(Identifier, Identifier)]
  keywords.add( ? parser.expect(keyword_value_identifier_spec))
  discard ? parser.expect(optional_space_spec)
  var maybe_comma = parser.expect(comma_spec)
  while maybe_comma.is_ok:
    discard ? parser.expect(optional_space_spec)
    keywords.add( ? parser.expect(keyword_value_identifier_spec))
    discard ? parser.expect(optional_space_spec)
    maybe_comma = parser.expect(comma_spec)

  discard ? parser.expect(close_curly_bracket_spec)
  new_struct_pattern(keywords, open_curly.location)

proc struct_pattern_named_spec(parser: Parser): Result[StructPattern, string] =
  let struct = ? parser.expect(identifier_spec)
  discard ? parser.expect(optional_space_spec)
  let struct_pattern_default = ? parser.expect(struct_pattern_default_spec)
  new_struct_pattern(struct, struct_pattern_default)

proc struct_pattern_spec(parser: Parser): Result[StructPattern, string] =
  let maybe_struct_pattern_named = parser.expect(struct_pattern_named_spec)
  if maybe_struct_pattern_named.is_ok:
    maybe_struct_pattern_named
  else:
    parser.expect(struct_pattern_default_spec)

proc case_pattern_spec(parser: Parser): Result[CasePattern, string] =
  let maybe_struct_pattern = parser.expect(struct_pattern_spec)
  if maybe_struct_pattern.is_ok:
    ok(new_case_pattern(maybe_struct_pattern.get))
  else:
    let literal = ? parser.expect(literal_spec)
    ok(new_case_pattern(literal))

proc case_definition_spec(parser: Parser): Result[CaseDefinition, string] =
  let case_keyword = ? parser.expect(case_keyword_spec)
  discard ? parser.expect(space_spec)
  discard ? parser.expect(optional_space_spec)
  let pattern = ? parser.expect(case_pattern_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(colon_spec)
  ok(new_case_definition(pattern, case_keyword.location))

proc case_spec(parser: Parser, indent: int): Result[Case, string] =
  discard ? parser.expect(indent_spec, indent)
  let case_def = ? parser.expect(case_definition_spec)
  discard ? parser.expect(optional_empty_line_spec)

  var statements: seq[Statement]
  var maybe_statement = parser.expect(statement_spec, indent + 1)
  while maybe_statement.is_ok:
    statements.add(maybe_statement.get)
    discard ? parser.expect(optional_empty_line_spec)
    maybe_statement = parser.expect(statement_spec, indent + 1)

  new_case(case_def, statements)

proc else_spec(parser: Parser, indent: int): Result[Else, string] =
  discard ? parser.expect(indent_spec, indent)

  let else_def = ? parser.expect(else_keyword_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(colon_spec)
  discard ? parser.expect(optional_empty_line_spec)

  var statements: seq[Statement]
  var maybe_statement = parser.expect(statement_spec, indent + 1)
  while maybe_statement.is_ok:
    statements.add(maybe_statement.get)
    discard ? parser.expect(optional_empty_line_spec)
    maybe_statement = parser.expect(statement_spec, indent + 1)

  new_else(statements, else_def.location)

proc simple_match_spec(parser: Parser, indent: int): Result[Match, string] =
  let match_def = ? parser.expect(match_definition_spec)
  var cases: seq[Case]

  discard ? parser.expect(optional_empty_line_spec)
  var maybe_case = parser.expect(case_spec, indent + 1)
  while maybe_case.is_ok:
    cases.add(maybe_case.get)
    discard ? parser.expect(optional_empty_line_spec)
    maybe_case = parser.expect(case_spec, indent + 1)

  var maybe_else = parser.expect(else_spec, indent + 1)
  if maybe_else.is_ok:
    return new_match(match_def, cases, maybe_else.get)

  return new_match(match_def, cases)

proc match_spec(parser: Parser, indent: int): Result[Match, string] =
  discard ? parser.expect(indent_spec, indent)
  parser.expect(simple_match_spec, indent)

proc function_step_spec(parser: Parser, indent: int): Result[FunctionStep, string] =
  # NOTE: match must be tried first due to overlapping structure of expressions.
  let maybe_match = parser.expect(match_spec, indent)
  if maybe_match.is_ok:
    ok(new_function_step(maybe_match.get))
  else:
    let statement = ? parser.expect(statement_spec, indent)
    ok(new_function_step(statement))

proc function_spec(parser: Parser, indent: int): Result[Function, string] =
  let def = ? parser.expect(function_definition_spec, indent)
  discard ? parser.expect(strict_empty_line_spec)

  var steps: seq[FunctionStep]
  # NOTE: Function must have at least 1 expression.
  steps.add( ? parser.expect(function_step_spec, indent + 1))
  discard ? parser.expect(optional_empty_line_spec)

  var maybe_expression = parser.expect(function_step_spec, indent + 1)
  while maybe_expression.is_ok:
    steps.add(maybe_expression.get)
    discard ? parser.expect(optional_empty_line_spec)
    maybe_expression = parser.expect(function_step_spec, indent + 1)

  new_function(def, steps)

proc generic_default_spec(parser: Parser, indent: int): Result[Generic, string] =
  discard ? parser.expect(indent_spec, indent)
  let generic_keyword = ? parser.expect(generic_keyword_spec)
  discard ? parser.expect(space_spec)
  discard ? parser.expect(optional_space_spec)
  let name = ? parser.expect(identifier_spec)
  ok(new_generic(name, generic_keyword.location))

proc generic_constrained_spec(parser: Parser, indent: int): Result[Generic, string] =
  discard ? parser.expect(indent_spec, indent)
  let generic_keyword = ? parser.expect(generic_keyword_spec)
  discard ? parser.expect(space_spec)
  discard ? parser.expect(optional_space_spec)
  let name = ? parser.expect(identifier_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(colon_spec)

  var defs: seq[FunctionDefinition]
  discard ? parser.expect(optional_empty_line_spec)

  var maybe_func_def = parser.expect(function_definition_spec, indent + 1)
  while maybe_func_def.is_ok:
    defs.add(maybe_func_def.get)
    discard ? parser.expect(strict_empty_line_spec)
    maybe_func_def = parser.expect(function_definition_spec, indent + 1)

  new_generic(name, defs, generic_keyword.location)

proc generic_spec(parser: Parser, indent: int): Result[Generic, string] =
  let maybe_generic_constrained = parser.expect(generic_constrained_spec, indent)
  if maybe_generic_constrained.is_ok:
    maybe_generic_constrained
  else:
    # NOTE: generic default parser must be second since it is a subset of
    # generic_named spec and therefore may result in malformed parsing.
    parser.expect(generic_default_spec, indent)

proc module_spec(parser: Parser, indent: int): Result[UserModule, string] =
  discard ? parser.expect(indent_spec, indent)
  let def = ? parser.expect(module_definition_spec)

  var generics: seq[Generic]
  while parser.can_parse():
    discard ? parser.expect(optional_empty_line_spec)

    let maybe_generic = parser.expect(generic_spec, indent + 1)
    if maybe_generic.is_ok:
      generics.add(maybe_generic.get)
    else:
      break

  var structs: seq[Struct]
  while parser.can_parse():
    discard ? parser.expect(optional_empty_line_spec)

    let maybe_struct = parser.expect(struct_spec, indent + 1)
    if maybe_struct.is_ok:
      structs.add(maybe_struct.get)
    else:
      break

  var functions: seq[Function]
  while parser.can_parse():
    discard ? parser.expect(optional_empty_line_spec)

    let maybe_function = parser.expect(function_spec, indent + 1)
    if maybe_function.is_ok:
      functions.add(maybe_function.get)
    else:
      break

  new_user_module(def, generics, structs, functions)

proc file_spec(parser: Parser): Result[ast.File, string] =
  var modules: seq[UserModule]
  var functions: seq[Function]
  while parser.can_parse():
    discard ? parser.expect(optional_empty_line_spec)

    let maybe_module = parser.expect(module_spec, 0)
    if maybe_module.is_ok:
      modules.add(maybe_module.get)
      continue

    let maybe_function = parser.expect(function_spec, 0)
    if maybe_function.is_ok:
      functions.add(maybe_function.get)
      continue

    let token = ? parser.peek()
    return err(fmt"{token.location} expected a module or function but found {token.value}")

  new_file(parser.path, modules, functions, parser.indent)

proc parse*(path: string, tokens: seq[Token]): Result[ast.File, string] =
  Parser(path: path, tokens: tokens, indent: INDENT_SIZE).expect(file_spec)
