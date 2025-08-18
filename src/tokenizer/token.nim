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
    tkLeftParen, tkRightParen, tkLeftBrace, tkRightBrace, tkLeftBracket, tkRightBracket,
    tkComma, tkDot, tkMinus, tkPlus, tkSlash, tkStar, tkColon, tkEqual,

    # Literals
    tkIdentifier, tkString, tkInteger, tkFloat,

    # Keywords
    tkModule, tkFn, tkMatch, tkCase, tkElse, tkStruct, tkUnion, tkGeneric,

    # Whitespace & Control
    tkIndent, # Represents two spaces
    tkNewline,
    tkEof,     # End of File
    tkIllegal  # Represents an unrecognized token

# --- Token ---
# Represents a single token scanned from the source code.
type
  Token* = object
    kind*: TokenKind
    lexeme*: string
    location*: Location

proc `$`*(token: Token): string =
  fmt"[{token.kind:12}] '{token.lexeme}' @ {token.location}"
