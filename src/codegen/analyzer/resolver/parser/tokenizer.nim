import results, strformat

import tokenizer/cursor
import tokenizer/constants
import tokenizer/error

import tokenizer/location
export location

import tokenizer/token
export token

proc tokenize(cursor: Cursor, filename: string, content: string): Result[Token, string] =
  if cursor.index < content.len and content[cursor.index] == TAB:
    return err(fmt"{filename}:{cursor} {err_tokenizer_tab_not_allowed(cursor.index)}")

  var errors: seq[Error]
  for (kind, spec) in TOKEN_SPECS:
    let maybe_chunk = spec.match(cursor, content)
    if maybe_chunk.is_ok:
      let chunk = maybe_chunk.get
      let updated_cursor = cursor.update(chunk)
      let location = new_location(filename, cursor, updated_cursor)
      return ok(new_token(kind, chunk, location))
    else:
      errors.add(maybe_chunk.error)

  return err(fmt"{filename}:{cursor} {errors.max()}")

proc tokenize*(filename: string, content: string): Result[seq[Token], string] =
  var cursor = new_cursor()
  var tokens: seq[Token]
  while cursor.index < content.len:
    let token = ? cursor.tokenize(filename, content)
    cursor = token.location.tail
    tokens.add(token)
  ok(tokens)
