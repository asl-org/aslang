import strformat, sequtils, strutils, unicode, results, options, tables

# The parser consumes Location (every AST node carries one) from the
# tokenizer, a sibling package, and re-exports it so `import parser`
# brings Location along with the combinator scaffolding — parser
# submodules no longer import `tokenizer/main` separately.
import ../tokenizer/main as tokenizer
export tokenizer

# ============================================================
# Parser Error
# ============================================================

type
  ParserError* = ref object
    loc*: Location
    msg*: string
    fatal*: bool

proc newParserError*(msg: string, loc: Location, fatal: bool = false): ParserError =
  ParserError(msg: msg, loc: loc, fatal: fatal)

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

proc peek(parser: Parser, tokenRepr: string): Result[Token, ParserError] =
  if parser.done():
    let msg = fmt"expected {tokenRepr} but reached end of token stream"
    err(newParserError(msg, parser.loc))
  else:
    ok(parser.tokens[parser.index])

# ============================================================
# Spec[T] — named, typed parser combinator
# ============================================================

type
  Consumer[T] = proc(parser: Parser): Result[T, ParserError]
  Matcher = proc(token: Token): bool
  ResultMapper[T, U] = proc(value: T): Result[U, ParserError]
  Mapper[T, U] = proc(value: T): U
  SpecKind = enum skDefault, skToken
  Spec*[T] = ref object
    name: string
    case kind: SpecKind
    of skDefault: consumer: Consumer[T]
    of skToken: matcher: Matcher

proc newSpec*[T](name: string, consumer: Consumer[T]): Spec[T] =
  Spec[T](kind: skDefault, name: name, consumer: consumer)

proc newSpec*(name: string, matcher: Matcher): Spec[Token] =
  Spec[Token](kind: skToken, name: name, matcher: matcher)

proc newSpec*(name: string, kind: TokenKind): Spec[Token] =
  newSpec(name, proc(t: Token): bool = t.kind == kind)

proc newSpec*(value: string): Spec[Token] =
  newSpec("'" & value & "'", proc(t: Token): bool = t.value == value)

proc expect*[T](parser: Parser, spec: Spec[T]): Result[T, ParserError] =
  let indexCheckpoint = parser.index
  let levelCheckpoint = parser.level
  let maybeValue =
    case spec.kind:
    of skDefault:
      spec.consumer(parser)
    of skToken:
      # A skToken spec is only ever constructed as Spec[Token], so the
      # token-matching arm is compiled only for that instantiation; the
      # generic `expect[T]` (e.g. T = seq[Token] via `any`) never reaches
      # skToken at runtime.
      when T is Token:
        let token = ? parser.peek(spec.name)
        if not spec.matcher(token):
          let msg = fmt"expected {spec.name} but found {token.repr}"
          err(newParserError(msg, parser.loc))
        else:
          parser.index += 1
          ok(token)
      else:
        raiseAssert("[BUG] - skToken spec must be Spec[Token]")

  if maybeValue.isErr:
    parser.index = indexCheckpoint
    parser.level = levelCheckpoint
  return maybeValue

proc expect*(parser: Parser, value: string): Result[Token, ParserError] = parser.expect(newSpec(value))

proc expectOptional[T](parser: Parser, spec: Spec[T]): Result[Option[T], ParserError] =
  let maybeItem = parser.expect(spec)
  if maybeItem.isErr:
    if maybeItem.error.fatal:
      err(maybeItem.error)
    else:
      ok(none(T))
  else:
    ok(some(maybeItem.get))

proc expectAny[T](parser: Parser, spec: Spec[T]): Result[seq[T], ParserError] =
  var items: seq[T]
  var maybeItem = ? parser.expectOptional(spec)
  while maybeItem.isSome:
    items.add(maybeItem.get)
    maybeItem = ? parser.expectOptional(spec)
  ok(items)

proc expectAtLeastOne[T](parser: Parser, spec: Spec[T]): Result[seq[T], ParserError] =
  let first = ? parser.expect(spec)
  var items = @[first]
  let rest = ? parser.expectAny(spec)
  items.add(rest)
  ok(items)

proc expectOneOf[T](parser: Parser, specs: seq[Spec[T]]): Result[T, ParserError] =
  assert(specs.len > 0, "`oneOf` combinator expects at least one spec")
  var errors: seq[ParserError]
  for spec in specs:
    let maybeValue = parser.expect(spec)
    if maybeValue.isOk or maybeValue.error.fatal: return maybeValue
    errors.add(maybeValue.error)
  err(max(errors))

proc any*[T](spec: Spec[T]): Spec[seq[T]] =
  let consumer = proc(parser: Parser): Result[seq[T], ParserError] = parser.expectAny(spec)
  newSpec[seq[T]](spec.name & "*", consumer)

proc atLeastOne*[T](spec: Spec[T]): Spec[seq[T]] =
  let consumer = proc(parser: Parser): Result[seq[T], ParserError] = parser.expectAtLeastOne(spec)
  newSpec[seq[T]](spec.name & "+", consumer)

proc optional*[T](spec: Spec[T]): Spec[Option[T]] =
  let consumer = proc(parser: Parser): Result[Option[T], ParserError] = parser.expectOptional(spec)
  newSpec[Option[T]](spec.name & "?", consumer)

proc oneOf*[T](name: string, specs: seq[Spec[T]]): Spec[T] =
  let variants = specs.mapIt(it.name).join(" | ")
  let consumer = proc(parser: Parser): Result[T, ParserError] = parser.expectOneOf(specs)
  newSpec[T](name & ": " & variants, consumer)

proc map*[T, U](spec: Spec[T], mapper: ResultMapper[T, U]): Spec[U] =
  let consumer = proc(parser: Parser): Result[U, ParserError] = mapper(? parser.expect(spec))
  newSpec[U](spec.name, consumer)

proc map*[T, U](spec: Spec[T], mapper: Mapper[T, U]): Spec[U] =
  let consumer = proc(parser: Parser): Result[U, ParserError] = ok(mapper(? parser.expect(spec)))
  newSpec[U](spec.name, consumer)

proc newSpec*[T](name: string, kind: TokenKind, mapper: ResultMapper[Token, T]): Spec[T] =
  newSpec(name, kind).map(mapper)

proc newSpec*[T](name: string, kind: TokenKind, mapper: Mapper[Token, T]): Spec[T] =
  newSpec(name, kind).map(mapper)

# ============================================================
# Static leaf specs (token-kind + common punctuation)
# ============================================================
#
# Named singletons for grammar files, each a skToken `Spec` built via
# `newSpec`; kept named because grammar code reads better as
# `parser.expect(SPACE)` than `parser.expect(newSpec("space ' '", tkSpace))`.

let SPACE* = newSpec("space ' '", tkSpace)

# space* comment? newline
proc emptyLineConsumer(parser: Parser): Result[Location, ParserError] =
  let loc = parser.loc
  discard ? parser.expect(SPACE.optional())
  discard ? parser.expect(newSpec("comment", tkComment).optional())
  discard ? parser.expect(newSpec("newline '\\n'", tkNewline))
  ok(loc)

let NEWLINE* = newSpec("empty line", emptyLineConsumer)

proc indentationConsumer(parser: Parser): Result[Location, ParserError] =
  let loc = parser.loc
  let maybeSpace = ? parser.expect(SPACE.optional())
  let count: uint32 = if maybeSpace.isSome: maybeSpace.get.value.len.uint32 else: 0
  let expected = parser.indentWidth * parser.level
  if count != expected:
    let msg = fmt"indentation error expected {expected} but found {count} space(s)"
    err(newParserError(msg, loc))
  else:
    ok(loc)

let indentationSpec* = newSpec("indentation", indentationConsumer)

proc wrappedList[O, I, C](opener: Spec[O], item: Spec[I], closer: Spec[C], allowEmpty: bool): Spec[(seq[I], Location)] =
  let listType = if allowEmpty: "list" else: "non-empty list"
  let specName = fmt"comma separated {listType} of {item.name} wrapped in {opener.name} and {closer.name}"
  let consumer =
    proc(parser: Parser): Result[(seq[I], Location), ParserError] =
      let start = ? parser.expect(opener)
      discard ? parser.expect(SPACE.optional())
      var items: seq[I]

      let maybeFirstItem = parser.expect(item)
      if maybeFirstItem.isErr:
        if allowEmpty:
          discard ? parser.expect(closer)
          ok((items, start.loc))
        else:
          err(maybeFirstItem.error)
      else:
        items.add(maybeFirstItem.get)
        discard ? parser.expect(SPACE.optional())
        var maybeComma = parser.expect(",")
        while maybeComma.isOk:
          discard ? parser.expect(SPACE.optional())
          let item = ? parser.expect(item)
          items.add(item)
          discard ? parser.expect(SPACE.optional())
          maybeComma = parser.expect(",")

        discard ? parser.expect(closer)
        ok((items, start.loc))
  newSpec(specName, consumer)

proc squareBracketList*[T](item: Spec[T], allowEmpty: bool = true): Spec[(seq[T], Location)] =
  wrappedList(newSpec("["), item, newSpec("]"), allowEmpty)

proc curlyBracketList*[T](item: Spec[T], allowEmpty: bool = true): Spec[(seq[T], Location)] =
  wrappedList(newSpec("{"), item, newSpec("}"), allowEmpty)

proc parenthesisList*[T](item: Spec[T], allowEmpty: bool = true): Spec[(seq[T], Location)] =
  wrappedList(newSpec("("), item, newSpec(")"), allowEmpty)

proc indentedLine*[T](item: Spec[T]): Spec[T] =
  let consumer =
    proc (parser: Parser): Result[T, ParserError] =
      discard ? parser.expect(indentationSpec)
      let val = ? parser.expect(item)
      discard ? parser.expect(NEWLINE.atLeastOne())
      ok(val)
  newSpec(fmt"indented {item.name}", consumer)

proc indentedBody*[T](parser: Parser, body: Consumer[T]): Result[T, ParserError] =
  ## Run a block body one indent level deeper. The level is always
  ## restored, and a body failure is marked fatal — once the header has
  ## committed the block, it cannot be backtracked out of.
  parser.level += 1
  result = body(parser)
  parser.level -= 1
  if result.isErr: result.error.fatal = true

proc indentedBody*[T](parser: Parser, body: Spec[T]): Result[T, ParserError] =
  ## Spec form of `indentedBody` — expects `body` one indent level deeper.
  parser.indentedBody(proc(parser: Parser): Result[T, ParserError] = parser.expect(body))

proc indentedBlock*[H, B](parser: Parser, header: Spec[H], body: Consumer[B]): Result[(H, B), ParserError] =
  ## A block: a `header` line, then its `body` indented one level deeper
  ## (indentedLine for the header, indentedBody for the body).
  let h = ? parser.expect(header.indentedLine())
  let b = ? parser.indentedBody(body)
  ok((h, b))

proc indentedBlock*[H, B](parser: Parser, header: Spec[H], body: Spec[B]): Result[(H, B), ParserError] =
  ## Spec-body form of `indentedBlock`.
  parser.indentedBlock(header, proc(parser: Parser): Result[B, ParserError] = parser.expect(body))
