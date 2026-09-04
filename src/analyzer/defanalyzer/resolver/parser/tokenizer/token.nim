import strformat

import ./location

type TokenKind* = enum
  tkPunctuation, tkSpace, tkNewline, tkAlphabet, tkDigit, tkUtf8, tkString, tkComment

type Token* = ref object
  kind: TokenKind
  value: string
  loc: Location

proc newToken*(kind: TokenKind, value: string, loc: Location): Token =
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