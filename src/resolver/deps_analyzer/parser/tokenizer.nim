import results

import tokenizer/cursor

import tokenizer/location
export location

import tokenizer/token
export token

proc tokenize*(filename: string, content: string): Result[seq[Token], string] =
  var head = Cursor()
  var tokens: seq[Token]
  while head.index < content.len:
    for (kind, spec) in TOKEN_SPECS:
      let maybe_match = spec.match(head, content)
      if maybe_match.is_err: continue

      let chunk = maybe_match.get
      let tail = head.update(chunk)
      let location = new_location(filename, head, tail)
      tokens.add(new_token(kind, chunk, location))
      head = tail
  ok(tokens)
