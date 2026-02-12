import results, strformat

import tokenizer
export tokenizer

import repo
export repo

# ast node constants
const MAX_IDENTIFIER_LENGTH* = 256
const MAX_TYPE_CHILDREN_COUNT* = 8
const MAX_ARGS_LENGTH* = 32
const MAX_BRANCH_LENGTH* = 256

# parser constants
const INDENT_SIZE* = 2 # spaces

type Error* = ref object of RootObj
  location: Location
  message: string

proc `<`*(self: Error, other: Error): bool = self.location < other.location
proc `>`*(self: Error, other: Error): bool = self.location > other.location
proc `==`*(self: Error, other: Error): bool = self.location == other.location
proc `$`*(err: Error): string = fmt"[ERROR] {err.location} - {err.message}"

proc new_parser_error(location: Location, message: string): Error =
  Error(location: location, message: message)

proc err_parser_reached_eof*(location: Location): Error =
  new_parser_error(location, "parser reached end of file")

proc err_parser_expectation_mismatch*(location: Location, expected: string,
    found: string): Error =
  new_parser_error(location, fmt"expected `{expected}` found `{found}`")

proc err_parser_indentation_error*(location: Location, expected: int,
    found: int): Error =
  new_parser_error(location, fmt"expected `{expected}` space(s) but found `{found}` space(s)")

proc err_parser_empty_identifier*(location: Location): Error =
  new_parser_error(location, "empty identifiers are not allowed")

proc err_parser_identifier_too_long*(location: Location,
    length: int): Error =
  new_parser_error(location, fmt"{location} identifier length `{length}` exceeded maximum identifier length of `{MAX_IDENTIFIER_LENGTH}`")

proc err_parser_expected_sign*(location: Location, found: string): Error =
  new_parser_error(location, fmt"expected a sign `+` or `-` but found {found}")

proc err_parser_empty_generic_list*(location: Location): Error =
  new_parser_error(location, "nested module refs can not have empty child module ref list")

proc err_parser_generic_list_too_long*(location: Location,
    children: int): Error =
  new_parser_error(location, fmt"a nested module ref only supports upto `{MAX_TYPE_CHILDREN_COUNT}` children types but `{children}` were given")

proc err_parser_empty_arg_list*(location: Location): Error =
  new_parser_error(location, "function argument list can not be empty")

proc err_parser_arg_list_too_long*(location: Location, args: int): Error =
  new_parser_error(location, fmt"function argument length `{args}` exceeded maximum argument length `{MAX_ARGS_LENGTH}`")

proc err_parser_arg_already_defined*(location: Location, arg: string,
    previous: Location): Error =
  new_parser_error(location, fmt"argument `{arg}` is already defined at {previous}")

proc err_parser_empty_struct*(location: Location): Error =
  new_parser_error(location, "struct block can not be empty")

proc err_parser_struct_too_long*(location: Location, fields: int): Error =
  new_parser_error(location, fmt"struct field length `{fields}` exceeded maximum field length `{MAX_ARGS_LENGTH}`")

proc err_parser_empty_union_branch*(location: Location): Error =
  new_parser_error(location, "union branch block can not be empty")

proc err_parser_union_branch_too_long*(location: Location,
    fields: int): Error =
  new_parser_error(location, fmt"union branch field length `{fields}` exceeded maximum field length `{MAX_ARGS_LENGTH}`")

proc err_parser_struct_conversion_error*(location: Location): Error =
  new_parser_error(location, fmt"[UNREACHABLE] named struct pattern can not be converted to another named struct pattern")

proc err_parser_empty_case*(location: Location): Error =
  new_parser_error(location, fmt"case block must have at least one statement")

proc err_parser_empty_else*(location: Location): Error =
  new_parser_error(location, fmt"else block must have at least one statement")

proc err_parser_empty_match*(location: Location): Error =
  new_parser_error(location, fmt"match block must have at least 2 case blocks")

proc err_parser_empty_match_with_else*(location: Location): Error =
  new_parser_error(location, fmt"match block must have at least 1 case block")

proc err_parser_empty_generic_constraint_list*(location: Location,
    generic: string): Error =
  new_parser_error(location, fmt"generic `{generic}` must have at least one constraint")

proc err_parser_generic_constraint_already_defined*(location: Location,
    constraint: string, previous: Location): Error =
  new_parser_error(location, fmt"generic constraint `{constraint}` is already defined at {previous}")

proc err_parser_empty_function*(location: Location, name: string): Error =
  new_parser_error(location, fmt"function `{name}` must have at least one statement")

proc err_parser_empty_module*(location: Location, name: string): Error =
  new_parser_error(location, fmt"module `{name}` can not be empty")

proc err_parser_empty_module_with_generics*(location: Location,
    name: string): Error =
  new_parser_error(location, fmt"module `{name}` can not only contain generics")

proc err_parser_generic_already_defined*(location: Location, name: string,
    previous: Location): Error =
  new_parser_error(location, fmt"generic `{name}` is already defined at {previous}")

proc err_parser_function_already_defined*(location: Location, name: string,
    previous: Location): Error =
  new_parser_error(location, fmt"function `{name}` is already defined at {previous}")

proc err_parser_struct_generic_conflict*(struct_location: Location,
    struct_name: string, generic_location: Location,
    generic_name: string): Error =
  new_parser_error(struct_location, fmt"struct `{struct_name}` name conflicts with generic `{generic_name}` at {generic_location}")

proc err_parser_function_generic_conflict*(function_location: Location,
    function_name: string, generic_location: Location,
    generic_name: string): Error =
  new_parser_error(function_location, fmt"function `{function_name}` name conflicts with generic `{generic_name}` at {generic_location}")

proc err_parser_function_struct_conflict*(function_location: Location,
    function_name: string, struct_location: Location,
    struct_name: string): Error =
  new_parser_error(function_location, fmt"function `{function_name}` name conflicts with struct `{struct_name}` at {struct_location}")

proc err_parser_module_already_defined*(location: Location, name: string,
    previous: Location): Error =
  new_parser_error(location, fmt"module `{name}` is already defined at {previous}")

proc err_parser_empty_file*(path: string): Error =
  new_parser_error(new_location(path), fmt"expected file to have at least a function or module")

proc err_parser_function_module_conflict*(function_location: Location,
    function_name: string, module_location: Location,
    module_name: string): Error =
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

proc new_parser*(path: string, tokens: seq[Token], indent: int): Parser =
  Parser(path: path, tokens: tokens, index: 0, indent: indent)

proc path*(parser: Parser): string = parser.path
proc indent*(parser: Parser): int = parser.indent

type AtomSpec*[T] = proc(parser: Parser): Result[T, Error] {.nimcall.}
type BlockSpec*[T] = proc(parser: Parser, indent: int): Result[T, Error] {.nimcall.}

proc can_parse*(parser: Parser): bool =
  parser.index < parser.tokens.len

proc peek*(parser: Parser): Result[Token, Error] =
  if parser.can_parse():
    ok(parser.tokens[parser.index])
  else:
    err(err_parser_reached_eof(parser.tokens[^1].location))

proc expect*[T](parser: Parser, spec: AtomSpec[T]): Result[T, Error] =
  let start = parser.index
  let maybe_value = spec(parser)
  # NOTE: Reset parser index to start if parsing fails.
  if maybe_value.is_err: parser.index = start
  return maybe_value

proc expect*[T](parser: Parser, spec: BlockSpec[T], indent: int): Result[
    T, Error] =
  let start = parser.index
  let maybe_value = spec(parser, indent)
  # NOTE: Reset parser index to start if parsing fails.
  if maybe_value.is_err: parser.index = start
  return maybe_value

proc token_spec_util*(parser: Parser, kind: TokenKind): Result[Token, Error] =
  let token = ? parser.peek()
  if token.kind == kind:
    parser.index += 1
    ok(token)
  else:
    err(err_parser_expectation_mismatch(token.location, $(kind), $(token.kind)))

proc keyword_spec_util*(parser: Parser, keyword: string): Result[Token, Error] =
  let alphabet = ? parser.token_spec_util(TK_ALPHABETS)
  if alphabet.value == keyword:
    ok(alphabet)
  else:
    err(err_parser_expectation_mismatch(alphabet.location, keyword,
        alphabet.value))

# keyword specs
proc module_keyword_spec*(parser: Parser): Result[Token,
    Error] = parser.keyword_spec_util("module")

proc extern_keyword_spec*(parser: Parser): Result[Token,
    Error] = parser.keyword_spec_util("extern")

proc fn_keyword_spec*(parser: Parser): Result[Token,
    Error] = parser.keyword_spec_util("fn")

proc match_keyword_spec*(parser: Parser): Result[Token,
    Error] = parser.keyword_spec_util("match")

proc case_keyword_spec*(parser: Parser): Result[Token,
    Error] = parser.keyword_spec_util("case")

proc else_keyword_spec*(parser: Parser): Result[Token,
    Error] = parser.keyword_spec_util("else")

proc struct_keyword_spec*(parser: Parser): Result[Token,
    Error] = parser.keyword_spec_util("struct")

proc generic_keyword_spec*(parser: Parser): Result[Token,
    Error] = parser.keyword_spec_util("generic")

proc comment_spec*(parser: Parser): Result[Token,
    Error] = parser.token_spec_util(TK_COMMENT)

# special character spec
proc colon_spec*(parser: Parser): Result[Token, Error] =
  parser.token_spec_util(TK_COLON)

proc comma_spec*(parser: Parser): Result[Token, Error] =
  parser.token_spec_util(TK_COMMA)

proc dot_spec*(parser: Parser): Result[Token, Error] =
  parser.token_spec_util(TK_DOT)

proc equal_spec*(parser: Parser): Result[Token, Error] =
  parser.token_spec_util(TK_EQUAL)

proc open_paren_bracket_spec*(parser: Parser): Result[Token, Error] =
  parser.token_spec_util(TK_OPEN_PAREN)

proc close_paren_bracket_spec*(parser: Parser): Result[Token, Error] =
  parser.token_spec_util(TK_CLOSE_PAREN)

proc open_curly_bracket_spec*(parser: Parser): Result[Token, Error] =
  parser.token_spec_util(TK_OPEN_CURLY)

proc close_curly_bracket_spec*(parser: Parser): Result[Token, Error] =
  parser.token_spec_util(TK_CLOSE_CURLY)

proc open_square_bracket_spec*(parser: Parser): Result[Token, Error] =
  parser.token_spec_util(TK_OPEN_SQUARE)

proc close_square_bracket_spec*(parser: Parser): Result[Token, Error] =
  parser.token_spec_util(TK_CLOSE_SQUARE)

# content token specs
proc underscore_spec*(parser: Parser): Result[Token, Error] =
  parser.token_spec_util(TK_UNDERSCORE)

proc alphabets_spec*(parser: Parser): Result[Token, Error] =
  parser.token_spec_util(TK_ALPHABETS)

proc digits_spec*(parser: Parser): Result[Token, Error] =
  parser.token_spec_util(TK_DIGITS)

proc plus_spec*(parser: Parser): Result[Token, Error] =
  parser.token_spec_util(TK_PLUS)

proc minus_spec*(parser: Parser): Result[Token, Error] =
  parser.token_spec_util(TK_MINUS)

# spaces spec
proc new_line_spec*(parser: Parser): Result[Token, Error] =
  parser.token_spec_util(TK_NEW_LINE)

proc space_spec*(parser: Parser): Result[Token, Error] =
  parser.token_spec_util(TK_SPACE)

# NOTE: It just consumes all the spaces and always succeeds
proc optional_space_spec*(parser: Parser): Result[int, Error] =
  var count = 0
  while parser.expect(space_spec).is_ok:
    count += 1
  ok(count)

proc strict_space_spec*(parser: Parser): Result[int, Error] =
  var count = 0
  # NOTE: Must have one strict space
  discard ? parser.expect(space_spec)
  count += 1
  while parser.expect(space_spec).is_ok:
    count += 1
  ok(count)

# NOTE: This spec is also used to consume trailing line content
proc empty_line_spec*(parser: Parser): Result[void, Error] =
  # NOTE: Existence of space does not matter at all.
  discard ? parser.expect(optional_space_spec)
  # NOTE: Existence of comment does not matter at all.
  discard parser.expect(comment_spec)
  # NOTE: Every line must end with a new line.
  discard ? parser.expect(new_line_spec)
  ok()

proc optional_empty_line_spec*(parser: Parser): Result[int, Error] =
  var count = 0
  while parser.expect(empty_line_spec).is_ok:
    count += 1
  ok(count)

proc strict_empty_line_spec*(parser: Parser): Result[int, Error] =
  var count = 0
  # NOTE: Must have one strict space
  ? parser.expect(empty_line_spec)
  count += 1
  while parser.expect(empty_line_spec).is_ok:
    count += 1
  ok(count)

# NOTE: Configure indent size here.
proc indent_spec*(parser: Parser, indent: int): Result[int, Error] =
  let spaces = ? parser.expect(optional_space_spec)
  if spaces == indent * parser.indent:
    return ok(spaces)

  let token = ? parser.peek()
  err(err_parser_indentation_error(token.location, indent * parser.indent, spaces))

# parser combinators
proc first_of*[T](parser: Parser, specs: openArray[AtomSpec[T]]): Result[T, Error] =
  var errors: seq[Error]
  for spec in specs:
    let maybe = parser.expect(spec)
    if maybe.is_ok: return maybe
    errors.add(maybe.error)
  err(errors.max())

proc first_of*[T](parser: Parser, specs: openArray[BlockSpec[T]], indent: int): Result[T, Error] =
  var errors: seq[Error]
  for spec in specs:
    let maybe = parser.expect(spec, indent)
    if maybe.is_ok: return maybe
    errors.add(maybe.error)
  err(errors.max())

proc comma_separated_spec*[T](parser: Parser, item_spec: AtomSpec[T]): Result[seq[T], Error] =
  var items: seq[T]
  discard ? parser.expect(optional_space_spec)
  items.add( ? parser.expect(item_spec))
  discard ? parser.expect(optional_space_spec)
  while parser.expect(comma_spec).is_ok:
    discard ? parser.expect(optional_space_spec)
    items.add( ? parser.expect(item_spec))
    discard ? parser.expect(optional_space_spec)
  ok(items)

proc list_spec*[T](parser: Parser, open_bracket: AtomSpec[Token],
    item_spec: AtomSpec[T], close_bracket: AtomSpec[Token]): Result[seq[T], Error] =
  discard ? parser.expect(open_bracket)
  let items = ? parser.comma_separated_spec(item_spec)
  discard ? parser.expect(close_bracket)
  ok(items)

proc zero_or_more_spec*[T](parser: Parser, item_spec: BlockSpec[T],
    indent: int, separator: AtomSpec[int]): Result[seq[T], Error] =
  var items: seq[T]
  var maybe = parser.expect(item_spec, indent)
  while maybe.is_ok:
    items.add(maybe.get)
    discard ? parser.expect(separator)
    maybe = parser.expect(item_spec, indent)
  ok(items)

proc one_or_more_spec*[T](parser: Parser, item_spec: BlockSpec[T],
    indent: int, separator: AtomSpec[int]): Result[seq[T], Error] =
  var items: seq[T]
  items.add( ? parser.expect(item_spec, indent))
  discard ? parser.expect(separator)
  var maybe = parser.expect(item_spec, indent)
  while maybe.is_ok:
    items.add(maybe.get)
    discard ? parser.expect(separator)
    maybe = parser.expect(item_spec, indent)
  ok(items)
