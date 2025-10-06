import strformat, hashes

type Location* = object
  filename: string
  line: int = 1
  col: int = 1

proc new_location*(filename: string): Location =
  Location(filename: filename)

proc new_location*(): Location = Location()

proc update*(location: Location, value: string): Location =
  var new_location = location
  for x in value:
    if x == '\n':
      new_location.line += 1
      new_location.col = 1
    else:
      new_location.col += 1
  return new_location

proc `$`*(location: Location): string =
  fmt"{location.filename}:{location.line}:{location.col}"

proc hash*(location: Location): Hash =
  hash(location.filename) !& hash(location.line) !& hash(location.col)

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
