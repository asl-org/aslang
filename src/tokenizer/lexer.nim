import token
import strutils
import tables
import results
import strformat

type Lexer* = ref object
  source: string
  filename: string
  tokens: seq[Token]
  start: int
  current: int
  line: int
  line_start: int

# --- Keyword Table ---
var keywords: Table[string, TokenKind]
proc init_keywords() =
  keywords = {
    "module": tkModule, "fn": tkFn, "match": tkMatch, "case": tkCase,
    "else": tkElse, "struct": tkStruct, "union": tkUnion, "generic": tkGeneric
  }.to_table
init_keywords()

# --- Forward Declarations ---
proc scan_token(lexer: Lexer): Result[void, string]

# --- Constructor ---
proc new_lexer*(filename: string, source: string): Lexer =
  Lexer(
    filename: filename, source: source, tokens: new_seq[Token](),
    start: 0, current: 0, line: 1, line_start: 0
  )

# --- State & Helpers ---
proc is_at_end(lexer: Lexer): bool = lexer.current >= lexer.source.len
proc advance(lexer: Lexer): char =
  result = lexer.source[lexer.current]
  lexer.current += 1
proc peek(lexer: Lexer): char =
  if lexer.is_at_end(): '\0' else: lexer.source[lexer.current]
proc peek_next(lexer: Lexer): char =
  if lexer.current + 1 >= lexer.source.len: '\0' else: lexer.source[lexer.current + 1]

proc add_token(lexer: Lexer, kind: TokenKind, content_override: string = "") =
  let lexeme = lexer.source.substr(lexer.start, lexer.current - 1)
  let content = if content_override == "": lexeme else: content_override
  let col = lexer.start - lexer.line_start + 1
  let location = Location(filename: lexer.filename, line: lexer.line, col: col)
  let token = new_token(kind, lexeme, content, location)
  lexer.tokens.add(token)

proc match(lexer: Lexer, expected: char): bool =
  if lexer.is_at_end() or lexer.source[lexer.current] != expected: return false
  lexer.current += 1
  true

# --- Parsing Logic for Dynamic Tokens ---
proc parse_string(lexer: Lexer): Result[void, string] =
  while peek(lexer) != '"' and not lexer.is_at_end():
    if peek(lexer) == '\n':
      let col = lexer.start - lexer.line_start + 1
      let loc = Location(filename: lexer.filename, line: lexer.line, col: col)
      return err(fmt"{loc} Error: Newlines are not allowed in strings.")
    discard lexer.advance()

  if lexer.is_at_end():
    let col = lexer.start - lexer.line_start + 1
    let loc = Location(filename: lexer.filename, line: lexer.line, col: col)
    return err(fmt"{loc} Error: Unterminated string.")

  discard lexer.advance()
  # The content is the value inside the quotes.
  let content = lexer.source.substr(lexer.start + 1, lexer.current - 2)
  lexer.add_token(tkString, content)
  ok()

proc parse_number(lexer: Lexer): Result[void, string] =
  while peek(lexer).is_digit(): discard lexer.advance()
  if peek(lexer) == '.' and peek_next(lexer).is_digit():
    discard lexer.advance()
    while peek(lexer).is_digit(): discard lexer.advance()
    lexer.add_token(tkFloat)
  else:
    lexer.add_token(tkInteger)
  ok()

proc parse_identifier(lexer: Lexer): Result[void, string] =
  while peek(lexer).is_alpha_numeric() or peek(lexer) == '_':
    discard lexer.advance()
  let text = lexer.source.substr(lexer.start, lexer.current - 1)
  let kind = keywords.getOrDefault(text, tkIdentifier)
  lexer.add_token(kind)
  ok()

# --- Main Scanning Logic ---
proc scan_tokens*(lexer: Lexer): Result[seq[Token], string] =
  while not lexer.is_at_end():
    lexer.start = lexer.current
    ? lexer.scan_token()

  let eof_loc = Location(filename: lexer.filename, line: lexer.line, col: lexer.current - lexer.line_start + 1)
  # For EOF, lexeme and content are empty.
  lexer.tokens.add(new_token(tkEof, "", "", eof_loc))
  ok(lexer.tokens)

proc scan_token(lexer: Lexer): Result[void, string] =
  let c = lexer.advance()
  case c:
    of '(': lexer.add_token(tkLeftParen)
    of ')': lexer.add_token(tkRightParen)
    of '{': lexer.add_token(tkLeftBrace)
    of '}': lexer.add_token(tkRightBrace)
    of '[': lexer.add_token(tkLeftBracket)
    of ']': lexer.add_token(tkRightBracket)
    of ',': lexer.add_token(tkComma)
    of '.': lexer.add_token(tkDot)
    of '-': lexer.add_token(tkMinus)
    of '+': lexer.add_token(tkPlus)
    of '*': lexer.add_token(tkStar)
    of '/': lexer.add_token(tkSlash)
    of ':': lexer.add_token(tkColon)
    of '=': lexer.add_token(tkEqual)
    of '#': lexer.add_token(tkHashtag)
    of ' ':
      if lexer.match(' '): lexer.add_token(tkIndent)
    of '\n':
      lexer.add_token(tkNewline)
      lexer.line += 1
      lexer.line_start = lexer.current
    of '"': ? lexer.parse_string()
    else:
      if c.is_alpha_ascii(): ? lexer.parse_identifier()
      elif c.is_digit(): ? lexer.parse_number()
      else:
        let col = lexer.start - lexer.line_start + 1
        let loc = Location(filename: lexer.filename, line: lexer.line, col: col)
        return err(fmt"{loc} Error: Unexpected character '{c}'.")
  ok()
