import results, hashes

import cursor
import constants
import location
import spec
import error

type TokenKind* = enum
  TK_PLUS, TK_MINUS
  TK_COMMA, TK_DOT, TK_COLON, TK_EQUAL
  TK_BACK_SLASH
  TK_OPEN_PAREN, TK_CLOSE_PAREN
  TK_OPEN_CURLY, TK_CLOSE_CURLY
  TK_OPEN_SQUARE, TK_CLOSE_SQUARE
  TK_SPACE, TK_NEW_LINE
  TK_STRING, TK_DIGITS, TK_ALPHABETS, TK_UNDERSCORE
  TK_COMMENT

type Token* = ref object of RootObj
  kind: TokenKind
  value: string
  location: Location

proc new_token*(kind: TokenKind, value: string, location: Location): Token =
  Token(kind: kind, value: value, location: location)

proc kind*(token: Token): TokenKind = token.kind
proc value*(token: Token): string = token.value
proc location*(token: Token): Location = token.location

proc hash*(token: Token): Hash =
  hash(token.kind) !& hash(token.value)

type
  TokenSpecKind = enum
    TSK_STATIC, TSK_MATCHER
  TokenSpec = ref object of RootObj
    case kind: TokenSpecKind
    of TSK_STATIC: value: string
    of TSK_MATCHER: matcher: proc(content: string, start: int): Result[int, Error]

proc new_token_spec(value: string): TokenSpec =
  TokenSpec(kind: TSK_STATIC, value: value)

proc new_token_spec(matcher: proc(content: string, start: int): Result[int,
    Error]): TokenSpec =
  TokenSpec(kind: TSK_MATCHER, matcher: matcher)

proc match*(spec: TokenSpec, cursor: Cursor, content: string): Result[string, Error] =
  let index =
    case spec.kind:
    of TSK_STATIC:
      if cursor.index + spec.value.len > content.len:
        return err(err_tokenizer_reached_eof(cursor.index))
      let chunk = content.substr(cursor.index, cursor.index + spec.value.len - 1)
      if chunk != spec.value:
        return err(err_tokenizer_expectation_mismatch(cursor.index, spec.value, chunk))
      cursor.index + spec.value.len
    of TSK_MATCHER:
      ? spec.matcher(content, cursor.index)
  ok(content.substr(cursor.index, index - 1))

let TOKEN_SPECS* = @[
  # matcher specs
  (TK_STRING, new_token_spec(match_string)),
  (TK_ALPHABETS, new_token_spec(match_alphabet)),
  (TK_DIGITS, new_token_spec(match_digit)),
  (TK_COMMENT, new_token_spec(match_comment)),
  # static specs
  (TK_PLUS, new_token_spec($PLUS_OP)),
  (TK_MINUS, new_token_spec($MINUS_OP)),
  (TK_COMMA, new_token_spec($COMMA_OP)),
  (TK_DOT, new_token_spec($DOT_OP)),
  (TK_COLON, new_token_spec($COLON_OP)),
  (TK_EQUAL, new_token_spec($EQUAL_OP)),
  (TK_BACK_SLASH, new_token_spec($BACK_SLASH_OP)),
  (TK_OPEN_PAREN, new_token_spec($OPEN_PAREN_OP)),
  (TK_CLOSE_PAREN, new_token_spec($CLOSE_PAREN_OP)),
  (TK_OPEN_CURLY, new_token_spec($OPEN_CURLY_OP)),
  (TK_CLOSE_CURLY, new_token_spec($CLOSE_CURLY_OP)),
  (TK_OPEN_SQUARE, new_token_spec($OPEN_SQUARE_OP)),
  (TK_CLOSE_SQUARE, new_token_spec($CLOSE_SQUARE_OP)),
  (TK_UNDERSCORE, new_token_spec($UNDERSCORE)),
  (TK_SPACE, new_token_spec($SPACE)),
  (TK_NEW_LINE, new_token_spec($NEW_LINE)),
]
