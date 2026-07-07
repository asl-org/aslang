import results, strformat, unicode, options

import ./tokenizer/constants
import ./tokenizer/location
import ./tokenizer/token
import ./tokenizer/spec

export location
export token

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

proc peek(tokenizer: Tokenizer): Result[Rune, string] =
  if not tokenizer.done:
    let head = tokenizer.source[tokenizer.index]
    let codepoint = head.uint32
    if codepoint in BidiCodepoints:
      err(fmt"{tokenizer.loc}: bidirectional control codepoint U+{codepoint:04X} encountered")
    elif codepoint in ZeroWidthCodepoints:
      err(fmt"{tokenizer.loc}: zero-width codepoint U+{codepoint:04X} encountered")
    elif codepoint in InvisibleCodepoints:
      err(fmt"{tokenizer.loc}: invisible control codepoint U+{codepoint:04X} encountered")
    else:
      ok(head)
  else:
    err("{tokenizer.loc}: tokenizer reached end of token stream")

proc next(tokenizer: Tokenizer, head: Rune): void =
  tokenizer.index += 1
  tokenizer.loc = tokenizer.loc.advance(head.isNewline)

proc pin(tokenizer: Tokenizer): Result[Location, string] =
  if tokenizer.checkpoint.isNone:
    tokenizer.checkpoint = some((tokenizer.index, tokenizer.loc))
    ok(tokenizer.loc)
  else:
    err(fmt"{tokenizer.loc}: [UNREACHABLE] tokenizer is already pinned")

proc commit(tokenizer: Tokenizer): Result[void, string] =
  if tokenizer.checkpoint.isSome:
    tokenizer.checkpoint = none((int, Location))
    ok()
  else:
    err(fmt"{tokenizer.loc}: [UNREACHABLE] tokenizer is not pinned")

proc rollback(tokenizer: Tokenizer): Result[void, string] =
  if tokenizer.checkpoint.isSome:
    (tokenizer.index, tokenizer.loc) = tokenizer.checkpoint.get
    tokenizer.checkpoint = none((int, Location))
    ok()
  else:
    err(fmt"{tokenizer.loc}: [UNREACHABLE] tokenizer is not pinned")

proc tokenize(tokenizer: Tokenizer, spec: TokenSpec): Result[Token, string] =
  var content: seq[Rune]
  let loc = ? tokenizer.pin()

  var maybeHead = tokenizer.peek
  while maybeHead.isOk and spec.match(maybeHead.get):
    tokenizer.next(maybeHead.get)
    content.add(maybeHead.get)
    case spec.kind:
    of tskIndividual: break
    of tskCollective: maybeHead = tokenizer.peek

  if content.len == 0:
    ? tokenizer.rollback()
    if maybeHead.isOk: err(fmt"{loc}: expected {spec.label}")
    else: err(maybeHead.error)
  else:
    ? tokenizer.commit()
    let token = newToken(spec.tokenKind, $content, loc)
    results.ok(token)

proc tokenize(tokenizer: Tokenizer, specs: seq[TokenSpec]): Result[Token, string] =
  for spec in specs:
    let maybeToken = tokenizer.tokenize(spec)
    if maybeToken.isOk: return maybeToken

  # Peek the current position for a compiler-safety violation before
  # dispatching to specs. Without this pre-check, an unsafe codepoint
  # (BOM, zero-width, bidi, invisible) would flow through each spec's
  # rollback path and surface as a generic "unknown token" error —
  # losing the specific Trojan-Source-defense message peek produces.
  # When peek errs on a safety issue, propagate that error verbatim.
  let head = ? tokenizer.peek
  err(fmt"{tokenizer.loc} unsupported token encountered `U+{head.uint32:04X}`")

proc tokenize*(source: string, filepath: string, dumpTokens: bool = false): Result[seq[Token], string] =
  let specs = @[
    newCollectiveTokenSpec("a utf8 character", tkUtf8, isUtf8),
    newCollectiveTokenSpec("an alphabet", tkAlphabet, isAlphabet),
    newCollectiveTokenSpec("a digit", tkDigit, isDigit),
    newCollectiveTokenSpec("a space", tkSpace, isSpace),
    newCollectiveTokenSpec("a new line", tkNewline, isNewline),
    newIndividualTokenSpec("a punctuation", tkPunctuation, isPunctuation),
  ]

  var tokens: seq[Token]
  var tokenizer = newTokenizer(filepath, source)
  while not tokenizer.done:
    let token = ? tokenizer.tokenize(specs)
    tokens.add(token)

  # Normalize trailing newline character handling
  let trailingNewline = newToken(tkNewline, $Newline, tokenizer.loc)
  tokens.add(trailingNewline)

  # Dump tokens
  if dumpTokens:
    echo fmt"--- // START {filepath} tokens ({tokens.len}) ---"
    for token in tokens: echo token
    echo fmt"--- // END {filepath} ---"

  ok(tokens)
