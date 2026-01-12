import results, strformat

import tokenizer
export tokenizer

# ast node constants
const MAX_IDENTIFIER_LENGTH* = 256
const MAX_TYPE_CHILDREN_COUNT* = 8
const MAX_ARGS_LENGTH* = 32

# parser constants
const INDENT_SIZE* = 2 # spaces

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

type AtomSpec*[T] = proc(parser: Parser): Result[T, string]
type BlockSpec*[T] = proc(parser: Parser, indent: int): Result[T, string]

proc can_parse*(parser: Parser): bool =
  parser.index < parser.tokens.len

proc peek*(parser: Parser): Result[Token, string] =
  if parser.can_parse():
    ok(parser.tokens[parser.index])
  else:
    err(fmt"reached end of token stream")

proc expect*[T](parser: Parser, spec: AtomSpec[T]): Result[T, string] =
  let start = parser.index
  let maybe_value = spec(parser)
  if maybe_value.is_err:
    parser.index = start
    return err(maybe_value.error)
  return maybe_value

proc expect*[T](parser: Parser, spec: BlockSpec[T], indent: int): Result[
    T, string] =
  let start = parser.index
  let maybe_value = spec(parser, indent)
  if maybe_value.is_err:
    parser.index = start
    return err(maybe_value.error)
  return maybe_value

proc token_spec_util*(parser: Parser, kind: TokenKind): Result[Token, string] =
  let token = ? parser.peek()
  if token.kind == kind:
    parser.index += 1
    ok(token)
  else:
    err(fmt"{token.location} expected token kind `{kind}` but found `{token.kind}`")

proc keyword_spec_util*(parser: Parser, keyword: string): Result[Token, string] =
  let alphabet = ? parser.token_spec_util(TK_ALPHABETS)
  if alphabet.value == keyword:
    ok(alphabet)
  else:
    err(fmt"{alphabet.location} expected keyword `{keyword}` but found `{alphabet.value}`")

# keyword specs
proc module_keyword_spec*(parser: Parser): Result[Token,
    string] = parser.keyword_spec_util("module")

proc fn_keyword_spec*(parser: Parser): Result[Token,
    string] = parser.keyword_spec_util("fn")

proc match_keyword_spec*(parser: Parser): Result[Token,
    string] = parser.keyword_spec_util("match")

proc case_keyword_spec*(parser: Parser): Result[Token,
    string] = parser.keyword_spec_util("case")

proc else_keyword_spec*(parser: Parser): Result[Token,
    string] = parser.keyword_spec_util("else")

proc struct_keyword_spec*(parser: Parser): Result[Token,
    string] = parser.keyword_spec_util("struct")

proc generic_keyword_spec*(parser: Parser): Result[Token,
    string] = parser.keyword_spec_util("generic")

proc comment_spec*(parser: Parser): Result[Token,
    string] = parser.token_spec_util(TK_COMMENT)

# special character spec
proc colon_spec*(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_COLON)

proc comma_spec*(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_COMMA)

proc dot_spec*(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_DOT)

proc equal_spec*(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_EQUAL)

proc open_paren_bracket_spec*(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_OPEN_PAREN)

proc close_paren_bracket_spec*(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_CLOSE_PAREN)

proc open_curly_bracket_spec*(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_OPEN_CURLY)

proc close_curly_bracket_spec*(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_CLOSE_CURLY)

proc open_square_bracket_spec*(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_OPEN_SQUARE)

proc close_square_bracket_spec*(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_CLOSE_SQUARE)

# spaces spec
proc new_line_spec*(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_NEW_LINE)

proc space_spec*(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_SPACE)

# NOTE: It just consumes all the spaces and always succeeds
proc optional_space_spec*(parser: Parser): Result[int, string] =
  var count = 0
  while parser.expect(space_spec).is_ok:
    count += 1
  ok(count)

proc strict_space_spec*(parser: Parser): Result[int, string] =
  var count = 0
  # NOTE: Must have one strict space
  discard ? parser.expect(space_spec)
  count += 1
  while parser.expect(space_spec).is_ok:
    count += 1
  ok(count)

# NOTE: This spec is also used to consume trailing line content
proc empty_line_spec*(parser: Parser): Result[void, string] =
  # NOTE: Existence of space does not matter at all.
  discard ? parser.expect(optional_space_spec)
  # NOTE: Existence of comment does not matter at all.
  discard parser.expect(comment_spec)
  # NOTE: Every line must end with a new line.
  discard ? parser.expect(new_line_spec)
  ok()

proc optional_empty_line_spec*(parser: Parser): Result[int, string] =
  var count = 0
  while parser.expect(empty_line_spec).is_ok:
    count += 1
  ok(count)

proc strict_empty_line_spec*(parser: Parser): Result[int, string] =
  var count = 0
  # NOTE: Must have one strict space
  ? parser.expect(empty_line_spec)
  count += 1
  while parser.expect(empty_line_spec).is_ok:
    count += 1
  ok(count)

# NOTE: Configure indent size here.
proc indent_spec*(parser: Parser, indent: int): Result[int, string] =

  let spaces = ? parser.expect(optional_space_spec)
  if spaces == indent * parser.indent:
    return ok(spaces)

  # NOTE: this token is the start of line
  let token = ? parser.peek()
  err(fmt"{token.location} indentation error: expected `{indent * parser.indent}` space but found `{spaces}`")
