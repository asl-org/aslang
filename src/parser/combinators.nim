import strformat, results, options

import ./tokenizer

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

proc filepath*(parser: Parser): string = parser.filepath


# ============================================================
# Token consumption
# ============================================================

proc peek*(parser: Parser, tokenRepr: string): Result[Token, ParserError] =
  if parser.done():
    let msg = fmt"expected {tokenRepr} but reached end of token stream"
    err(newParserError(msg, parser.loc))
  else:
    ok(parser.tokens[parser.index])

# ============================================================
# Token matchers — data-driven token consumption
# ============================================================
#
# One `TokenMatcher` record + one `consume` dispatcher replaces the
# family of `consume*` procs that were doing the same work with
# different predicates (consumeTokenKind, consumePunctuation,
# consumeExceptNewline, consumeSpace). Follows the tokenizer's
# `TokenSpec` collapse — the variation (label + predicate) lives in
# data; the shared control flow lives in one place.

type
  TokenMatcher* = ref object
    label: string
    predicate: proc(t: Token): bool

proc byKind*(kind: TokenKind, label: string): TokenMatcher =
  TokenMatcher(label: label,
    predicate: proc(t: Token): bool = t.kind == kind)

proc byPunctuation*(value: string): TokenMatcher =
  TokenMatcher(label: "'" & value & "'",
    predicate: proc(t: Token): bool = t.kind == tkPunctuation and t.value == value)

proc byKindExcept(kind: TokenKind, label: string): TokenMatcher =
  TokenMatcher(label: label,
    predicate: proc(t: Token): bool = t.kind != kind)

let spaceMatcher = byKind(tkSpace, "space ' '")

proc consume*(parser: Parser, matcher: TokenMatcher): Result[Token, ParserError] =
  let token = ? parser.peek(matcher.label)
  if not matcher.predicate(token):
    let msg = fmt"expected {matcher.label} but found {token.repr}"
    err(newParserError(msg, parser.loc))
  else:
    parser.index += 1
    ok(token)

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

proc map*[T, U](spec: Spec[T], name: string,
    fn: proc(v: T): Result[U, ParserError]): Spec[U] =
  Spec[U](
    name: name,
    parseFn: proc(parser: Parser): Result[U, ParserError] =
    let value = ? parser.run(spec)
    fn(value)
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
  let openMatcher = byPunctuation(open)
  let closeMatcher = byPunctuation(close)
  Spec[T](
    name: name,
    parseFn: proc(parser: Parser): Result[T, ParserError] =
    discard ? parser.consume(openMatcher)
    while parser.consume(spaceMatcher).isOk: discard
    let maybeValue = ? parser.run(inner)
    while parser.consume(spaceMatcher).isOk: discard
    discard ? parser.consume(closeMatcher)
    ok(maybeValue)
  )

# ============================================================
# Sequence-composition atoms
# ============================================================
#
# Small vocabulary that lets domain-type specs be built out of
# existing `Spec[T]` values instead of hand-writing a
# `Spec[T](name: ..., parseFn: proc(...): ...)` block every time.
# Same "compose atoms into a grammar" pattern the tokenizer uses
# for its per-kind matchers.

proc prefixed*[P, T](prefix: Spec[P], inner: Spec[T]): Spec[T] =
  ## Parse `prefix inner`; discard prefix, return inner's value.
  ## Common shape: `= expression`, `. identifier`, `: expression`.
  Spec[T](
    name: inner.name,
    parseFn: proc(parser: Parser): Result[T, ParserError] =
      discard ? parser.run(prefix)
      parser.run(inner)
  )

proc suffixed*[T, S](inner: Spec[T], suffix: Spec[S]): Spec[T] =
  ## Parse `inner suffix`; discard suffix, return inner's value.
  Spec[T](
    name: inner.name,
    parseFn: proc(parser: Parser): Result[T, ParserError] =
      let v = ? parser.run(inner)
      discard ? parser.run(suffix)
      ok(v)
  )

proc pair*[A, B](a: Spec[A], b: Spec[B]): Spec[(A, B)] =
  ## Parse `a b`; return `(A, B)`. Chain with `.map` to lift into
  ## a domain type.
  Spec[(A, B)](
    name: a.name & " + " & b.name,
    parseFn: proc(parser: Parser): Result[(A, B), ParserError] =
      let va = ? parser.run(a)
      let vb = ? parser.run(b)
      ok((va, vb))
  )

proc triple*[A, B, C](a: Spec[A], b: Spec[B], c: Spec[C]): Spec[(A, B, C)] =
  ## Parse `a b c`; return `(A, B, C)`. Chain with `.map` to lift.
  Spec[(A, B, C)](
    name: a.name & " + " & b.name & " + " & c.name,
    parseFn: proc(parser: Parser): Result[(A, B, C), ParserError] =
      let va = ? parser.run(a)
      let vb = ? parser.run(b)
      let vc = ? parser.run(c)
      ok((va, vb, vc))
  )

proc presence*[T](spec: Spec[T]): Spec[bool] =
  ## Returns true if `spec` matched, false otherwise. Never errors —
  ## `parser.run(spec)` handles its own rollback on non-fatal failure.
  ## Turns the `let m = parser.run(x); let flag = m.isOk` idiom into
  ## a single composable spec.
  Spec[bool](
    name: spec.name & "?",
    parseFn: proc(parser: Parser): Result[bool, ParserError] =
      let r = parser.run(spec)
      ok(r.isOk)
  )

# ============================================================
# Leaf token specs — one-line wrappers over `matcherSpec`
# ============================================================
#
# Kept as named factories so grammar files read as `punctuationSpec(",")`
# instead of the more verbose `matcherSpec(byPunctuation(","))`. Under
# the hood all three delegate to the single `TokenMatcher` machinery
# above.

proc matcherSpec(matcher: TokenMatcher): Spec[Token] =
  Spec[Token](
    name: matcher.label,
    parseFn: proc(parser: Parser): Result[Token, ParserError] =
      parser.consume(matcher)
  )

proc tokenSpec*(kind: TokenKind, tokenRepr: string): Spec[Token] =
  matcherSpec(byKind(kind, tokenRepr))

proc punctuationSpec*(value: string): Spec[Token] =
  matcherSpec(byPunctuation(value))

proc anyTokenExceptNewlineSpec*(tokenRepr: string): Spec[Token] =
  matcherSpec(byKindExcept(tkNewline, tokenRepr))

# ============================================================
# Static leaf specs (token-kind + common punctuation)
# ============================================================
#
# Named singletons for grammar files. Backed by `matcherSpec` under
# the hood; kept named because grammar code reads better as
# `parser.run(spaceSpec)` than `parser.run(matcherSpec(spaceMatcher))`.

let spaceSpec* = tokenSpec(tkSpace, "space ' '")
let newlineSpec* = tokenSpec(tkNewline, "newline '\\n'")
let alphabetSpec* = tokenSpec(tkAlphabet, "alphabet [a-zA-Z]")
let digitSpec* = tokenSpec(tkDigit, "digit [0-9]")

let underscoreSpec* = punctuationSpec("_")
let hashSpec* = punctuationSpec("#")
let backslashSpec* = punctuationSpec("\\")
let doubleQuoteSpec* = punctuationSpec("\"")

# ============================================================
# Trivia specs — named compositions of the highest-frequency
# discarded-in-grammar idioms.
# ============================================================
#
# `discard parser.run(any(spaceSpec))` etc. shows up 30+ times
# across the parser; naming these makes the intent obvious at
# the call site. The underlying combinators (any, atLeastOne)
# are unchanged — these are pure aliases.
#
# `blankLines` sits with `ignorableLineSpec` below because it
# depends on it; `ws0`/`ws1` live here alongside `spaceSpec`.

let ws0* = any(spaceSpec)               ## zero-or-more spaces
let ws1* = atLeastOne(spaceSpec)        ## one-or-more spaces

# ============================================================
# Comment + ignorable line
# ============================================================

let commentSpec* = Spec[Location](
  name: "comment",
  parseFn: proc(parser: Parser): Result[Location, ParserError] =
  let hashtag = ? parser.run(hashSpec)
  discard parser.run(any(anyTokenExceptNewlineSpec("comment character")))
  ok(hashtag.loc)
)

# space* comment? newline
let ignorableLineSpec* = Spec[Location](
  name: "ignorable_line",
  parseFn: proc(parser: Parser): Result[Location, ParserError] =
  let loc = parser.loc
  discard ? parser.run(ws0)
  discard ? parser.run(optional(commentSpec))
  discard ? parser.run(newlineSpec)
  ok(loc)
)

let blankLines* = any(ignorableLineSpec) ## any number of blank/comment lines

# ============================================================
# Separator helpers
# ============================================================

proc separatorSpec*(sep: string): Spec[Token] =
  Spec[Token](
    name: "'" & sep & "'",
    parseFn: proc(parser: Parser): Result[Token, ParserError] =
    discard ? parser.run(ws0)
    let token = ? parser.run(punctuationSpec(sep))
    discard ? parser.run(ws0)
    ok(token)
  )

let commaWithSpacesSpec* = separatorSpec(",")
let colonWithSpacesSpec* = separatorSpec(":")
let equalsSeparatorSpec* = separatorSpec("=")
