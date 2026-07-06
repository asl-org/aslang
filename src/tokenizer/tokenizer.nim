import results, strformat, unicode, sequtils, options

import constants

import location
export location

type TokenKind* = enum
  tkPunctuation, tkSpace, tkNewline, tkAlphabet, tkDigit, tkUtf8

type Token* = ref object
  kind: TokenKind
  value: string
  loc: Location

proc newToken(kind: TokenKind, value: string, loc: Location): Token =
  Token(kind: kind, value: value, loc: loc)

proc kind*(token: Token): TokenKind = token.kind
proc value*(token: Token): string = token.value
proc loc*(token: Token): Location = token.loc

proc repr*(token: Token): string =
  case token.kind:
  of tkNewline: "'\\n'"
  else: fmt"'{token.value}'"

proc `$`*(token: Token): string =
  fmt"{token.loc} {token.kind} {token.repr}"

type Tokenizer = ref object
  filepath: string
  source: seq[Rune]
  index: int
  loc: Location
  checkpoint: Option[(int, Location)]

proc newTokenizer(filepath: string, source: seq[Rune]): Tokenizer =
  let loc = newLocation(filepath)
  Tokenizer(filepath: filepath, source: source, index: 0, loc: loc)

proc done(tokenizer: Tokenizer): bool = tokenizer.index >= tokenizer.source.len

proc pin(tokenizer: Tokenizer): Result[Location, string] =
  if tokenizer.checkpoint.isNone:
    tokenizer.checkpoint = some((tokenizer.index, tokenizer.loc))
    ok(tokenizer.loc)
  else:
    err(fmt"{tokenizer.loc}: tokenizer is already pinned")

proc commit(tokenizer: Tokenizer): Result[void, string] =
  if tokenizer.checkpoint.isSome:
    tokenizer.checkpoint = none((int, Location))
    ok()
  else:
    err(fmt"{tokenizer.loc}: tokenizer is not pinned")

proc rollback(tokenizer: Tokenizer): Result[void, string] =
  if tokenizer.checkpoint.isSome:
    (tokenizer.index, tokenizer.loc) = tokenizer.checkpoint.get
    tokenizer.checkpoint = none((int, Location))
    ok()
  else:
    err(fmt"{tokenizer.loc}: tokenizer is not pinned")

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

type TokenSpec = proc(tokenizer: Tokenizer, start: Location): Result[Token, string] {.nimcall.}

proc tokenizeUtf8(tokenizer: Tokenizer, start: Location): Result[Token, string] =
  var maybeHead = tokenizer.peek
  var content: seq[Rune]
  while maybeHead.isOk and maybeHead.get.isUtf8:
    tokenizer.next(maybeHead.get)
    content.add(maybeHead.get)
    maybeHead = tokenizer.peek
  if content.len == 0: err(fmt"{start}: expected a utf8 character")
  else: ok(newToken(tkUtf8, $content, start))

proc tokenizeSpace(tokenizer: Tokenizer, start: Location): Result[Token, string] =
  var maybeHead = tokenizer.peek
  var content: seq[Rune]
  while maybeHead.isOk and maybeHead.get.isSpace:
    tokenizer.next(maybeHead.get)
    content.add(maybeHead.get)
    maybeHead = tokenizer.peek
  if content.len == 0: err(fmt"{start}: expected a space character")
  else: ok(newToken(tkSpace, $content, start))

proc tokenizeNewLine(tokenizer: Tokenizer, start: Location): Result[Token, string] =
  var maybeHead = tokenizer.peek
  var content: seq[Rune]
  while maybeHead.isOk and maybeHead.get.isNewline:
    tokenizer.next(maybeHead.get)
    content.add(maybeHead.get)
    maybeHead = tokenizer.peek
  if content.len == 0: err(fmt"{start}: expected a new line character")
  else: ok(newToken(tkNewline, $content, start))

proc tokenizePunctuation(tokenizer: Tokenizer, start: Location): Result[Token, string] =
  var maybeHead = tokenizer.peek
  if maybeHead.isOk and maybeHead.get.isPunctuation:
    tokenizer.next(maybeHead.get)
    ok(newToken(tkPunctuation, $(maybeHead.get), start))
  else:
    err(fmt"{start}: expected a punctuation")

proc tokenizeAlphabet(tokenizer: Tokenizer, start: Location): Result[Token, string] =
  var maybeHead = tokenizer.peek
  var content: seq[Rune]
  while maybeHead.isOk and maybeHead.get.isAlphabet:
    tokenizer.next(maybeHead.get)
    content.add(maybeHead.get)
    maybeHead = tokenizer.peek
  if content.len == 0: err(fmt"{start}: expected an alphabet")
  else: ok(newToken(tkAlphabet, $content, start))

proc tokenizeDigit(tokenizer: Tokenizer, start: Location): Result[Token, string] =
  var maybeHead = tokenizer.peek
  var content: seq[Rune]
  while maybeHead.isOk and maybeHead.get.isDigit:
    tokenizer.next(maybeHead.get)
    content.add(maybeHead.get)
    maybeHead = tokenizer.peek
  if content.len == 0: err(fmt"{start}: expected a digit")
  else: ok(newToken(tkDigit, $content, start))

proc tokenize(tokenizer: Tokenizer, specs: seq[TokenSpec]): Result[Token, string] =
  # Sniff the current position for a compiler-safety violation before
  # dispatching to specs. Without this pre-check, an unsafe codepoint
  # (BOM, zero-width, bidi, invisible) would flow through each spec's
  # rollback path and surface as a generic "unknown token" error —
  # losing the specific Trojan-Source-defense message peek produces.
  # When peek errs on a safety issue, propagate that error verbatim.
  let sniff = tokenizer.peek
  if sniff.isErr: return err(sniff.error)

  for spec in specs:
    let start = ? tokenizer.pin()
    let maybeToken = spec(tokenizer, start)
    if maybeToken.isOk:
      ? tokenizer.commit()
      return maybeToken
    else:
      ? tokenizer.rollback()
  err(fmt"{tokenizer.loc} unknown token encountered")

proc tokenize*(source: string, filepath: string, dumpTokens: bool = false): Result[seq[Token], string] =
  let specs = @[
    tokenizeUtf8,
    tokenizeSpace,
    tokenizeNewLine,
    tokenizePunctuation,
    tokenizeAlphabet,
    tokenizeDigit,
  ]

  var tokens: seq[Token]
  var tokenizer = newTokenizer(filepath, source.runes.toSeq)
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
