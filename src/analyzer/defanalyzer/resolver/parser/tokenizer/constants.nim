import unicode, strutils, strformat, results

const BidiCodepoints*: array[11, uint32] = [
  0x200E, # LRM
  0x200F, # RLM
  0x202A, # LRE
  0x202B, # RLE
  0x202C, # PDF
  0x202D, # LRO
  0x202E, # RLO
  0x2066, # LRI
  0x2067, # RLI
  0x2068, # FSI
  0x2069, # PDI
]

const ZeroWidthCodepoints*: array[4, uint32] = [
  0x200B, # ZERO WIDTH SPACE
  0x200C, # ZERO WIDTH NON-JOINER
  0x200D, # ZERO WIDTH JOINER
  0xFEFF, # BOM / ZERO WIDTH NO-BREAK SPACE
]

const InvisibleCodepoints*: array[18, uint32] = [
  0x00AD,                         # SOFT HYPHEN
  0x034F,                         # COMBINING GRAPHEME JOINER
  0x061C,                         # ARABIC LETTER MARK
  0x115F,                         # HANGUL CHOSEONG FILLER
  0x1160,                         # HANGUL JUNGSEONG FILLER
  0x17B4,                         # KHMER VOWEL INHERENT AQ
  0x17B5,                         # KHMER VOWEL INHERENT AA
  0x2060,                         # WORD JOINER
  0x2061, 0x2062, 0x2063, 0x2064, # INVISIBLE MATH OPERATORS
  0x206A, 0x206B, 0x206C, 0x206D, 0x206E, 0x206F, # DEPRECATED FORMATTING
]

const AsciiMaxValue*: uint32 = 0x7F
# `"` and `#` are intentionally excluded — they open a string literal and
# a comment respectively (handled by `consumeString` / `consumeComment`,
# tried before punctuation), so neither is ever a standalone punctuation
# token.
const Punctuations*: string = "`~!@$%^&*()-_=+[]{}\\|;:',<.>/?"
const Space*: string = " "
const Newline*: string = "\n"

const DoubleQuote*: string = "\""
const Backslash*: string = "\\"
const Hash*: string = "#"
# The `\X` escapes ASL recognises inside a string literal. Frozen to
# this set (all also valid, identically-meaning C escapes), so a string
# token can carry its escapes verbatim through to codegen.
const StringEscapes*: array[4, string] = [Backslash, DoubleQuote, "n", "t"]

proc consumeUtf8*(source: seq[Rune], start: int): Result[int, string] =
  var index = start
  while index < source.len and source[index].uint32 > AsciiMaxValue:
    index += 1
  ok(index)

proc consumeSpace*(source: seq[Rune], start: int): Result[int, string] =
  var index = start
  while index < source.len and $(source[index]) == Space:
    index += 1
  ok(index)

proc consumeNewline*(source: seq[Rune], start: int): Result[int, string] =
  var index = start
  while index < source.len and $(source[index]) == Newline:
    index += 1
  ok(index)

proc consumePunctuation*(source: seq[Rune], start: int): Result[int, string] =
  if start < source.len and $(source[start]) in Punctuations:
    ok(start + 1)
  else:
    ok(start)

proc consumeAlphabet*(source: seq[Rune], start: int): Result[int, string] =
  let isAlphabet = proc (r: Rune): bool = r.uint32 <= AsciiMaxValue and r.char.isAlphaAscii
  var index = start
  while index < source.len and source[index].isAlphabet:
    index += 1
  ok(index)

const Plus*: string = "+"
const Hyphen*: string = "-"

# `(+|-)? digit+` — an integer literal with an optional leading sign. The
# sign binds only when digits follow (so `+inf` leaves `+` for
# punctuation); a lone sign consumes nothing.
proc consumeInteger*(source: seq[Rune], start: int): Result[int, string] =
  let isDigit = proc (r: Rune): bool = r.uint32 <= AsciiMaxValue and r.char.isDigit
  var index = start
  if index < source.len and ($(source[index]) == Plus or $(source[index]) == Hyphen):
    index += 1
  let digitsStart = index
  while index < source.len and source[index].isDigit:
    index += 1
  if index == digitsStart:
    return ok(start)                        # no digits → not an integer
  ok(index)

# `"` content* `"` where content is an unescaped rune (not `"`, `\`, or
# newline) or one of the `\X` escapes in StringEscapes. Returns the index
# past the closing quote; errs on an unterminated or badly-escaped string.
proc consumeString*(source: seq[Rune], start: int): Result[int, string] =
  if start >= source.len or $(source[start]) != DoubleQuote:
    return ok(start)                               # not a string → no match
  var index = start + 1
  while index < source.len:
    let head = $(source[index])
    if head == DoubleQuote:
      return ok(index + 1)                         # closing quote
    elif head == Backslash:
      if index + 1 >= source.len:
        return err("unterminated string literal")
      let escape = $(source[index + 1])
      if escape notin StringEscapes:
        return err(fmt"invalid string escape `\{escape}`")
      index += 2
    elif head == Newline:
      return err("unterminated string literal")
    else:
      index += 1
  return err("unterminated string literal")

# `#` then everything up to (but not including) the newline. A comment
# runs to the newline or EOF and is never malformed.
proc consumeComment*(source: seq[Rune], start: int): Result[int, string] =
  if start >= source.len or $(source[start]) != Hash:
    return ok(start)                               # not a comment → no match
  var index = start + 1
  while index < source.len and $(source[index]) != Newline:
    index += 1
  ok(index)
