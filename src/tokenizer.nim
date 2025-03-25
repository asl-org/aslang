import strutils, results, strformat, tables

import common

const Punctuations* = {
  '.' :TK_PERIOD,
  '=' :TK_EQUAL,
  ' ' :TK_SPACE,
  '\n' :TK_NEW_LINE,
  '_' :TK_UNDERSCORE,
  '(' :TK_OPEN_PARENTHESIS,
  ')' :TK_CLOSE_PARENTHESIS,
}.to_table

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

proc tokenize*(cursor: var Cursor): Result[seq[Token], string] =
  var tokens: seq[Token] = @[]
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