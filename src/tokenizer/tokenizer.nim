import results, strformat, unicode, strutils, hashes

const BidiCodepoints: array[11, uint32] = [
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

const ZeroWidthCodepoints: array[4, uint32] = [
  0x200B, # ZERO WIDTH SPACE
  0x200C, # ZERO WIDTH NON-JOINER
  0x200D, # ZERO WIDTH JOINER
  0xFEFF, # BOM / ZERO WIDTH NO-BREAK SPACE
]

const InvisibleCodepoints: array[18, uint32] = [
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

proc isCompilerSafe(r: Rune): Result[void, string] =
  let codepoint = r.uint32
  if codepoint in BidiCodepoints:
    return err(fmt"bidirectional control codepoint U+{codepoint:04X} encountered")
  elif codepoint in ZeroWidthCodepoints:
    return err(fmt"zero-width codepoint U+{codepoint:04X} encountered")
  elif codepoint in InvisibleCodepoints:
    return err(fmt"invisible control codepoint U+{codepoint:04X} encountered")
  else:
    ok()

type Location* = object
  filepath: string
  line: int
  col: int

proc newLocation(filepath: string, line, col: int): Location =
  Location(filepath: filepath, line: line, col: col)

proc newLocation*(filepath: string): Location = newLocation(filepath, 1, 1)

proc newLocation*(): Location = newLocation("", 1, 1)

proc advance(loc: Location, line: bool = false): Location =
  var location = loc
  if line:
    location.line += 1
    location.col = 1
  else:
    location.col += 1
  return location

proc `<`*(a, b: Location): bool =
  if a.line == b.line: a.col < b.col
  else: a.line < b.line

proc hash*(a: Location): Hash =
  a.filepath.hash !& a.line.hash !& a.col.hash

proc `==`*(a, b: Location): bool =
  a.hash == b.hash

proc `$`(loc: Location): string =
  fmt"{loc.line}:{loc.col}"

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
  const Punctuations = "`~!@#$%^&*()-_=+[]{}\\|;:'\",<.>/?"

  var loc = newLocation(filepath)
  var tokens: seq[Token]
  for r in runes(source):
    let maybeValid = isCompilerSafe(r)
    if maybeValid.isErr: return err(fmt"{filepath}:{loc} {maybeValid.error}")

    let kind =
      if r.uint32 > 0x7F: tkUtf8
      elif r.char == ' ': tkSpace
      elif r.char == '\n': tkNewline
      elif r.char in Punctuations: tkPunctuation
      elif r.char.isAlphaAscii: tkAlphabet
      elif r.char.isDigit: tkDigit
      else: return err(fmt"{filepath}:{loc} unknown token `U+{r.uint32:04X}` encountered.")

    let token = newToken(kind, $r, loc)
    loc = loc.advance(r == Rune('\n'))
    tokens.add(token)

  # Normalize trailing newline character handling
  let trailingNewline = newToken(tkNewline, "\n", loc)
  tokens.add(trailingNewline)

  # Dump tokens
  if dumpTokens:
    echo fmt"--- // START {filepath} tokens ({tokens.len}) ---"
    for token in tokens: echo token
    echo fmt"--- // END {filepath} ---"

  ok(tokens)
