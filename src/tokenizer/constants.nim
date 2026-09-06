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
const Punctuations*: seq[string] = @["!", "@", ",", "(", ")", "=", "[", "]", "{", "}", ":", "."]
const Space*: string = " "
const Newline*: string = "\n"
const DoubleQuote*: string = "\""
const Backslash*: string = "\\"
const Hash*: string = "#"
const Plus*: string = "+"
const Hyphen*: string = "-"
const Dot*: string = "."
const Underscore*: string = "_"
const NotANumber*: string = "nan"
const Infinite*: string = "inf"
