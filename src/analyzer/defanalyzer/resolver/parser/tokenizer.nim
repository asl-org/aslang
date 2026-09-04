import results, strformat, unicode, options

import ./tokenizer/constants
import ./tokenizer/location
import ./tokenizer/token
import ./tokenizer/spec

export location
export token

proc validate(head: Rune, loc: Location): Result[void, string] =
  let codepoint = head.uint32
  if codepoint in BidiCodepoints:
    return err(fmt"{loc}: bidirectional control codepoint U+{codepoint:04X} encountered")
  elif codepoint in ZeroWidthCodepoints:
    return err(fmt"{loc}: zero-width codepoint U+{codepoint:04X} encountered")
  elif codepoint in InvisibleCodepoints:
    return err(fmt"{loc}: invisible control codepoint U+{codepoint:04X} encountered")
  else:
    ok()

type Tokenizer = ref object
  filepath: string
  source: seq[Rune]
  index: int
  loc: Location
  checkpoint: Option[(int, Location)]

proc newTokenizer(filepath: string, source: string): Tokenizer =
  let loc = newLocation(filepath)
  Tokenizer(filepath: filepath, source: source.toRunes, index: 0, loc: loc)

proc done(tokenizer: Tokenizer): bool = tokenizer.index >= tokenizer.source.len

proc unsupported(tokenizer: Tokenizer): string =
  ## The head matched no spec — an ASCII control char (TAB, CR, …) that
  ## is neither space/newline/punctuation nor alphanumeric. No safety
  ## re-check is needed: every Trojan-Source codepoint is > ASCII, so it
  ## is consumed by the utf8 spec and rejected in `commit` before ever
  ## reaching here.
  assert(not tokenizer.done, fmt"{tokenizer.loc}: tokenizer reached end of token stream")
  let head = tokenizer.source[tokenizer.index]
  fmt"{tokenizer.loc} unsupported token encountered `U+{head.uint32:04X}`"

proc pin(tokenizer: Tokenizer): void =
  assert(tokenizer.checkpoint.isNone, fmt"{tokenizer.loc}: [UNREACHABLE] tokenizer is already pinned")
  tokenizer.checkpoint = some((tokenizer.index, tokenizer.loc))

proc commit(tokenizer: Tokenizer, updated: int, kind: TokenKind): Result[Token, string] =
  let start = tokenizer.loc
  assert(tokenizer.checkpoint.isSome, fmt"{start}: [UNREACHABLE] tokenizer is not pinned")
  let content = tokenizer.source[tokenizer.index..<updated]
  for head in content:
    ? head.validate(tokenizer.loc)
    tokenizer.loc = tokenizer.loc.advance(head)

  tokenizer.index = updated
  tokenizer.checkpoint = none((int, Location))
  ok(newToken(kind, $content, start))

proc rollback(tokenizer: Tokenizer, label: string): void =
  assert(tokenizer.checkpoint.isSome, fmt"{tokenizer.loc}: [UNREACHABLE] tokenizer is not pinned")
  (tokenizer.index, tokenizer.loc) = tokenizer.checkpoint.get
  tokenizer.checkpoint = none((int, Location))

proc expect(tokenizer: Tokenizer, spec: TokenSpec): Result[Option[Token], string] =
  # `none` means the spec did not match (the caller should try the next
  # one); an `err` means the spec matched but its content is invalid
  # (e.g. a Trojan-Source codepoint), which must propagate immediately
  # rather than being retried against the remaining specs.
  tokenizer.pin()
  let maybeMatch = spec.match(tokenizer.source, tokenizer.index)
  if maybeMatch.isErr:
    # The spec matched its opening but the content is malformed (e.g. an
    # unterminated string); surface it with the token-start location.
    let message = fmt"{tokenizer.loc}: {maybeMatch.error}"
    tokenizer.rollback(spec.label)
    err(message)
  else:
    let index = maybeMatch.get
    if tokenizer.index == index:
      tokenizer.rollback(spec.label)
      ok(none(Token))
    else:
      let token = ? tokenizer.commit(index, spec.kind)
      ok(some(token))

proc expectOneOf(tokenizer: Tokenizer, specs: seq[TokenSpec]): Result[Token, string] =
  for spec in specs:
    let maybeToken = ? tokenizer.expect(spec)
    if maybeToken.isSome: return ok(maybeToken.get)
  err(tokenizer.unsupported())

proc tokenize*(source: string, filepath: string): Result[seq[Token], string] =
  let specs = @[
    newTokenSpec("a utf8 character", tkUtf8, consumeUtf8),
    newTokenSpec("an alphabet", tkAlphabet, consumeAlphabet),
    newTokenSpec("a float", tkFloat, consumeFloat),
    newTokenSpec("an integer", tkInteger, consumeInteger),
    newTokenSpec("a space", tkSpace, consumeSpace),
    newTokenSpec("a new line", tkNewline, consumeNewline),
    newTokenSpec("a string", tkString, consumeString),
    newTokenSpec("a comment", tkComment, consumeComment),
    newTokenSpec("a punctuation", tkPunctuation, consumePunctuation),
  ]

  var tokens: seq[Token]
  var tokenizer = newTokenizer(filepath, source)
  while not tokenizer.done:
    let token = ? tokenizer.expectOneOf(specs)
    tokens.add(token)

  # Normalize trailing newline character handling
  let trailingNewline = newToken(tkNewline, $Newline, tokenizer.loc)
  tokens.add(trailingNewline)
  ok(tokens)
