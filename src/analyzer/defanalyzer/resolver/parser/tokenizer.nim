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

proc pin(tokenizer: Tokenizer): Result[Location, string] =
  if tokenizer.checkpoint.isNone:
    tokenizer.checkpoint = some((tokenizer.index, tokenizer.loc))
    ok(tokenizer.loc)
  else:
    err(fmt"{tokenizer.loc}: [UNREACHABLE] tokenizer is already pinned")

proc commit(tokenizer: Tokenizer, updated: int): Result[string, string] =
  if tokenizer.checkpoint.isSome:
    let content = tokenizer.source[tokenizer.index..<updated]
    for head in content:
      ? head.validate(tokenizer.loc)
      tokenizer.loc = tokenizer.loc.advance(head)

    tokenizer.index = updated
    tokenizer.checkpoint = none((int, Location))
    ok[string]($(content))
  else:
    err(fmt"{tokenizer.loc}: [UNREACHABLE] tokenizer is not pinned")

proc rollback(tokenizer: Tokenizer): Result[void, string] =
  if tokenizer.checkpoint.isSome:
    (tokenizer.index, tokenizer.loc) = tokenizer.checkpoint.get
    tokenizer.checkpoint = none((int, Location))
    ok()
  else:
    err(fmt"{tokenizer.loc}: [UNREACHABLE] tokenizer is not pinned")

proc expect(tokenizer: Tokenizer, spec: TokenSpec): Result[Token, string] =
  let loc = ? tokenizer.pin()
  let index = spec.match(tokenizer.source, tokenizer.index)

  if tokenizer.index == index:
    ? tokenizer.rollback()
    err(fmt"{loc}: expected `{spec.label}`")
  else:
    let value = ? tokenizer.commit(index)
    ok(newToken(spec.kind, value, loc))

proc expectOneOf(tokenizer: Tokenizer, specs: seq[TokenSpec]): Result[Token, string] =
  for spec in specs:
    let maybeToken = tokenizer.expect(spec)
    if maybeToken.isOk: return maybeToken

  # Peek the current position for a compiler-safety violation before
  # dispatching to specs. Without this pre-check, an unsafe codepoint
  # (BOM, zero-width, bidi, invisible) would flow through each spec's
  # rollback path and surface as a generic "unknown token" error —
  # losing the specific Trojan-Source-defense message peek produces.
  # When peek errs on a safety issue, propagate that error verbatim.
  if tokenizer.done:
    err("{tokenizer.loc}: tokenizer reached end of token stream")
  else:
    let head = tokenizer.source[tokenizer.index]
    ? head.validate(tokenizer.loc)
    err(fmt"{tokenizer.loc} unsupported token encountered `U+{head.uint32:04X}`")

proc tokenize*(source: string, filepath: string): Result[seq[Token], string] =
  let specs = @[
    newTokenSpec("a utf8 character", tkUtf8, consumeUtf8),
    newTokenSpec("an alphabet", tkAlphabet, consumeAlphabet),
    newTokenSpec("a digit", tkDigit, consumeDigit),
    newTokenSpec("a space", tkSpace, consumeSpace),
    newTokenSpec("a new line", tkNewline, consumeNewline),
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
