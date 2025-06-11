import strformat, results, hashes

import helpers

type Location* = object of RootObj
  filename*: string
  line: int = 1
  column*: int = 1

proc new_location*(filename: string): Location =
  Location(filename: filename)

proc new_file_location*(filename: string): Location =
  Location(filename: filename, line: 0, column: -1)

proc update*(location: Location, content: string): Location =
  var updated = location
  for x in content:
    if x == '\n':
      updated.line += 1
      updated.column = 1
    else:
      updated.column += 1
  return updated

proc `$`*(location: Location): string =
  fmt"{location.filename}:{location.line}:{location.column}"

type
  TokenKind* = enum
    # keywords
    TK_MODULE, TK_FN, TK_MATCH, TK_CASE, TK_ELSE, TK_STRUCT, TK_UNION
    # values
    TK_ID, TK_STRING, TK_FLOAT, TK_INTEGER
    # prefix operators
    TK_HASHTAG, TK_TILDE, TK_AT_THE_RATE, TK_BACKSLASH
    # infix operators
    TK_PLUS, TK_MINUS, TK_ASTERISK, TK_SLASH, TK_DOLLAR, TK_PERCENT, TK_EQUAL
    TK_AMPERSAND, TK_PIPE, TK_CARET, TK_PERIOD, TK_SEMI_COLON, TK_COLON, TK_COMMA
    # postfix operators
    TK_BANG, TK_QUESTION_MARK
    # grouping operators
    TK_OPAREN, TK_CPAREN, TK_OCURLY, TK_CCURLY, TK_OSQUARE, TK_CSQUARE
    TK_OANGLE, TK_CANGLE, TK_SINGLE_QUOTE, TK_DOUBLE_QUOTE, TK_BACKTICK
    # space characters
    TK_NEWLINE, TK_SPACE
    # EOF
    TK_EOF

  Token* = ref object of RootObj
    content*: string
    kind*: TokenKind
    location*: Location

proc hash*(token: Token): Hash = token.content.hash !& token.location.hash
proc `$`*(token: Token): string = token.content

type
  TokenSpecKind* = enum
    TSK_STATIC, TSK_DYNAMIC
  TokenSpec* = ref object of RootObj
    token_kind*: TokenKind
    case kind*: TokenSpecKind
    of TSK_STATIC: value*: string
    of TSK_DYNAMIC: matcher*: proc(content: string, index: int): Result[string, string]

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
