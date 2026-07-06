import unicode

import token

type
  TokenSpecMatcher* = proc(r: Rune): bool {.nimcall.}
  TokenSpecKind* = enum
    tskIndividual, tskCollective
  TokenSpec* = ref object
    label: string
    kind: TokenSpecKind
    tokenKind: TokenKind
    matcher: TokenSpecMatcher

proc newCollectiveTokenSpec*(label: string, tokenKind: TokenKind, matcher: TokenSpecMatcher): TokenSpec =
  TokenSpec(kind: tskCollective, label: label, tokenKind: tokenKind, matcher: matcher)

proc newIndividualTokenSpec*(label: string, tokenKind: TokenKind, matcher: TokenSpecMatcher): TokenSpec =
  TokenSpec(kind: tskIndividual, label: label, tokenKind: tokenKind, matcher: matcher)

proc label*(spec: TokenSpec): string = spec.label
proc kind*(spec: TokenSpec): TokenSpecKind = spec.kind
proc tokenKind*(spec: TokenSpec): TokenKind = spec.tokenKind
proc match*(spec: TokenSpec, r: Rune): bool = spec.matcher(r)
