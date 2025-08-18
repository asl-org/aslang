import token
import strutils
import tables

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
    "module": Module,
    "fn": Fn,
    "match": Match,
    "case": Case,
    "else": Else,
    "struct": Struct,
    "union": Union,
    "generic": Generic
  }.to_table
init_keywords()

# --- Forward Declarations ---
proc scan_token(lexer: Lexer)

# --- Constructor ---
proc new_lexer*(filename: string, source: string): Lexer =
  Lexer(
    filename: filename,
    source: source,
    tokens: new_seq[Token](),
    start: 0,
    current: 0,
    line: 1,
    line_start: 0
  )

# --- State & Helpers ---
proc is_at_end(lexer: Lexer): bool =
  lexer.current >= lexer.source.len

proc advance(lexer: Lexer): char =
  result = lexer.source[lexer.current]
  lexer.current += 1

proc peek(lexer: Lexer): char =
  if lexer.is_at_end(): return '\0'
  return lexer.source[lexer.current]

proc peek_next(lexer: Lexer): char =
  if lexer.current + 1 >= lexer.source.len: return '\0'
  return lexer.source[lexer.current + 1]

proc add_token(lexer: Lexer, kind: TokenKind) =
  let lexeme = lexer.source.substr(lexer.start, lexer.current - 1)
  let col = lexer.start - lexer.line_start + 1
  let location = Location(filename: lexer.filename, line: lexer.line, col: col)
  lexer.tokens.add(Token(kind: kind, lexeme: lexeme, location: location))

proc match(lexer: Lexer, expected: char): bool =
  if lexer.is_at_end(): return false
  if lexer.source[lexer.current] != expected: return false
  lexer.current += 1
  return true

# --- Parsing Logic for Dynamic Tokens ---
proc parse_string(lexer: Lexer) =
  while peek(lexer) != '"' and not lexer.is_at_end():
    if peek(lexer) == '\n':
      lexer.add_token(Illegal)
      return
    discard lexer.advance()

  if lexer.is_at_end():
    lexer.add_token(Illegal)
    return

  discard lexer.advance()
  lexer.add_token(String)

proc parse_number(lexer: Lexer) =
  while peek(lexer).is_digit():
    discard lexer.advance()

  if peek(lexer) == '.' and peek_next(lexer).is_digit():
    discard lexer.advance()
    while peek(lexer).is_digit():
      discard lexer.advance()
    lexer.add_token(Float)
  else:
    lexer.add_token(Integer)

proc parse_identifier(lexer: Lexer) =
  while peek(lexer).is_alpha_numeric() or peek(lexer) == '_':
    discard lexer.advance()

  let text = lexer.source.substr(lexer.start, lexer.current - 1)
  let kind = keywords.getOrDefault(text, Identifier)
  lexer.add_token(kind)

# --- Main Scanning Logic ---
proc scan_tokens*(lexer: Lexer): seq[Token] =
  while not lexer.is_at_end():
    lexer.start = lexer.current
    scan_token(lexer)

  let eof_loc = Location(filename: lexer.filename, line: lexer.line, col: lexer.current - lexer.line_start + 1)
  lexer.tokens.add(Token(kind: Eof, lexeme: "", location: eof_loc))
  return lexer.tokens

proc scan_token(lexer: Lexer) =
  let c = lexer.advance()
  case c:
    of '(': lexer.add_token(LeftParen)
    of ')': lexer.add_token(RightParen)
    of '{': lexer.add_token(LeftBrace)
    of '}': lexer.add_token(RightBrace)
    of '[': lexer.add_token(LeftBracket)
    of ']': lexer.add_token(RightBracket)
    of ',': lexer.add_token(Comma)
    of '.': lexer.add_token(Dot)
    of '-': lexer.add_token(Minus)
    of '+': lexer.add_token(Plus)
    of '*': lexer.add_token(Star)
    of '/': lexer.add_token(Slash)
    of ':': lexer.add_token(Colon)
    of '=': lexer.add_token(Equal)
    of ' ':
      if lexer.match(' '):
        lexer.add_token(Indent)
      else:
        discard
    of '\n':
      lexer.add_token(Newline)
      lexer.line += 1
      lexer.line_start = lexer.current
    of '"': parse_string(lexer)
    else:
      if c.is_alpha_ascii():
        parse_identifier(lexer)
      elif c.is_digit():
        parse_number(lexer)
      else:
        lexer.add_token(Illegal)
