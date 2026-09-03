import unicode

import ./token

type
  TokenSpecMatcher* = proc(source: seq[Rune], index: int): int {.nimcall.}
  TokenSpec* = ref object
    label: string
    kind: TokenKind
    matcher: TokenSpecMatcher

proc newTokenSpec*(label: string, kind: TokenKind, matcher: TokenSpecMatcher): TokenSpec =
  TokenSpec(label: label, kind: kind, matcher: matcher)

proc label*(spec: TokenSpec): string = spec.label
proc kind*(spec: TokenSpec): TokenKind = spec.kind
proc match*(spec: TokenSpec, source: seq[Rune], start: int): int = spec.matcher(source, start)
