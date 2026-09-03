import unicode, strutils

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
const Punctuations*: string = "`~!@#$%^&*()-_=+[]{}\\|;:'\",<.>/?"
const Space*: string = " "
const Newline*: string = "\n"

proc consumeUtf8*(source: seq[Rune], start: int): int =
  var index = start
  while index < source.len and source[index].uint32 > AsciiMaxValue:
    index += 1
  return index

proc consumeSpace*(source: seq[Rune], start: int): int =
  var index = start
  while index < source.len and $(source[index]) == Space:
    index += 1
  return index

proc consumeNewline*(source: seq[Rune], start: int): int =
  var index = start
  while index < source.len and $(source[index]) == Newline:
    index += 1
  return index

proc consumePunctuation*(source: seq[Rune], start: int): int =
  var index = start
  if index < source.len and $(source[index]) in Punctuations:
    index + 1
  else:
    index

proc consumeAlphabet*(source: seq[Rune], start: int): int =
  let isAlphabet = proc (r: Rune): bool = r.uint32 <= AsciiMaxValue and r.char.isAlphaAscii
  var index = start
  while index < source.len and source[index].isAlphabet:
    index += 1
  return index

proc consumeDigit*(source: seq[Rune], start: int): int =
  let isDigit = proc (r: Rune): bool = r.uint32 <= AsciiMaxValue and r.char.isDigit
  var index = start
  while index < source.len and source[index].isDigit:
    index += 1
  return index
