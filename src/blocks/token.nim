import hashes

import token/helpers

import token/spec; export spec
import token/location; export location
import token/kind; export kind

type Token* = ref object of RootObj
  content*: string
  kind*: TokenKind
  location*: Location

proc new_id_token*(content: string): Token =
  Token(kind: TK_ID, content: content)

proc new_int_token*(value: uint): Token =
  Token(kind: TK_INTEGER, content: $(value))

proc hash*(token: Token): Hash =
  token.content.hash !& token.location.hash

proc `$`*(token: Token): string =
  token.content

# NOTE: spec order is important
let TOKEN_SPECS* = @[
  # keywords
  TokenSpec(kind: TSK_STATIC, value: "module", token_kind: TK_MODULE),
  TokenSpec(kind: TSK_STATIC, value: "fn", token_kind: TK_FN),
  TokenSpec(kind: TSK_STATIC, value: "match", token_kind: TK_MATCH),
  TokenSpec(kind: TSK_STATIC, value: "case", token_kind: TK_CASE),
  TokenSpec(kind: TSK_STATIC, value: "else", token_kind: TK_ELSE),
  TokenSpec(kind: TSK_STATIC, value: "struct", token_kind: TK_STRUCT),
  TokenSpec(kind: TSK_STATIC, value: "union", token_kind: TK_UNION),
  # values
  TokenSpec(kind: TSK_DYNAMIC, matcher: expect_identifier, token_kind: TK_ID),
  TokenSpec(kind: TSK_DYNAMIC, matcher: expect_string, token_kind: TK_STRING),
  TokenSpec(kind: TSK_DYNAMIC, matcher: expect_float, token_kind: TK_FLOAT),
  TokenSpec(kind: TSK_DYNAMIC, matcher: expect_integer, token_kind: TK_INTEGER),
  # prefix operators
  TokenSpec(kind: TSK_STATIC, value: "#", token_kind: TK_HASHTAG),
  TokenSpec(kind: TSK_STATIC, value: "~", token_kind: TK_TILDE),
  TokenSpec(kind: TSK_STATIC, value: "@", token_kind: TK_AT_THE_RATE),
  TokenSpec(kind: TSK_STATIC, value: "\\", token_kind: TK_BACKSLASH),
  # infix operators
  TokenSpec(kind: TSK_STATIC, value: "+", token_kind: TK_PLUS),
  TokenSpec(kind: TSK_STATIC, value: "-", token_kind: TK_MINUS),
  TokenSpec(kind: TSK_STATIC, value: "*", token_kind: TK_ASTERISK),
  TokenSpec(kind: TSK_STATIC, value: "/", token_kind: TK_SLASH),
  TokenSpec(kind: TSK_STATIC, value: "$", token_kind: TK_DOLLAR),
  TokenSpec(kind: TSK_STATIC, value: "%", token_kind: TK_PERCENT),
  TokenSpec(kind: TSK_STATIC, value: "=", token_kind: TK_EQUAL),
  TokenSpec(kind: TSK_STATIC, value: "&", token_kind: TK_AMPERSAND),
  TokenSpec(kind: TSK_STATIC, value: "|", token_kind: TK_PIPE),
  TokenSpec(kind: TSK_STATIC, value: "^", token_kind: TK_CARET),
  TokenSpec(kind: TSK_STATIC, value: ".", token_kind: TK_PERIOD),
  TokenSpec(kind: TSK_STATIC, value: ",", token_kind: TK_COMMA),
  TokenSpec(kind: TSK_STATIC, value: ":", token_kind: TK_COLON),
  # postfix operators
  TokenSpec(kind: TSK_STATIC, value: "!", token_kind: TK_BANG),
  TokenSpec(kind: TSK_STATIC, value: "?", token_kind: TK_QUESTION_MARK),
  TokenSpec(kind: TSK_STATIC, value: ";", token_kind: TK_SEMI_COLON),
  # grouping operators
  TokenSpec(kind: TSK_STATIC, value: "(", token_kind: TK_OPAREN),
  TokenSpec(kind: TSK_STATIC, value: ")", token_kind: TK_CPAREN),
  TokenSpec(kind: TSK_STATIC, value: "{", token_kind: TK_OCURLY),
  TokenSpec(kind: TSK_STATIC, value: "}", token_kind: TK_CCURLY),
  TokenSpec(kind: TSK_STATIC, value: "[", token_kind: TK_OSQUARE),
  TokenSpec(kind: TSK_STATIC, value: "]", token_kind: TK_CSQUARE),
  TokenSpec(kind: TSK_STATIC, value: "<", token_kind: TK_OANGLE),
  TokenSpec(kind: TSK_STATIC, value: ">", token_kind: TK_CANGLE),
  TokenSpec(kind: TSK_STATIC, value: "`", token_kind: TK_BACKTICK),
  TokenSpec(kind: TSK_STATIC, value: "'", token_kind: TK_SINGLE_QUOTE),
  TokenSpec(kind: TSK_STATIC, value: "\"", token_kind: TK_DOUBLE_QUOTE),
  # space characters
  TokenSpec(kind: TSK_STATIC, value: " ", token_kind: TK_SPACE),
  TokenSpec(kind: TSK_STATIC, value: "\n", token_kind: TK_NEWLINE),
]
