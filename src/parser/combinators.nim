import strformat, results, options

import tokenizer

# ============================================================
# Parser Error
# ============================================================

type
  ParserError* = ref object
    loc*: Location
    msg*: string
    fatal*: bool

proc newParserError*(msg: string, loc: Location): ParserError =
  ParserError(msg: msg, loc: loc)

proc `<`*(err1: ParserError, err2: ParserError): bool =
  err1.loc < err2.loc

proc `$`*(error: ParserError): string =
  fmt"{error.loc} {error.msg}"

# ============================================================
# Parser
# ============================================================

type
  Parser* = ref object
    filepath*: string
    indentWidth*: uint32
    tokens: seq[Token]
    index*: int
    level*: uint32

proc newParser*(filepath: string, indentWidth: uint32, tokens: seq[
    Token]): Parser =
  Parser(filepath: filepath, indentWidth: indentWidth, tokens: tokens, index: 0, level: 0)

proc done*(parser: Parser): bool =
  parser.index == parser.tokens.len

proc loc*(parser: Parser): Location =
  if parser.done(): parser.tokens[^1].loc
  else: parser.tokens[parser.index].loc

# ============================================================
# Token consumption
# ============================================================

proc peek*(parser: Parser, tokenRepr: string): Result[Token, ParserError] =
  if parser.done():
    let msg = fmt"expected {tokenRepr} but reached end of token stream"
    err(newParserError(msg, parser.loc))
  else:
    ok(parser.tokens[parser.index])

proc consumeExceptNewline*(parser: Parser,
    tokenRepr: string): Result[Token, ParserError] =
  let token = ? parser.peek(tokenRepr)
  if token.kind == tkNewline:
    let msg = fmt"{token.repr} is not supported as {tokenRepr}"
    err(newParserError(msg, parser.loc))
  else:
    parser.index += 1
    ok(token)

proc consumeTokenKind*(parser: Parser, kind: TokenKind,
    tokenRepr: string): Result[Token, ParserError] =
  let token = ? parser.peek(tokenRepr)
  if token.kind != kind:
    let msg = fmt"expected {tokenRepr} but found {token.repr}"
    err(newParserError(msg, parser.loc))
  else:
    parser.index += 1
    ok(token)

proc consumePunctuation*(parser: Parser,
    value: string): Result[Token, ParserError] =
  let token = ? parser.peek(fmt"punctuation '{value}'")
  if token.kind != tkPunctuation or token.value != value:
    let msg = fmt"expected punctuation '{value}' but found {token.repr}"
    err(newParserError(msg, token.loc))
  else:
    parser.index += 1
    ok(token)

proc consumeSpace*(parser: Parser): Result[Token, ParserError] =
  parser.consumeTokenKind(tkSpace, "space ' '")

# ============================================================
# Spec[T] — named, typed parser combinator
# ============================================================

type
  Spec*[T] = ref object
    name*: string
    parseFn*: proc(parser: Parser): Result[T, ParserError]

proc newSpec*[T](name: string): Spec[T] =
  Spec[T](name: name, parseFn: nil)

proc run*[T](parser: Parser, spec: Spec[T]): Result[T, ParserError] =
  assert spec.parseFn != nil, "spec '" & spec.name & "' has no implementation"
  let indexCheckpoint = parser.index
  let levelCheckpoint = parser.level
  let maybeValue = spec.parseFn(parser)
  if maybeValue.isErr and not maybeValue.error.fatal:
    parser.index = indexCheckpoint
    parser.level = levelCheckpoint
  return maybeValue

# ============================================================
# Combinators
# ============================================================

proc oneOf*[T](name: string, specs: openArray[Spec[T]]): Spec[T] =
  let captured = @specs
  assert captured.len > 0, "oneOf requires at least one alternative"
  Spec[T](
    name: name,
    parseFn: proc(parser: Parser): Result[T, ParserError] =
    var errors: seq[ParserError]
    for spec in captured:
      let maybeValue = parser.run(spec)
      if maybeValue.isOk: return maybeValue
      errors.add(maybeValue.error)
    err(max(errors))
  )

proc any*[T](spec: Spec[T]): Spec[seq[T]] =
  Spec[seq[T]](
    name: spec.name & "*",
    parseFn: proc(parser: Parser): Result[seq[T], ParserError] =
    var items: seq[T]
    while true:
      let maybeValue = parser.run(spec)
      if maybeValue.isErr:
        if maybeValue.error.fatal: return err(maybeValue.error)
        break
      items.add(maybeValue.get)
    ok(items)
  )

proc atLeastOne*[T](spec: Spec[T]): Spec[seq[T]] =
  Spec[seq[T]](
    name: spec.name & "+",
    parseFn: proc(parser: Parser): Result[seq[T], ParserError] =
    let first = ? parser.run(spec)
    var items = @[first]
    let rest = ? parser.run(any(spec))
    items.add(rest)
    ok(items)
  )

proc optional*[T](spec: Spec[T]): Spec[Option[T]] =
  Spec[Option[T]](
    name: spec.name & "?",
    parseFn: proc(parser: Parser): Result[Option[T], ParserError] =
    let maybeValue = parser.run(spec)
    if maybeValue.isErr: ok(none(T))
    else: ok(some(maybeValue.get))
  )

proc map*[T, U](spec: Spec[T], name: string,
    fn: proc(v: T): U): Spec[U] =
  Spec[U](
    name: name,
    parseFn: proc(parser: Parser): Result[U, ParserError] =
    let value = ? parser.run(spec)
    ok(fn(value))
  )

proc separatedBy*[T, S](spec: Spec[T], sep: Spec[S]): Spec[seq[T]] =
  let pairSpec = Spec[T](
    name: spec.name & "_pair",
    parseFn: proc(parser: Parser): Result[T, ParserError] =
    discard ? parser.run(sep)
    let elem = ? parser.run(spec)
    ok(elem)
  )
  Spec[seq[T]](
    name: spec.name & "...",
    parseFn: proc(parser: Parser): Result[seq[T], ParserError] =
    var items: seq[T]
    let first = parser.run(spec)
    if first.isOk:
      items.add(first.get)
      let rest = ? parser.run(any(pairSpec))
      items.add(rest)
    ok(items)
  )

proc contained*[T](name: string, open: string, inner: Spec[T],
    close: string): Spec[T] =
  Spec[T](
    name: name,
    parseFn: proc(parser: Parser): Result[T, ParserError] =
    discard ? parser.consumePunctuation(open)
    while parser.consumeSpace().isOk: discard
    let maybeValue = ? parser.run(inner)
    while parser.consumeSpace().isOk: discard
    discard ? parser.consumePunctuation(close)
    ok(maybeValue)
  )

# ============================================================
# Leaf token specs
# ============================================================

proc tokenSpec*(kind: TokenKind, tokenRepr: string): Spec[Token] =
  Spec[Token](
    name: tokenRepr,
    parseFn: proc(parser: Parser): Result[Token, ParserError] =
    parser.consumeTokenKind(kind, tokenRepr)
  )

proc punctuationSpec*(value: string): Spec[Token] =
  Spec[Token](
    name: "'" & value & "'",
    parseFn: proc(parser: Parser): Result[Token, ParserError] =
    parser.consumePunctuation(value)
  )

proc anyTokenExceptNewlineSpec*(tokenRepr: string): Spec[Token] =
  Spec[Token](
    name: tokenRepr,
    parseFn: proc(parser: Parser): Result[Token, ParserError] =
    parser.consumeExceptNewline(tokenRepr)
  )
