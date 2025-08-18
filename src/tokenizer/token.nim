import strformat

# --- Location ---
# Represents a location in the source code for error reporting.
type
  Location* = object
    filename*: string
    line*: int
    col*: int

proc new_location*(filename: string): Location =
  Location(filename: filename, line: 1, col: 1)

proc `$`*(loc: Location): string =
  fmt"{loc.filename}:{loc.line}:{loc.col}"

# --- TokenKind ---
# Enum representing all possible token types in ASLang.
type
  TokenKind* = enum
    # Single-character tokens
    LeftParen, RightParen, LeftBrace, RightBrace, LeftBracket, RightBracket,
    Comma, Dot, Minus, Plus, Slash, Star, Colon, Equal,

    # Literals
    Identifier, String, Integer, Float,

    # Keywords
    Module, Fn, Match, Case, Else, Struct, Union, Generic,

    # Whitespace & Control
    Indent, # Represents two spaces
    Newline,
    Eof,     # End of File
    Illegal  # Represents an unrecognized token

# --- Token ---
# Represents a single token scanned from the source code.
type
  Token* = object
    kind*: TokenKind
    lexeme*: string
    location*: Location

proc `$`*(token: Token): string =
  fmt"[{token.kind:12}] '{token.lexeme}' @ {token.location}"
