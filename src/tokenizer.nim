import strutils, results, strformat, tables

import common

const Punctuations* = {
  '.'  : TK_PERIOD,
  '='  : TK_EQUAL,
  ','  : TK_COMMA,
  ' '  : TK_SPACE,
  '\n' : TK_NEW_LINE,
  '_'  : TK_UNDERSCORE,
  '('  : TK_OPEN_PARENTHESIS,
  ')'  : TK_CLOSE_PARENTHESIS,
}.to_table

type Cursor = object
  content: string
  location: Location

proc can_move(cursor: Cursor): bool = cursor.location.index < cursor.content.len
proc head(cursor: Cursor): char = cursor.content[cursor.location.index]
proc move(cursor: var Cursor): Cursor =
  if cursor.can_move() and cursor.head() == '\n':
    cursor.location.line += 1
    cursor.location.column = 1
  else:
    cursor.location.column += 1
  cursor.location.index += 1
  return cursor
proc chunk(cursor: Cursor, head: Location): string = cursor.content[head.index..<cursor.location.index]

proc tokenize_alphabets(cursor: var Cursor): Result[Token, string] =
  if not cursor.can_move():
    return err(fmt"Expected alphabets but reached EOF at {cursor.location}")

  let start = cursor.location
  while cursor.can_move() and cursor.head().is_alpha_ascii():
    cursor = cursor.move()

  let alphabets = cursor.chunk(start)
  if alphabets.len == 0:
    cursor.location = start
    return err(fmt"Expected alphabets but found {cursor.head()} at {cursor.location}")

  let token = Token(kind: TokenKind.TK_ALPHABETS, location: start, symbol: alphabets)
  return ok(token)

proc tokenize_digits(cursor: var Cursor): Result[Token, string] =
  if not cursor.can_move():
    return err(fmt"Expected digits but reached EOF at {cursor.location}")

  let start = cursor.location
  while cursor.can_move() and cursor.head().is_digit():
    cursor = cursor.move()

  let digits = cursor.chunk(start)
  if digits.len == 0:
    cursor.location = start
    return err(fmt"Expected digits but found {cursor.head()} at {cursor.location}")

  let token = Token(kind: TokenKind.TK_DIGITS, location: start, symbol: digits)
  return ok(token)

proc tokenize_punctuation(cursor: var Cursor): Result[Token, string] =
  if not cursor.can_move():
    return err(fmt"Expected punctuations but reached EOF at {cursor.location}")

  let start = cursor.location
  for symbol, token_kind in Punctuations.pairs:
    if symbol == cursor.head():
      let token = Token(kind: token_kind, symbol: $symbol, location: start)
      cursor = cursor.move()
      return ok(token)
  return err(fmt"Expected punctuations but found {cursor.head()} at {cursor.location}")

proc tokenize*(filename: string, content: string): Result[seq[Token], string] =
  var tokens: seq[Token] = @[]

  let location = Location(filename: filename, index: 0, line: 1, column: 1)
  var cursor = Cursor(content: content, location: location)

  while cursor.can_move():
    let maybe_alphabets = tokenize_alphabets(cursor)
    if maybe_alphabets.is_ok:
      tokens.add(maybe_alphabets.get)
      continue

    let maybe_digits = tokenize_digits(cursor)
    if maybe_digits.is_ok:
      tokens.add(maybe_digits.get)
      continue

    let maybe_punctuation = tokenize_punctuation(cursor)
    if maybe_punctuation.is_ok:
      tokens.add(maybe_punctuation.get)
      continue

    if cursor.can_move():
      return err(fmt"Expected alphabet/digit/punctuation but found {cursor.head()} at {cursor.location}")
  return ok(tokens)