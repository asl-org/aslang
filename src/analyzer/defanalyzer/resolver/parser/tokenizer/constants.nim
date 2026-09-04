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
# `"`, `#` and `_` are intentionally excluded — `"` opens a string, `#` a
# comment, and `_` starts an identifier (all handled by their own specs,
# tried before punctuation), so none is ever a standalone punctuation token.
const Punctuations*: string = "`~!@$%^&*()-=+[]{}\\|;:',<.>/?"
const Space*: string = " "
const Newline*: string = "\n"

const DoubleQuote*: string = "\""
const Backslash*: string = "\\"
const Hash*: string = "#"
# The `\X` escapes ASL recognises inside a string literal. Frozen to
# this set (all also valid, identically-meaning C escapes), so a string
# token can carry its escapes verbatim through to codegen.
const StringEscapes*: array[4, string] = [Backslash, DoubleQuote, "n", "t"]

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

# `[A-Za-z_] [A-Za-z0-9_]*` — an identifier. The head is a letter or
# underscore; tails add digits. Naming rules (length, reserved prefixes)
# are enforced later by `newIdentifier`, not here.
proc consumeIdentifier*(source: seq[Rune], start: int): Result[int, string] =
  let isHead = proc (r: Rune): bool =
    r.uint32 <= AsciiMaxValue and (r.char.isAlphaAscii or r.char == '_')
  let isTail = proc (r: Rune): bool =
    isHead(r) or (r.uint32 <= AsciiMaxValue and r.char.isDigit)
  if start >= source.len or not isHead(source[start]):
    return ok(start)                        # not an identifier → no match
  var index = start + 1
  while index < source.len and isTail(source[index]):
    index += 1
  ok(index)

const Plus*: string = "+"
const Hyphen*: string = "-"
const Dot*: string = "."

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

# `(+|-)? digit+ ("." digit+)? ((e|E) (+|-)? digit+)?` — a numeric float.
# A `.` fraction or an `(e|E)` exponent is required; without either it is a
# plain integer (so consumeFloat is tried before consumeInteger and rolls
# back to no-match here). The sign folds in like consumeInteger.
proc consumeFloat*(source: seq[Rune], start: int): Result[int, string] =
  let isDigit = proc (r: Rune): bool = r.uint32 <= AsciiMaxValue and r.char.isDigit
  var index = start
  if index < source.len and ($(source[index]) == Plus or $(source[index]) == Hyphen):
    index += 1
  let intStart = index
  while index < source.len and source[index].isDigit:
    index += 1
  if index == intStart:
    return ok(start)                        # no leading digit → not a float
  var isFloat = false
  # Fraction: `.` digit+ (a `.` with no digits is not consumed).
  if index < source.len and $(source[index]) == Dot:
    var j = index + 1
    let fracStart = j
    while j < source.len and source[j].isDigit:
      j += 1
    if j > fracStart:
      index = j
      isFloat = true
  # Exponent: (e|E) (+|-)? digit+.
  if index < source.len and ($(source[index]) == "e" or $(source[index]) == "E"):
    var j = index + 1
    if j < source.len and ($(source[j]) == Plus or $(source[j]) == Hyphen):
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
