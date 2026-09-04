import unicode, results

import ./token

type
  # Returns the index one past the match (== start ⇒ no match), or an
  # `err` when a spec matched its opening but the content is malformed
  # (e.g. an unterminated or badly-escaped string).
  TokenSpecMatcher* = proc(source: seq[Rune], index: int): Result[int, string] {.nimcall.}
  TokenSpec* = ref object
    label: string
    kind: TokenKind
    matcher: TokenSpecMatcher

proc newTokenSpec*(label: string, kind: TokenKind, matcher: TokenSpecMatcher): TokenSpec =
  TokenSpec(label: label, kind: kind, matcher: matcher)

proc label*(spec: TokenSpec): string = spec.label
proc kind*(spec: TokenSpec): TokenKind = spec.kind
proc match*(spec: TokenSpec, source: seq[Rune], start: int): Result[int, string] = spec.matcher(source, start)
