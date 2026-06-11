import results, strformat, unicode, strutils, sequtils

import constants

import location
export location

proc isCompilerSafe(r: Rune): Result[void, string] =
  let codepoint = r.uint32
  if codepoint in BidiCodepoints:
    err(fmt"bidirectional control codepoint U+{codepoint:04X} encountered")
  elif codepoint in ZeroWidthCodepoints:
    err(fmt"zero-width codepoint U+{codepoint:04X} encountered")
  elif codepoint in InvisibleCodepoints:
    err(fmt"invisible control codepoint U+{codepoint:04X} encountered")
  else:
    ok()

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

proc tokenize*(source: string, filepath: string,
    dumpTokens: bool = false): Result[seq[Token], string] =
  var tokens: seq[Token]
  var loc = newLocation(filepath)
  var runes = source.runes.toSeq
  var index = 0
  while index < runes.len:
    let r = runes[index]

    let maybeValid = isCompilerSafe(r)
    if maybeValid.isErr: return err(fmt"{filepath}:{loc} {maybeValid.error}")

    let kind =
      if r.uint32 > AsciiMaxValue: tkUtf8
      elif r.char == Space: tkSpace
      elif r.char == Newline: tkNewline
      elif r.char in Punctuations: tkPunctuation
      elif r.char.isAlphaAscii: tkAlphabet
      elif r.char.isDigit: tkDigit
      else: return err(fmt"{filepath}:{loc} unknown token `U+{r.uint32:04X}` encountered.")

    let token = newToken(kind, $r, loc)
    loc = loc.advance(r == Rune(Newline))
    tokens.add(token)
    index += 1

  # Normalize trailing newline character handling
  let trailingNewline = newToken(tkNewline, $Newline, loc)
  tokens.add(trailingNewline)

  # Dump tokens
  if dumpTokens:
    echo fmt"--- // START {filepath} tokens ({tokens.len}) ---"
    for token in tokens: echo token
    echo fmt"--- // END {filepath} ---"

  ok(tokens)
