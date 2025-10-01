import results, strformat, hashes

type Location* = object
  filename: string
  line: int = 1
  col: int = 1

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
  kind*: TokenKind
  value*: string
  location*: Location

proc hash*(token: Token): Hash =
  hash(token.kind) !& hash(token.value)

proc tokenize*(filename: string, content: string): Result[seq[Token], string] =
  var index = 0
  var location = Location(filename: filename)
  var tokens: seq[Token]

  while index < content.len:
    case content[index]:
    of '+':
      let token = Token(kind: TK_PLUS, value: $content[index],
          location: location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of '-':
      let token = Token(kind: TK_MINUS, value: $content[index],
          location: location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of ',':
      let token = Token(kind: TK_COMMA, value: $content[index],
          location: location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of '.':
      let token = Token(kind: TK_DOT, value: $content[index],
          location: location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of ':':
      let token = Token(kind: TK_COLON, value: $content[index],
          location: location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of '=':
      let token = Token(kind: TK_EQUAL, value: $content[index],
          location: location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of '\\':
      let token = Token(kind: TK_BACK_SLASH, value: $content[index],
          location: location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of '"':
      let start = index

      index += 1 # move past double quote
      # NOTE: this check is needed because in case it is not present while loop
      # will be skipped entirely resulting into an invalid string token.
      if index == content.len:
        return err(fmt"{location} failed to parse malformed string literal")

      while index < content.len:
        if content[index] == '"':
          if index > 0 and content[index - 1] == '\\':
            index += 1
          else:
            index += 1 # move past double quote again
            break
        else:
          index += 1

      let token = Token(kind: TK_STRING, value: content.substr(start, index -
          1), location: location)
      location = location.update(token.value)
      tokens.add(token)
    of '(':
      let token = Token(kind: TK_OPEN_PAREN, value: $content[index],
          location: location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of ')':
      let token = Token(kind: TK_CLOSE_PAREN, value: $content[index],
          location: location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of '{':
      let token = Token(kind: TK_OPEN_CURLY, value: $content[index],
          location: location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of '}':
      let token = Token(kind: TK_CLOSE_CURLY, value: $content[index],
          location: location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of '[':
      let token = Token(kind: TK_OPEN_SQUARE, value: $content[index],
          location: location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of ']':
      let token = Token(kind: TK_CLOSE_SQUARE, value: $content[index],
          location: location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of '#':
      let start = index
      # consume everything up until newline
      while index < content.len and content[index] != '\n': index += 1
      let token = Token(kind: TK_COMMENT, value: content.substr(start, index -
          1), location: location)
      location = location.update(token.value)
      tokens.add(token)
    of ' ':
      let token = Token(kind: TK_SPACE, value: $content[index],
          location: location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of '\n':
      let token = Token(kind: TK_NEW_LINE, value: $content[index],
          location: location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of '0'..'9':
      let start = index
      while index < content.len and content[index] in '0'..'9':
        index += 1
      let token = Token(kind: TK_DIGITS, value: content.substr(start, index -
          1), location: location)
      location = location.update(token.value)
      tokens.add(token)
    of 'a'..'z', 'A'..'Z':
      let start = index
      while index < content.len and ((content[index] in 'a'..'z') or (content[
          index] in 'A'..'Z')):
        index += 1
      let token = Token(kind: TK_ALPHABETS, value: content.substr(start, index -
          1), location: location)
      location = location.update(token.value)
      tokens.add(token)
    of '_':
      let token = Token(kind: TK_UNDERSCORE, value: $content[index],
          location: location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    else:
      return err(fmt"{location} Unexpected character `{content[index]}` encountered")

  # NOTE: Adding NEW_LINE Token to indicate end of token stream
  tokens.add(Token(kind: TK_NEW_LINE, value: "\n", location: location))

  ok(tokens)
