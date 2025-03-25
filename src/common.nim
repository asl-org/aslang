import strformat

type Location* = object
  filename: string
  index: int
  line: int
  column: int

proc `$`(location: Location): string =
  fmt"{location.filename}({location.line}, {location.column})"

type TokenKind* = enum
  TK_ALPHABETS
  TK_DIGITS
  TK_PERIOD
  TK_EQUAL
  TK_SPACE
  TK_NEW_LINE
  TK_UNDERSCORE
  TK_OPEN_PARENTHESIS
  TK_CLOSE_PARENTHESIS

type Token* = object
  kind*: TokenKind
  symbol*: string
  location*: Location

type Cursor* = object
  content: string
  location*: Location

proc new_cursor*(filename, content: string): Cursor =
  let location = Location(filename: filename, index: 0, line: 1, column: 1)
  Cursor(content: content, location: location)

proc can_move*(cursor: Cursor): bool = cursor.location.index < cursor.content.len
proc head*(cursor: Cursor): char = cursor.content[cursor.location.index]
proc move*(cursor: var Cursor): Cursor =
  if cursor.can_move() and cursor.head() == '\n':
    cursor.location.line += 1
    cursor.location.column = 1
  else:
    cursor.location.column += 1
  cursor.location.index += 1
  return cursor
proc chunk*(cursor: Cursor, head: Location): string = cursor.content[head.index..<cursor.location.index]