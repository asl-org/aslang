import results, strformat, hashes

const MAX_DIGITS_LENGTH = 256
const MAX_STRING_LENGTH = 1 shl 16

# OPERATORS
const PLUS_OP = '+'
const MINUS_OP = '-'
const COMMA_OP = ','
const DOT_OP = '.'
const COLON_OP = ':'
const EQUAL_OP = '='
const BACK_SLASH_OP = '\\'
const OPEN_PAREN_OP = '('
const CLOSE_PAREN_OP = ')'
const OPEN_CURLY_OP = '{'
const CLOSE_CURLY_OP = '}'
const OPEN_SQUARE_OP = '['
const CLOSE_SQUARE_OP = ']'

const SPACE = ' '
const NEW_LINE = '\n'

const UNDERSCORE = '_'
const DOUBLE_QUOTE = '"'
const HASHTAG = '#'


type Location* = object
  filename: string
  line: int = 1
  col: int = 1

proc new_location*(filename: string): Location =
  Location(filename: filename)

proc update(location: Location, value: string): Location =
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

proc tokenize*(filename: string, content: string): Result[seq[Token], string] =
  var index = 0
  var location = new_location(filename)
  var tokens: seq[Token]

  while index < content.len:
    case content[index]:
    of PLUS_OP:
      let token = new_token(TK_PLUS, $content[index], location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of MINUS_OP:
      let token = new_token(TK_MINUS, $content[index], location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of COMMA_OP:
      let token = new_token(TK_COMMA, $content[index], location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of DOT_OP:
      let token = new_token(TK_DOT, $content[index], location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of COLON_OP:
      let token = new_token(TK_COLON, $content[index], location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of EQUAL_OP:
      let token = new_token(TK_EQUAL, $content[index], location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of BACK_SLASH_OP:
      let token = new_token(TK_BACK_SLASH, $content[index], location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of OPEN_PAREN_OP:
      let token = new_token(TK_OPEN_PAREN, $content[index], location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of CLOSE_PAREN_OP:
      let token = new_token(TK_CLOSE_PAREN, $content[index], location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of OPEN_CURLY_OP:
      let token = new_token(TK_OPEN_CURLY, $content[index], location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of CLOSE_CURLY_OP:
      let token = new_token(TK_CLOSE_CURLY, $content[index], location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of OPEN_SQUARE_OP:
      let token = new_token(TK_OPEN_SQUARE, $content[index], location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of CLOSE_SQUARE_OP:
      let token = new_token(TK_CLOSE_SQUARE, $content[index], location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of SPACE:
      let token = new_token(TK_SPACE, $content[index], location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of NEW_LINE:
      let token = new_token(TK_NEW_LINE, $content[index], location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of DOUBLE_QUOTE:
      let start = index

      index += 1 # move past double quote

      # NOTE: this check is needed because in case it is not present while loop
      # will be skipped entirely resulting into an invalid string token.
      if index == content.len:
        return err(fmt"{location} [TE101] failed to parse malformed string literal")

      while index < content.len:
        if content[index] == '"':
          if index > 0 and content[index - 1] == '\\':
            index += 1
          else:
            break
        else:
          index += 1

        if index > start + MAX_STRING_LENGTH:
          return err(fmt"{location} [TE102] string literal exceeded maximum supported length of {MAX_STRING_LENGTH}")

      index += 1 # move past double quote again

      let token = new_token(TK_STRING, content.substr(start, index - 1), location)
      tokens.add(token)
    of HASHTAG:
      let start = index
      # consume everything up until newline
      while index < content.len and content[index] != '\n': index += 1
      let token = new_token(TK_COMMENT, content.substr(start, index - 1), location)
      location = location.update(token.value)
      tokens.add(token)
    of '0'..'9':
      let start = index
      while index < content.len and content[index] in '0'..'9':
        index += 1
        if index > start + MAX_DIGITS_LENGTH:
          return err(fmt"{location} [TE103] integer literal exceeded maximum supported length of {MAX_DIGITS_LENGTH}")
      let token = new_token(TK_DIGITS, content.substr(start, index - 1), location)
      location = location.update(token.value)
      tokens.add(token)
    of 'a'..'z', 'A'..'Z':
      let start = index
      while index < content.len and ((content[index] in 'a'..'z') or (content[
          index] in 'A'..'Z')):
        index += 1
      let token = new_token(TK_ALPHABETS, content.substr(start, index - 1), location)
      location = location.update(token.value)
      tokens.add(token)
    of UNDERSCORE:
      let token = new_token(TK_UNDERSCORE, $content[index], location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    else:
      return err(fmt"[TE104] {location} Unexpected character `{content[index]}` encountered")

  # NOTE: Adding NEW_LINE Token to indicate end of token stream
  tokens.add(new_token(TK_NEW_LINE, "\n", location))

  ok(tokens)
