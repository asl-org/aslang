import results, strformat

import tokenizer
export tokenizer

# ast node constants
const MAX_IDENTIFIER_LENGTH* = 256
const MAX_TYPE_CHILDREN_COUNT* = 8
const MAX_ARGS_LENGTH* = 32
const MAX_BRANCH_LENGTH* = 256

# parser constants
const INDENT_SIZE* = 2 # spaces

type ParserError* = ref object of RootObj
  location: Location
  message: string

proc `<`*(self: ParserError, other: ParserError): bool = self.location < other.location
proc `>`*(self: ParserError, other: ParserError): bool = self.location > other.location
proc `==`*(self: ParserError, other: ParserError): bool = self.location == other.location
proc `$`*(err: ParserError): string = fmt"[ERROR] {err.location} - {err.message}"

proc new_parser_error(location: Location, message: string): ParserError =
  ParserError(location: location, message: message)

proc err_parser_reached_eof*(location: Location): ParserError =
  new_parser_error(location, "parser reached end of file")

proc err_parser_expectation_mismatch*(location: Location, expected: string,
    found: string): ParserError =
  new_parser_error(location, fmt"expected `{expected}` found `{found}`")

proc err_parser_indentation_error*(location: Location, expected: int,
    found: int): ParserError =
  new_parser_error(location, fmt"expected `{expected}` space(s) but found `{found}` space(s)")

proc err_parser_empty_identifier*(location: Location): ParserError =
  new_parser_error(location, "empty identifiers are not allowed")

proc err_parser_identifier_too_long*(location: Location,
    length: int): ParserError =
  new_parser_error(location, fmt"{location} identifier length `{length}` exceeded maximum identifier length of `{MAX_IDENTIFIER_LENGTH}`")

proc err_parser_expected_sign*(location: Location, found: string): ParserError =
  new_parser_error(location, fmt"expected a sign `+` or `-` but found {found}")

proc err_parser_empty_generic_list*(location: Location): ParserError =
  new_parser_error(location, "nested module refs can not have empty child module ref list")

proc err_parser_generic_list_too_long*(location: Location,
    children: int): ParserError =
  new_parser_error(location, fmt"a nested module ref only supports upto `{MAX_TYPE_CHILDREN_COUNT}` children types but `{children}` were given")

proc err_parser_empty_arg_list*(location: Location): ParserError =
  new_parser_error(location, "function argument list can not be empty")

proc err_parser_arg_list_too_long*(location: Location, args: int): ParserError =
  new_parser_error(location, fmt"function argument length `{args}` exceeded maximum argument length `{MAX_ARGS_LENGTH}`")

proc err_parser_arg_already_defined*(location: Location, arg: string,
    previous: Location): ParserError =
  new_parser_error(location, fmt"argument `{arg}` is already defined at {previous}")

proc err_parser_empty_struct*(location: Location): ParserError =
  new_parser_error(location, "struct block can not be empty")

proc err_parser_struct_too_long*(location: Location, fields: int): ParserError =
  new_parser_error(location, fmt"struct field length `{fields}` exceeded maximum field length `{MAX_ARGS_LENGTH}`")

proc err_parser_empty_union_branch*(location: Location): ParserError =
  new_parser_error(location, "union branch block can not be empty")

proc err_parser_union_branch_too_long*(location: Location,
    fields: int): ParserError =
  new_parser_error(location, fmt"union branch field length `{fields}` exceeded maximum field length `{MAX_ARGS_LENGTH}`")

proc err_parser_empty_union*(location: Location): ParserError =
  new_parser_error(location, "union block can not be empty")

proc err_parser_union_too_long*(location: Location,
    branches: int): ParserError =
  new_parser_error(location, fmt"union branch length `{branches}` exceeded maximum field length `{MAX_BRANCH_LENGTH}`")

proc err_parser_struct_conversion_error*(location: Location): ParserError =
  new_parser_error(location, fmt"[UNREACHABLE] named struct pattern can not be converted to another named struct pattern")

proc err_parser_empty_case*(location: Location): ParserError =
  new_parser_error(location, fmt"case block must have at least one statement")

proc err_parser_empty_else*(location: Location): ParserError =
  new_parser_error(location, fmt"elseerr_parser_empty_else block must have at least one statement")

proc err_parser_empty_match*(location: Location): ParserError =
  new_parser_error(location, fmt"match block must have at least 2 case blocks")

proc err_parser_empty_match_with_else*(location: Location): ParserError =
  new_parser_error(location, fmt"match block must have at least 1 case block")

proc err_parser_empty_generic_constraint_list*(location: Location,
    generic: string): ParserError =
  new_parser_error(location, fmt"generic `{generic}` must have at least one constraint")

proc err_parser_generic_constraint_already_defined*(location: Location,
    constraint: string, previous: Location): ParserError =
  new_parser_error(location, fmt"generic constraint `{constraint}` is already defined at {previous}")

proc err_parser_empty_function*(location: Location, name: string): ParserError =
  new_parser_error(location, fmt"function `{name}` must have at least one statement")

proc err_parser_empty_module*(location: Location, name: string): ParserError =
  new_parser_error(location, fmt"module `{name}` can not be empty")

proc err_parser_empty_module_with_generics*(location: Location,
    name: string): ParserError =
  new_parser_error(location, fmt"module `{name}` can not only contain generics")

proc err_parser_generic_already_defined*(location: Location, name: string,
    previous: Location): ParserError =
  new_parser_error(location, fmt"generic `{name}` is already defined at {previous}")

proc err_parser_struct_already_defined*(location: Location, name: string,
    previous: Location): ParserError =
  new_parser_error(location, fmt"struct `{name}` is already defined at {previous}")

proc err_parser_function_already_defined*(location: Location, name: string,
    previous: Location): ParserError =
  new_parser_error(location, fmt"function `{name}` is already defined at {previous}")

proc err_parser_struct_generic_conflict*(struct_location: Location,
    struct_name: string, generic_location: Location,
    generic_name: string): ParserError =
  new_parser_error(struct_location, fmt"struct `{struct_name}` name conflicts with generic `{generic_name}` at {generic_location}")

proc err_parser_function_generic_conflict*(function_location: Location,
    function_name: string, generic_location: Location,
    generic_name: string): ParserError =
  new_parser_error(function_location, fmt"function `{function_name}` name conflicts with generic `{generic_name}` at {generic_location}")

proc err_parser_function_struct_conflict*(function_location: Location,
    function_name: string, struct_location: Location,
    struct_name: string): ParserError =
  new_parser_error(function_location, fmt"function `{function_name}` name conflicts with struct `{struct_name}` at {struct_location}")

proc err_parser_function_union_branch_conflict*(function_location: Location,
    function_name: string, union_branch_location: Location,
    union_branch_name: string): ParserError =
  new_parser_error(function_location, fmt"function `{function_name}` name conflicts with union branch `{union_branch_name}` at {union_branch_location}")

proc err_parser_expected_multi_struct*(kind: string): ParserError =
  new_parser_error(Location(), fmt"[INTERNAL] expected data to be a list of structs but found `{kind}`")

proc err_parser_expected_struct*(kind: string): ParserError =
  new_parser_error(Location(), fmt"[INTERNAL] expected data to be a default struct but found `{kind}`")

proc err_parser_expected_union*(kind: string): ParserError =
  new_parser_error(Location(), fmt"[INTERNAL] expected data to be a union but found `{kind}`")

proc err_parser_expected_default_struct*(location: Location,
    name: string): ParserError =
  new_parser_error(location, fmt"expected a default struct but found named struct `{name}`")

proc err_parser_expected_named_struct*(location: Location): ParserError =
  new_parser_error(location, fmt"expected a named struct but found anonymous struct")

proc err_parser_module_already_defined*(location: Location, name: string,
    previous: Location): ParserError =
  new_parser_error(location, fmt"module `{name}` is already defined at {previous}")

proc err_parser_empty_file*(path: string): ParserError =
  new_parser_error(new_location(path), fmt"expected file to have at least a function or module")

proc err_parser_native_module_already_defined*(name: string): ParserError =
  new_parser_error(Location(), fmt"[INTERNAL] Native module `{name} is defined twice")

proc err_parser_function_module_conflict*(function_location: Location,
    function_name: string, module_location: Location,
    module_name: string): ParserError =
  new_parser_error(function_location, fmt"function `{function_name}` conflicts with module `{module_name}` at {module_location}")

# NOTE: The parser assumes that the editor used to write code
# must automatically strip off the trailing spaces and also
# add the new line at the end of file if not present. This is
# a conscious choice to ensure the consistent syntax with
# minimal configuration.
type Parser* = ref object of RootObj
  path: string
  tokens: seq[Token]
  index: int = 0
  indent: int
  checkpoints: seq[int]

proc new_parser*(path: string, tokens: seq[Token], indent: int): Parser =
  Parser(path: path, tokens: tokens, index: 0, indent: indent, checkpoints: @[])

proc path*(parser: Parser): string = parser.path
proc indent*(parser: Parser): int = parser.indent

type AtomSpec*[T] = proc(parser: Parser): Result[T, ParserError]
type BlockSpec*[T] = proc(parser: Parser, indent: int): Result[T, ParserError]

proc can_parse*(parser: Parser): bool =
  parser.index < parser.tokens.len

proc peek*(parser: Parser): Result[Token, ParserError] =
  if parser.can_parse():
    ok(parser.tokens[parser.index])
  else:
    err(err_parser_reached_eof(parser.tokens[^1].location))

proc expect*[T](parser: Parser, spec: AtomSpec[T]): Result[T, ParserError] =
  let start = parser.index
  let maybe_value = spec(parser)
  # NOTE: Reset parser index to start if parsing fails.
  if maybe_value.is_err: parser.index = start
  return maybe_value

proc expect*[T](parser: Parser, spec: BlockSpec[T], indent: int): Result[
    T, ParserError] =
  let start = parser.index
  let maybe_value = spec(parser, indent)
  # NOTE: Reset parser index to start if parsing fails.
  if maybe_value.is_err: parser.index = start
  return maybe_value

proc token_spec_util*(parser: Parser, kind: TokenKind): Result[Token, ParserError] =
  let token = ? parser.peek()
  if token.kind == kind:
    parser.index += 1
    ok(token)
  else:
    err(err_parser_expectation_mismatch(token.location, $(kind), $(token.kind)))

proc keyword_spec_util*(parser: Parser, keyword: string): Result[Token, ParserError] =
  let alphabet = ? parser.token_spec_util(TK_ALPHABETS)
  if alphabet.value == keyword:
    ok(alphabet)
  else:
    err(err_parser_expectation_mismatch(alphabet.location, keyword,
        alphabet.value))

# keyword specs
proc module_keyword_spec*(parser: Parser): Result[Token,
    ParserError] = parser.keyword_spec_util("module")

proc extern_keyword_spec*(parser: Parser): Result[Token,
    ParserError] = parser.keyword_spec_util("extern")

proc fn_keyword_spec*(parser: Parser): Result[Token,
    ParserError] = parser.keyword_spec_util("fn")

proc match_keyword_spec*(parser: Parser): Result[Token,
    ParserError] = parser.keyword_spec_util("match")

proc case_keyword_spec*(parser: Parser): Result[Token,
    ParserError] = parser.keyword_spec_util("case")

proc else_keyword_spec*(parser: Parser): Result[Token,
    ParserError] = parser.keyword_spec_util("else")

proc struct_keyword_spec*(parser: Parser): Result[Token,
    ParserError] = parser.keyword_spec_util("struct")

proc generic_keyword_spec*(parser: Parser): Result[Token,
    ParserError] = parser.keyword_spec_util("generic")

proc comment_spec*(parser: Parser): Result[Token,
    ParserError] = parser.token_spec_util(TK_COMMENT)

# special character spec
proc colon_spec*(parser: Parser): Result[Token, ParserError] =
  parser.token_spec_util(TK_COLON)

proc comma_spec*(parser: Parser): Result[Token, ParserError] =
  parser.token_spec_util(TK_COMMA)

proc dot_spec*(parser: Parser): Result[Token, ParserError] =
  parser.token_spec_util(TK_DOT)

proc equal_spec*(parser: Parser): Result[Token, ParserError] =
  parser.token_spec_util(TK_EQUAL)

proc open_paren_bracket_spec*(parser: Parser): Result[Token, ParserError] =
  parser.token_spec_util(TK_OPEN_PAREN)

proc close_paren_bracket_spec*(parser: Parser): Result[Token, ParserError] =
  parser.token_spec_util(TK_CLOSE_PAREN)

proc open_curly_bracket_spec*(parser: Parser): Result[Token, ParserError] =
  parser.token_spec_util(TK_OPEN_CURLY)

proc close_curly_bracket_spec*(parser: Parser): Result[Token, ParserError] =
  parser.token_spec_util(TK_CLOSE_CURLY)

proc open_square_bracket_spec*(parser: Parser): Result[Token, ParserError] =
  parser.token_spec_util(TK_OPEN_SQUARE)

proc close_square_bracket_spec*(parser: Parser): Result[Token, ParserError] =
  parser.token_spec_util(TK_CLOSE_SQUARE)

# spaces spec
proc new_line_spec*(parser: Parser): Result[Token, ParserError] =
  parser.token_spec_util(TK_NEW_LINE)

proc space_spec*(parser: Parser): Result[Token, ParserError] =
  parser.token_spec_util(TK_SPACE)

# NOTE: It just consumes all the spaces and always succeeds
proc optional_space_spec*(parser: Parser): Result[int, ParserError] =
  var count = 0
  while parser.expect(space_spec).is_ok:
    count += 1
  ok(count)

proc strict_space_spec*(parser: Parser): Result[int, ParserError] =
  var count = 0
  # NOTE: Must have one strict space
  discard ? parser.expect(space_spec)
  count += 1
  while parser.expect(space_spec).is_ok:
    count += 1
  ok(count)

# NOTE: This spec is also used to consume trailing line content
proc empty_line_spec*(parser: Parser): Result[void, ParserError] =
  # NOTE: Existence of space does not matter at all.
  discard ? parser.expect(optional_space_spec)
  # NOTE: Existence of comment does not matter at all.
  discard parser.expect(comment_spec)
  # NOTE: Every line must end with a new line.
  discard ? parser.expect(new_line_spec)
  ok()

proc optional_empty_line_spec*(parser: Parser): Result[int, ParserError] =
  var count = 0
  while parser.expect(empty_line_spec).is_ok:
    count += 1
  ok(count)

proc strict_empty_line_spec*(parser: Parser): Result[int, ParserError] =
  var count = 0
  # NOTE: Must have one strict space
  ? parser.expect(empty_line_spec)
  count += 1
  while parser.expect(empty_line_spec).is_ok:
    count += 1
  ok(count)

# NOTE: Configure indent size here.
proc indent_spec*(parser: Parser, indent: int): Result[int, ParserError] =
  let spaces = ? parser.expect(optional_space_spec)
  if spaces == indent * parser.indent:
    return ok(spaces)

  let token = ? parser.peek()
  err(err_parser_indentation_error(token.location, indent * parser.indent, spaces))
