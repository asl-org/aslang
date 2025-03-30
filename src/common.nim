import strformat

type Location* = object
  filename*: string
  index*: int
  line*: int
  column*: int

proc `$`(location: Location): string =
  fmt"{location.filename}({location.line}, {location.column})"

type
  TokenKind* = enum
    TK_ALPHABETS
    TK_DIGITS
    TK_PERIOD
    TK_EQUAL
    TK_COMMA
    TK_SPACE
    TK_NEW_LINE
    TK_UNDERSCORE
    TK_OPEN_PARENTHESIS
    TK_CLOSE_PARENTHESIS

  Token* = object
    kind*: TokenKind
    symbol*: string
    location*: Location

proc `$`*(token: Token): string =
  fmt"{token.symbol} {token.kind} {token.location}"

type
  Identifier* = object
    name*: string
    location*: Location

  Datatype* = object
    refs*: seq[Identifier]
    location*: Location

  LiteralKind* = enum
    LK_INTEGER
    LK_FLOAT
    LK_STRING
  Literal* = object
    location*: Location
    case kind*: LiteralKind
    of LK_INTEGER:
      int_value*: uint64
    of LK_FLOAT:
      float_value*: float64
    of LK_STRING:
      str_value*: string

  ArgumentKind* = enum
    AK_LITERAL
    AK_IDENTIFIER
  Argument* = object
    location*: Location
    case kind*: ArgumentKind
    of AK_LITERAL:
      literal*: Literal
    of AK_IDENTIFIER:
      identifier*: Identifier
  ArgumentList* = object
    location*: Location
    args*: seq[Argument]

  Initializer* = object
    location*: Location
    datatype*: Datatype
    variable*: Identifier
    literal*: Literal

  FunctionCall* = object
    location*: Location
    variable*: Identifier
    name*: Identifier
    arglist*: ArgumentList

  StatementKind* = enum
    SK_INIT
    SK_FNCALL
  Statement* = object
    location*: Location
    case kind*: StatementKind
    of StatementKind.SK_INIT:
      initializer*: Initializer
    of StatementKIND.SK_FNCALL:
      fncall*: FunctionCall
