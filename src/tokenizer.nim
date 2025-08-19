import results, strformat

import blocks/token

type Tokenizer = ref object of RootObj
  index: int = 0
  content: string
  location: Location
  checkpoints: seq[(int, Location)]

proc pin(tokenizer: Tokenizer): Location =
  tokenizer.checkpoints.add((tokenizer.index, tokenizer.location))

proc rollback(tokenizer: Tokenizer, message: string): Result[Token, string] =
  let (prev_index, prev_loc) = tokenizer.checkpoints.pop()
  tokenizer.index = prev_index
  tokenizer.location = prev_loc
  err(message)

proc commit(tokenizer: Tokenizer, value: string, kind: TokenKind): Token =
  let (_, location) = tokenizer.checkpoints.pop()
  tokenizer.index += value.len
  tokenizer.location = tokenizer.location.update(value)
  Token(kind: kind, content: value, location: location)

proc expect(tokenizer: Tokenizer, expected: string): Result[string, string] =
  if tokenizer.index >= tokenizer.content.len:
    return err(fmt"expected '{expected}' but reached end of file")

  let actual = tokenizer.content.substr(tokenizer.index, tokenizer.index +
      expected.len - 1)
  if actual != expected:
    return err(fmt"expected '{expected}' but found '{actual}'")

  return ok(actual)

proc expect(tokenizer: Tokenizer, spec: TokenSpec): Result[Token, string] =
  discard tokenizer.pin()

  let maybe_match =
    case spec.kind:
    of TSK_STATIC: tokenizer.expect(spec.value)
    of TSK_DYNAMIC: spec.matcher(tokenizer.content, tokenizer.index)

  if maybe_match.is_ok:
    return ok(tokenizer.commit(maybe_match.get, spec.token_kind))

  tokenizer.rollback(maybe_match.error)

proc expect_one_of(tokenizer: Tokenizer, specs: seq[TokenSpec]): Result[Token, string] =
  for spec in specs:
    let maybe_match = tokenizer.expect(spec)
    if maybe_match.is_ok: return maybe_match
  err(fmt"{tokenizer.location} could not find matching token spec")

proc tokenize*(filename, content: string): Result[seq[Token], string] =
  var tokens: seq[Token]
  let tokenizer = Tokenizer(content: content, location: new_location(filename))
  while tokenizer.index < tokenizer.content.len:
    let token = ? tokenizer.expect_one_of(TOKEN_SPECS)
    tokens.add(token)
  # Marks end of token stream
  tokens.add(Token(kind: TK_EOF, location: tokenizer.location))
  ok(tokens)
