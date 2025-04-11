import strformat

type Location* = object of RootObj
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
    TK_HASHTAG

  Token* = ref object of RootObj
    kind*: TokenKind
    symbol*: string
    location*: Location

proc `$`*(token: Token): string =
  fmt"{token.symbol} {token.kind} {token.location}"

type Identifier* = ref object of RootObj
  name*: string
  location*: Location

proc `$`*(i: Identifier): string = fmt"{i.name}"

type Datatype* = ref object of RootObj
  name*: string
  location*: Location

proc `$`*(d: Datatype): string = fmt"{d.name}"

type
  LiteralKind* = enum
    LK_INTEGER
    LK_FLOAT
    LK_STRING
  Literal* = ref object of RootObj
    location*: Location
    kind*: LiteralKind
    value*: string

proc `$`*(literal: Literal): string =
  fmt"{literal.location} '{literal.value}'"

type
  Variable* = ref object of RootObj
    name*: string
    datatype*: Datatype

proc `$`(v: Variable): string =
  fmt"`{v.datatype} {v.name}`"

type
  ArgumentKind* = enum
    AK_LITERAL
    AK_IDENTIFIER
  Argument* = ref object of RootObj
    location*: Location
    case kind*: ArgumentKind
    of AK_LITERAL:
      literal*: Literal
    of AK_IDENTIFIER:
      identifier*: Identifier

proc `$`*(arg: Argument): string =
  case arg.kind:
  of ArgumentKind.AK_LITERAL:
    fmt"{arg.location} {arg.literal}"
  of ArgumentKind.AK_IDENTIFIER:
    fmt"{arg.location} {arg.identifier}"

type ArgumentList* = ref object of RootObj
  location*: Location
  args*: seq[Argument]

type Initializer* = ref object of RootObj
  location*: Location
  variable*: Variable
  value*: Argument

proc `$`*(i: Initializer): string =
  fmt"{i.location} `{i.variable} = {i.value}`"

type FunctionCall* = ref object of RootObj
  location*: Location
  variable*: Identifier
  name*: string
  arglist*: ArgumentList

proc `$`*(i: FunctionCall): string =
  fmt"{i.location} `{i.variable} = {i.name}(...)`"

type
  StatementKind* = enum
    SK_INIT
    SK_FNCALL
  Statement* = ref object of RootObj
    location*: Location
    case kind*: StatementKind
    of StatementKind.SK_INIT:
      initializer*: Initializer
    of StatementKIND.SK_FNCALL:
      fncall*: FunctionCall

proc `$`*(s: Statement): string =
  case s.kind:
  of StatementKind.SK_INIT:
    fmt"{s.location} {s.initializer}"
  of StatementKind.SK_FNCALL:
    fmt"{s.location} {s.fncall}"

type
  LineKind* = enum
    LK_EMPTY
    LK_COMMENT
    LK_STATEMENT
  Line* = ref object of RootObj
    case kind*: LineKind
    of LK_STATEMENT:
      statement*: Statement
    else: discard


type FunctionDefinition* = ref object of RootObj
  native_function*: string
  result*: Datatype
  args*: seq[Variable]

type Function* = ref object of RootObj
  name*: string
  defs*: seq[FunctionDefinition]
