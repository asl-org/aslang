import unicode, results, strutils, strformat

import constants
import token

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

# The `\X` escapes ASL recognises inside a string literal. Frozen to
# this set (all also valid, identically-meaning C escapes), so a string
# token can carry its escapes verbatim through to codegen.

proc isAscii(r: Rune): bool = r.uint32 <= AsciiMaxValue
proc isSpace(r: Rune): bool = $(r) == Space
proc isNewline(r: Rune): bool = $(r) == Newline
proc isUnderscore(r: Rune): bool = $(r) == Underscore
proc isHash(r: Rune): bool = $(r) == Hash
proc isDoubleQuote(r: Rune): bool = $(r) == DoubleQuote
proc isBackslash(r: Rune): bool = $(r) == Backslash
proc isEscapableChar(r: Rune): bool = $(r) in @[Backslash, DoubleQuote, "n", "t"]
proc isPunctuation(r: Rune): bool = $(r) in Punctuations
proc isSign(r: Rune): bool = $(r) in @[Plus, Hyphen]
proc isDot(r: Rune): bool = $(r) == Dot
proc isAlphabet(r: Rune): bool = r.isAscii and r.char.isAlphaAscii
proc isDigit(r: Rune): bool = r.isAscii and r.char.isDigit
proc isExponent(r: Rune): bool = $(r) in @["e", "E"]
proc isIdentifierHead(r: Rune): bool = r.isAlphabet or r.isUnderscore
proc isIdentifierTail(r: Rune): bool = r.isIdentifierHead or r.isDigit

# A whole-word match ends at EOF or a non-identifier-tail rune, so a
# reserved word like `inf` / `nan` matches but `infinity` / `nano` do not.
proc isWordEnd(source: seq[Rune], index: int): bool =
  index >= source.len or not source[index].isIdentifierTail

proc consumeSpace(source: seq[Rune], start: int): Result[int, string] =
  var index = start
  while index < source.len and source[index].isSpace:
    index += 1
  ok(index)

proc consumeNewline(source: seq[Rune], start: int): Result[int, string] =
  var index = start
  while index < source.len and source[index].isNewline:
    index += 1
  ok(index)

proc consumePunctuation(source: seq[Rune], start: int): Result[int, string] =
  if start < source.len and source[start].isPunctuation:
    ok(start + 1)
  else:
    ok(start)

# `[A-Za-z_] [A-Za-z0-9_]*` — an identifier. The head is a letter or
# underscore; tails add digits. Naming rules (length, reserved prefixes)
# are enforced later by `newIdentifier`, not here.
proc consumeIdentifier(source: seq[Rune], start: int): Result[int, string] =
  if start >= source.len or not source[start].isIdentifierHead:
    ok(start)                        # not an identifier → no match
  else:
    var index = start + 1
    while index < source.len and source[index].isIdentifierTail:
      index += 1
    ok(index)

# `(+|-)? digit+` — an integer literal with an optional leading sign. The
# sign binds only when digits follow (so `+inf` leaves `+` for
# punctuation); a lone sign consumes nothing.
proc consumeInteger(source: seq[Rune], start: int): Result[int, string] =
  var index = start
  if index < source.len and source[index].isSign:
    index += 1

  let digitsStart = index
  while index < source.len and source[index].isDigit:
    index += 1
  if index == digitsStart:
    ok(start)                        # no digits → not an integer
  else:
    ok(index)

# `(+|-)? digit+ ("." digit+)? ((e|E) (+|-)? digit+)?` — a numeric float.
# A `.` fraction or an `(e|E)` exponent is required; without either it is a
# plain integer (so consumeFloat is tried before consumeInteger and rolls
# back to no-match here). The sign folds in like consumeInteger.
proc consumeFloat(source: seq[Rune], start: int): Result[int, string] =
  var index = start
  if index + NotANumber.len <= source.len and $(source[index..<(index + NotANumber.len)]) == NotANumber and isWordEnd(source, index + NotANumber.len):
    ok(index + NotANumber.len)
  else:
    if index < source.len and source[index].isSign:
      index += 1
    # Special IEEE-754 values: `(+|-)?inf` and bare `nan`. `nan` takes no
    # sign (`+nan` / `-nan` are not float literals), so it only matches when
    # no sign was consumed (index still at start).
    if index + Infinite.len <= source.len and $(source[index..<(index + Infinite.len)]) == Infinite and isWordEnd(source, index + Infinite.len):
      ok(index + Infinite.len)
    else:
      let intStart = index
      while index < source.len and source[index].isDigit:
        index += 1
      if index == intStart:
        ok(start)                        # no leading digit and not inf/nan → not a float
      else:
        var isFloat = false
        # Fraction: `.` digit+ (a `.` with no digits is not consumed).
        if index < source.len and source[index].isDot:
          var j = index + 1
          let fracStart = j
          while j < source.len and source[j].isDigit:
            j += 1
          if j > fracStart:
            index = j
            isFloat = true
        # Exponent: (e|E) (+|-)? digit+.
        if index < source.len and source[index].isExponent:
          var j = index + 1
          if j < source.len and source[j].isSign:
            j += 1
          let expStart = j
          while j < source.len and source[j].isDigit:
            j += 1
          if j > expStart:
            index = j
            isFloat = true
        if isFloat: ok(index) else: ok(start)     # no `.`/`e` → leave for integer

# `"` content* `"` where content is an unescaped rune (not `"`, `\`, or
# newline) or one of the `\X` escapes in StringEscapes. Returns the index
# past the closing quote; errs on an unterminated or badly-escaped string.
proc consumeString(source: seq[Rune], start: int): Result[int, string] =
  if start >= source.len or not source[start].isDoubleQuote:
    ok(start)                               # not a string → no match
  else:
    var index = start + 1
    while index < source.len:
      if source[index].isDoubleQuote:
        return ok(index + 1)                         # closing quote
      elif source[index].isBackslash:
        if index + 1 >= source.len:
          return err("unterminated string literal")
        elif not source[index + 1].isEscapableChar:
          return err(fmt"invalid string escape `\{source[index + 1]}`")
        index += 2
      elif source[index].isNewline:
        return err("unterminated string literal")
      else:
        index += 1
    err("unterminated string literal")

# `#` then everything up to (but not including) the newline. A comment
# runs to the newline or EOF and is never malformed.
proc consumeComment(source: seq[Rune], start: int): Result[int, string] =
  if start >= source.len or not source[start].isHash:
    ok(start)                               # not a comment → no match
  else:
    var index = start + 1
    while index < source.len and not source[index].isNewline:
      index += 1
    ok(index)

let TOKEN_SPECS* = @[
    # `float` MUST precede `identifier` and `integer`. It owns the special
    # values `nan` / `inf` / `+inf` / `-inf` (which would otherwise scan as
    # an identifier), and it shares the `(+|-)?digit+` prefix with integer —
    # `consumeFloat` rolls back to a no-match when there is neither a special
    # value nor a `.`/`e`, letting the later specs take the token.
    newTokenSpec("a float", tkFloat, consumeFloat),
    newTokenSpec("an identifier", tkIdentifier, consumeIdentifier),
    newTokenSpec("a string", tkString, consumeString),
    newTokenSpec("an integer", tkInteger, consumeInteger),
    newTokenSpec("a comment", tkComment, consumeComment),
    newTokenSpec("a punctuation", tkPunctuation, consumePunctuation),
    newTokenSpec("a space", tkSpace, consumeSpace),
    newTokenSpec("a new line", tkNewline, consumeNewline),
  ]