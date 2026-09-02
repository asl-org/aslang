import strformat, sequtils, strutils, unicode, results, options, tables, os

# Location is re-exported so downstream layers (resolver, analyzer,
# tests) can consume it via a single `import parser` — it's part of
# the parser's public surface (every AST node carries one). The rest
# of the tokenizer (Token, TokenKind, tokenize) stays private to the
# parser layer.
import ./parser/tokenizer
export tokenizer.location

# combinators.nim (Spec[T] + oneOf / any / pair / ...) is
# imported but NOT re-exported. It's parser-internal scaffolding.
# Downstream layers (resolver, analyzer, cli, asl.nim) consume the
# parser through the AST types + `parse*` entry point below; the
# combinator machinery has no callers outside the parser layer.
# Parser tests that need it import `./parser/combinators` directly.

import ./parser/identifiers
export identifiers

import ./parser/literals
export literals

import ./parser/imports
export imports

import ./parser/argtype
export argtype

import ./parser/refs
export refs

import ./parser/datadef
export datadef

import ./parser/statement
export statement

import ./parser/function
export function

import ./parser/types
export types

import ./parser/app
export app

# import ./parser/combinators
# export combinators
import ./parser/error
import ./parser/decorator
import ./parser/utils

type File = app.File

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

proc done(parser: Parser): bool =
  parser.index == parser.tokens.len

proc loc(parser: Parser): Location =
  if parser.done(): parser.tokens[^1].loc
  else: parser.tokens[parser.index].loc

proc peek(parser: Parser, tokenRepr: string): Result[Token, ParserError] =
  if parser.done():
    let msg = fmt"expected {tokenRepr} but reached end of token stream"
    err(newParserError(msg, parser.loc))
  else:
    ok(parser.tokens[parser.index])

type
  TokenMatcher* = ref object
    label: string
    predicate: proc(t: Token): bool

proc byKind(kind: TokenKind, label: string): TokenMatcher =
  TokenMatcher(label: label,
    predicate: proc(t: Token): bool = t.kind == kind)

proc byPunctuation(value: string): TokenMatcher =
  TokenMatcher(label: "'" & value & "'",
    predicate: proc(t: Token): bool = t.kind == tkPunctuation and t.value == value)

proc byKindExcept(kind: TokenKind, label: string): TokenMatcher =
  TokenMatcher(label: label,
    predicate: proc(t: Token): bool = t.kind != kind)

proc consume(parser: Parser, matcher: TokenMatcher): Result[Token, ParserError] =
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
  Consumer[T] = proc(parser: Parser): Result[T, ParserError]
  Mapper[T, U] = proc(value: T): Result[U, ParserError]
  SpecKind = enum skOne, skAtLeastOne, skOneOf, skOptional
  Spec*[T] = ref object
    name: string
    consumer: Consumer[T]

proc newSpec[T](name: string, consumer: Consumer): Spec[T] =
  Spec[T](name: name, consumer: consumer)

proc expect[T](parser: Parser, consumer: Consumer[T]): Result[T, ParserError] =
  let indexCheckpoint = parser.index
  let levelCheckpoint = parser.level
  let maybeValue = consumer(parser)
  if maybeValue.isErr and not maybeValue.error.fatal:
    parser.index = indexCheckpoint
    parser.level = levelCheckpoint
  return maybeValue

proc expectOptional[T](parser: Parser, consumer: Consumer[T]): Result[Option[T], ParserError] =
  let maybeItem = parser.expect(consumer)
  if maybeItem.isErr:
    if maybeItem.error.fatal:
      err(maybeItem.error)
    else:
      ok(none(T))
  else:
    ok(some(maybeItem.get))

proc expectAny[T](parser: Parser, consumer: Consumer[T]): Result[seq[T], ParserError] =
  var items: seq[T]
  var maybeItem = parser.expect(consumer)
  while maybeItem.isOk:
    items.add(maybeItem.get)
    maybeItem = parser.expect(consumer)
  if maybeItem.isErr and maybeItem.error.fatal:
    err(maybeItem.error)
  else:
    ok(items)

proc expectAtLeastOne[T](parser: Parser, consumer: Consumer[T]): Result[seq[T], ParserError] =
  let first = ? parser.expect(consumer)
  var items = @[first]
  let rest = ? parser.expectAny(consumer)
  items.add(rest)
  ok(items)

proc expectOneOf[T](parser: Parser, consumers: seq[Consumer[T]]): Result[T, ParserError] =
  var errors: seq[ParserError]
  for consumer in consumers:
    let maybeValue = parser.expect(consumer)
    if maybeValue.isOk: return maybeValue
    errors.add(maybeValue.error)
  err(max(errors))

proc run*[T](parser: Parser, spec: Spec[T]): Result[T, ParserError] =
  parser.expect(spec.consumer)

proc runOptional[T](parser: Parser, spec: Spec[T]): Result[Option[T], ParserError] =
  parser.expectOptional(spec.consumer)

# ============================================================
# Combinators
# ============================================================

proc oneOf*[T](name: string, specs: openArray[Spec[T]]): Spec[T] =
  let captured = @specs
  assert captured.len > 0, "oneOf requires at least one alternative"
  let consumer = proc(parser: Parser): Result[T, ParserError] = parser.expectOneOf(captured.mapIt(it.consumer))
  newSpec[T](name, consumer)

proc any*[T](spec: Spec[T]): Spec[seq[T]] =
  let consumer = proc(parser: Parser): Result[seq[T], ParserError] = parser.expectAny(spec.consumer)
  newSpec[seq[T]](spec.name & "*", consumer)

proc atLeastOne*[T](spec: Spec[T]): Spec[seq[T]] =
  let consumer = proc(parser: Parser): Result[seq[T], ParserError] = parser.expectAtLeastOne(spec.consumer)
  newSpec[seq[T]](spec.name & "+", consumer)

proc optional*[T](spec: Spec[T]): Spec[Option[T]] =
  let consumer = proc(parser: Parser): Result[Option[T], ParserError] = parser.expectOptional(spec.consumer)
  newSpec[Option[T]](spec.name & "?", consumer)

proc map*[T, U](spec: Spec[T], name: string, mapper: Mapper[T, U]): Spec[U] =
  let consumer = proc(parser: Parser): Result[U, ParserError] = mapper(? parser.run(spec))
  newSpec[U](name, consumer)

proc separatedBy*[T, S](spec: Spec[T], sep: Spec[S]): Spec[seq[T]] =
  let pairConsumer =
    proc(parser: Parser): Result[T, ParserError] =
      discard ? parser.run(sep)
      let elem = ? parser.run(spec)
      ok(elem)
  let pairSpec = newSpec[T](spec.name & "_pair", pairConsumer)

  let consumer =
    proc(parser: Parser): Result[seq[T], ParserError] =
      var items: seq[T]
      let first = parser.run(spec)
      if first.isOk:
        items.add(first.get)
        let rest = ? parser.run(any(pairSpec))
        items.add(rest)
      ok(items)
  newSpec[seq[T]](spec.name & "...", consumer)

# ============================================================
# Sequence-composition atoms
# ============================================================
#
# Small vocabulary that lets domain-type specs be built out of
# existing `Spec[T]` values instead of hand-writing a
# `newSpec[T](name, proc(...): ...)` block every time.
# Same "compose atoms into a grammar" pattern the tokenizer uses
# for its per-kind matchers.

proc pair*[A, B](a: Spec[A], b: Spec[B]): Spec[(A, B)] =
  ## Parse `a b`; return `(A, B)`. Chain with `.map` to lift into
  ## a domain type.
  let consumer =
    proc(parser: Parser): Result[(A, B), ParserError] =
      let va = ? parser.run(a)
      let vb = ? parser.run(b)
      ok((va, vb))
  newSpec[(A, B)](a.name & " + " & b.name, consumer)

proc separated*[A, S, B](a: Spec[A], sep: Spec[S], b: Spec[B]): Spec[(A, B)] =
  ## Parse `a sep b`; discard the separator, return `(A, B)`. Reads
  ## like the grammar rule "a separated-by sep from b". Pairs `a` with
  ## a `sep`-then-`b` spec, so the separator is consumed but dropped.
  let consumer =
    proc(parser: Parser): Result[B, ParserError] =
      discard ? parser.run(sep)
      parser.run(b)
  let rest = newSpec[B](b.name, consumer)
  pair(a, rest)

proc triple*[A, B, C](a: Spec[A], b: Spec[B], c: Spec[C]): Spec[(A, B, C)] =
  ## Parse `a b c`; return `(A, B, C)`. Chain with `.map` to lift.
  let consumer =
    proc(parser: Parser): Result[(A, B, C), ParserError] =
      let va = ? parser.run(a)
      let vb = ? parser.run(b)
      let vc = ? parser.run(c)
      ok((va, vb, vc))
  newSpec[(A, B, C)](a.name & " + " & b.name & " + " & c.name, consumer)

proc presence*[T](spec: Spec[T]): Spec[bool] =
  ## Returns true if `spec` matched, false otherwise. Never errors —
  ## `parser.run(spec)` handles its own rollback on non-fatal failure.
  ## Turns the `let m = parser.run(x); let flag = m.isOk` idiom into
  ## a single composable spec.
  let consumer = proc(parser: Parser): Result[bool, ParserError] = ok(parser.run(spec).isOk)
  newSpec[bool](spec.name & "?", consumer)

# ============================================================
# Leaf token specs — one-line wrappers over `matcherSpec`
# ============================================================
#
# Kept as named factories so grammar files read as `punctuationSpec(",")`
# instead of the more verbose `matcherSpec(byPunctuation(","))`. Under
# the hood all three delegate to the single `TokenMatcher` machinery
# above.

proc matcherSpec(matcher: TokenMatcher): Spec[Token] =
  let consumer = proc(parser: Parser): Result[Token, ParserError] = parser.consume(matcher)
  newSpec[Token](matcher.label, consumer)

proc tokenSpec*(kind: TokenKind, tokenRepr: string): Spec[Token] =
  matcherSpec(byKind(kind, tokenRepr))

proc punctuationSpec*(value: string): Spec[Token] =
  matcherSpec(byPunctuation(value))

proc anyTokenExceptNewlineSpec(tokenRepr: string): Spec[Token] =
  matcherSpec(byKindExcept(tkNewline, tokenRepr))

# ============================================================
# Static leaf specs (token-kind + common punctuation)
# ============================================================
#
# Named singletons for grammar files. Backed by `matcherSpec` under
# the hood; kept named because grammar code reads better as
# `parser.run(spaceSpec)` than `parser.run(matcherSpec(byKind(...)))`.

let spaceSpec* = tokenSpec(tkSpace, "space ' '")
let newlineSpec* = tokenSpec(tkNewline, "newline '\\n'")
let alphabetSpec* = tokenSpec(tkAlphabet, "alphabet [a-zA-Z]")
let digitSpec* = tokenSpec(tkDigit, "digit [0-9]")

let underscoreSpec* = punctuationSpec("_")
let hashSpec* = punctuationSpec("#")
let backslashSpec* = punctuationSpec("\\")
let doubleQuoteSpec* = punctuationSpec("\"")
let bangSpec* = punctuationSpec("!")

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

proc contained*[T](name: string, open: string, inner: Spec[T],
    close: string): Spec[T] =
  ## Parse `open ws0 inner ws0 close`; return only inner. Grammar
  ## brackets tolerate whitespace on both sides of the content.
  let head = pair(punctuationSpec(open), any(spaceSpec))
  let tail = pair(any(spaceSpec), punctuationSpec(close))

  let consumer =
    proc(parser: Parser): Result[T, ParserError] =
      discard ? parser.run(head)
      let v = ? parser.run(inner)
      discard ? parser.run(tail)
      ok(v)
  newSpec[T](name, consumer)

# ============================================================
# Comment + ignorable line
# ============================================================

proc commentConsumer(parser: Parser): Result[Location, ParserError] =
  let hashtag = ? parser.run(hashSpec)
  discard parser.run(any(anyTokenExceptNewlineSpec("comment character")))
  ok(hashtag.loc)

let commentSpec = newSpec[Location]("comment", commentConsumer)

# space* comment? newline
proc emptyLineConsumer(parser: Parser): Result[Location, ParserError] =
  let loc = parser.loc
  discard ? parser.run(ws0)
  discard ? parser.runOptional(commentSpec)
  discard ? parser.run(newlineSpec)
  ok(loc)

let emptyLineSpec = newSpec[Location]("empty line", emptyLineConsumer)

# ============================================================
# Separator helpers
# ============================================================

proc separatorSpec(sep: string): Spec[Token] =
  ## Parse `ws0 sep ws0`; return the sep token. Whitespace-tolerant
  ## on both sides of the punctuation.
  let consumer =
    proc(parser: Parser): Result[Token, ParserError] =
      discard ? parser.run(ws0)
      let v = ? parser.run(punctuationSpec(sep))
      discard ? parser.run(ws0)
      ok(v)
  newSpec[Token](sep, consumer)

let commaWithSpacesSpec* = separatorSpec(",")
let colonWithSpacesSpec* = separatorSpec(":")
let equalsSeparatorSpec* = separatorSpec("=")



# ============================================================
# Space + indentation
# ============================================================

type Space* = ref object
  spaces: uint32
  loc: Location

proc newSpace(spaces: uint32, loc: Location): Space =
  Space(spaces: spaces, loc: loc)

proc indentationConsumer(parser: Parser): Result[Space, ParserError] =
  let loc = parser.loc
  let spaces = ? parser.run(any(spaceSpec))

  var count: uint32 = 0
  for space in spaces: count += space.value.len.uint32
  let expected = parser.indentWidth * parser.level
  if count != expected:
    let msg = fmt"indentation error expected {expected} but found {count} space(s)"
    err(newParserError(msg, loc))
  else:
    ok(newSpace(count, loc))

let indentationSpec = newSpec[Space]("indentation", indentationConsumer)

let identifierHeadCharSpec = oneOf("identifier_head", [
  underscoreSpec,
  alphabetSpec,
])

let identifierTailCharSpec = oneOf("identifier_tail", [
  identifierHeadCharSpec,
  digitSpec,
])

proc identifierConsumer(parser: Parser): Result[Identifier, ParserError] =
  let head = ? parser.run(identifierHeadCharSpec)
  let tails = ? parser.run(any(identifierTailCharSpec))
  var content = head.value
  for tail in tails: content.add(tail.value)
  newIdentifier(content, head.loc)

let identifierSpec = newSpec[Identifier]("identifier", identifierConsumer)

proc parseKeyword(parser: Parser, keyword: string): Result[Location, ParserError] =
  let ident = ? parser.run(identifierSpec)
  if ident.value != keyword:
    let msg = fmt"expected keyword '{keyword}' but found '{ident.value}'"
    return err(newParserError(msg, ident.loc))
  ok(ident.loc)

# Curried adapter for callers still using `parser.run(keywordSpec("foo"))`.
proc keywordSpec(keyword: string): Spec[Location] =
  let consumer = proc(parser: Parser): Result[Location, ParserError] = parser.parseKeyword(keyword)
  newSpec[Location]("'" & keyword & "'", consumer)

# Spec adapter — `identifierSpec` is still consumed by
# `parseStructRequires`'s `separatedBy(identifierSpec, ...)` combinator
# chain (and by other `separatedBy(identifierSpec, ...)` sites).

proc decoratorConsumer(parser: Parser): Result[Decorator, ParserError] =
  discard ? parser.run(indentationSpec)
  discard ? parser.run(punctuationSpec("@"))
  let ident = ? parser.run(identifierSpec)
  discard ? parser.run(emptyLineSpec)
  ok(newDecorator(ident))

let decoratorSpec = newSpec[Decorator]("decorator", decoratorConsumer)

proc makeEscapedParser(name: string, character: string, charSpec: Spec[Token]): Spec[StringContent] =
  ## Returns a `Spec` for a single `\X` escape sequence.
  let consumer = proc(parser: Parser): Result[StringContent, ParserError] =
    let backslash = ? parser.run(backslashSpec)
    let token = ? parser.run(charSpec)
    if token.value != character:
      return err(newParserError(fmt"expected '\\{character}' but found '\\{token.value}'", token.loc))
    ok(newStringContent("\\" & character, backslash.loc))

  newSpec[StringContent](name, consumer)

let escapedStringContentSpec =
  oneOf("escaped string content", @[
    makeEscapedParser("string backslash character", "\\", backslashSpec),
    makeEscapedParser("string double quote character", "\"", doubleQuoteSpec),
    makeEscapedParser("string new line character", "n", alphabetSpec),
    makeEscapedParser("string tab character", "t", alphabetSpec)
  ])


proc unescapedStringContentConsumer(parser: Parser): Result[StringContent, ParserError] =
  let token = ? parser.run(anyTokenExceptNewlineSpec("unescaped string character"))
  if token.value == "\"" or token.value == "\\":
    return err(newParserError(
      fmt"expected a valid string character but found '{token.value}'", token.loc))
  ok(newStringContent(token.value, token.loc))

let unescapedStringContentSpec = newSpec[StringContent]("unescaped string content", unescapedStringContentConsumer)

let stringContentSpec =
  oneOf("string content", @[
    escapedStringContentSpec,
    unescapedStringContentSpec,
  ])

proc stringLiteralConsumer(parser: Parser): Result[StringLiteral, ParserError] =
  let openQuote = ? parser.run(doubleQuoteSpec)
  var content: string
  while true:
    let maybeChar = parser.run(stringContentSpec)
    if maybeChar.isErr:
      if maybeChar.error.fatal: return err(maybeChar.error)
      break
    content.add(maybeChar.get.content)
  discard ? parser.run(doubleQuoteSpec)
  ok(newStringLiteral(content, openQuote.loc))

# Spec adapter for stringLiteralSpec — still consumed by remaining
# combinator chains (import specs, literalDefSpec, etc.).
let stringLiteralSpec* = newSpec[StringLiteral]("string_literal", stringLiteralConsumer)

# (+ | -) digit+
let signSpec = oneOf("sign", [punctuationSpec("+"), punctuationSpec("-")])

# digit+
proc unsignedIntegerLiteralConsumer(parser: Parser): Result[UnsignedIntegerLiteral, ParserError] =
  let loc = parser.loc
  let digits = ? parser.run(atLeastOne(digitSpec))
  var value: string
  for d in digits: value.add(d.value)
  ok(newUnsignedIntegerLiteral(value, loc))

let unsignedIntegerLiteralSpec = newSpec[UnsignedIntegerLiteral]("unsigned integer literal", unsignedIntegerLiteralConsumer)


proc signedIntegerLiteralConsumer(parser: Parser): Result[SignedIntegerLiteral, ParserError] =
  let sign = ? parser.run(signSpec)
  let magnitude = ? parser.run(unsignedIntegerLiteralSpec)
  ok(newSignedIntegerLiteral(sign.value, magnitude, sign.loc))

let signedIntegerLiteralSpec = newSpec[SignedIntegerLiteral]("signed integer literal", signedIntegerLiteralConsumer)

proc integerLiteralConsumer(parser: Parser): Result[IntegerLiteral, ParserError] =
  var errors: seq[ParserError]
  let maybeSigned = parser.run(signedIntegerLiteralSpec)
  if maybeSigned.isOk: return ok(newIntegerLiteral(maybeSigned.get))
  errors.add(maybeSigned.error)
  let maybeUnsigned = parser.run(unsignedIntegerLiteralSpec)
  if maybeUnsigned.isOk: return ok(newIntegerLiteral(maybeUnsigned.get))
  errors.add(maybeUnsigned.error)
  err(max(errors))

let integerLiteralSpec = newSpec[IntegerLiteral]("integer literal", integerLiteralConsumer)

# Float-literal is a three-way alternation (`oneOf`) over per-form
# consumers, each with a single responsibility:
#   `nanFloatConsumer`     — matches the bare token `nan` (no sign allowed).
#   `infFloatConsumer`     — matches `inf` with an optional `+` / `-` prefix.
#   `numericFloatConsumer` — matches the digit-starting numeric form.
# Special-value forms are listed first because they start with identifier
# tokens; the numeric form couldn't reach them anyway (it requires a
# leading digit or sign+digit).

# `nan` — IEEE-754 quiet NaN. Unsigned only: `+nan` / `-nan` are
# rejected at parse time (the NaN sign bit exists in the hardware
# representation but is rarely meaningful in source code).
proc nanFloatConsumer(parser: Parser): Result[FloatLiteral, ParserError] =
  let ident = ? parser.run(identifierSpec)
  if ident.value != "nan":
    return err(newParserError(fmt"expected 'nan' but found `{ident.value}`", ident.loc))
  ok(newFloatLiteral("nan", ident.loc))

let nanFloatSpec = newSpec[FloatLiteral]("nan float", nanFloatConsumer)

# `inf` — IEEE-754 infinity. Optional `+` / `-` sign prefix; the sign
# folds into the stored literal value so downstream `analyzeFloatLiteral`
# can distinguish `+inf` from `-inf`.
proc infFloatConsumer(parser: Parser): Result[FloatLiteral, ParserError] =
  let loc = parser.loc
  let maybeSign = parser.run(signSpec)
  let signStr = if maybeSign.isOk: maybeSign.get.value else: ""
  let ident = ? parser.run(identifierSpec)
  if ident.value != "inf":
    return err(newParserError(fmt"expected 'inf' but found `{ident.value}`", ident.loc))
  ok(newFloatLiteral(signStr & "inf", loc))

let infFloatSpec = newSpec[FloatLiteral]("inf float", infFloatConsumer)

# (+|-)? digit+ ("." digit+)? ((e|E) (+|-)? digit+)?
# Must have either decimal part or exponent to distinguish from integer
proc numericFloatConsumer(parser: Parser): Result[FloatLiteral, ParserError] =
  let loc = parser.loc
  var value: string
  # Optional sign
  let maybeSign = parser.run(signSpec)
  if maybeSign.isOk: value.add(maybeSign.get.value)
  # Integer part (required)
  let intDigits = ? parser.run(atLeastOne(digitSpec))
  for d in intDigits: value.add(d.value)
  # Decimal part (optional)
  var hasDecimal = false
  let maybeDot = parser.run(punctuationSpec("."))
  if maybeDot.isOk:
    hasDecimal = true
    value.add(".")
    let fracDigits = ? parser.run(atLeastOne(digitSpec))
    for d in fracDigits: value.add(d.value)
  # Exponent part (optional)
  var hasExponent = false
  let maybeE = parser.run(oneOf("exponent", [
    alphabetSpec, alphabetSpec,
  ]))
  if maybeE.isOk and (maybeE.get.value == "e" or maybeE.get.value == "E"):
    hasExponent = true
    value.add(maybeE.get.value)
    let maybeExpSign = parser.run(signSpec)
    if maybeExpSign.isOk: value.add(maybeExpSign.get.value)
    let expDigits = ? parser.run(atLeastOne(digitSpec))
    for d in expDigits: value.add(d.value)
  # Must have at least decimal or exponent to be a float
  if not hasDecimal and not hasExponent:
    return err(newParserError("expected '.' or 'e' for float literal", loc))
  ok(newFloatLiteral(value, loc))

let numericFloatSpec = newSpec[FloatLiteral]("numeric float", numericFloatConsumer)

let floatLiteralSpec =
  oneOf("float literal", @[
    nanFloatSpec,
    infFloatSpec,
    numericFloatSpec,
  ])

proc literalConsumer(parser: Parser): Result[Literal, ParserError] =
  var errors: seq[ParserError]
  let maybeString = parser.run(stringLiteralSpec)
  if maybeString.isOk: return ok(newLiteral(maybeString.get))
  errors.add(maybeString.error)
  let maybeFloat = parser.run(floatLiteralSpec)
  if maybeFloat.isOk: return ok(newLiteral(maybeFloat.get))
  errors.add(maybeFloat.error)
  let maybeInt = parser.run(integerLiteralSpec)
  if maybeInt.isOk: return ok(newLiteral(maybeInt.get))
  errors.add(maybeInt.error)
  err(max(errors))

let literalSpec = newSpec[Literal]("literal spec", literalConsumer)

proc literalTypeConsumer(parser: Parser): Result[LiteralDef, ParserError] =
  discard ? parser.run(indentationSpec)
  let loc = ? parser.run(keywordSpec("literal"))
  discard ? parser.run(colonWithSpacesSpec)
  let strLit = ? parser.run(stringLiteralSpec)
  ok(newLiteralDef(strLit, loc))

let literalDefSpec = newSpec[LiteralDef]("literal def", literalTypeConsumer)

# Argument-type sugar: a trailing `!` on an argument type expands to
# `Status[<argType>]`. Parsed uniformly here so every argument-type
# position picks it up — function args, return types, kwarg field
# types, and the initializer type prefix all route through this parser.
#
# Nesting binds tight: `!` attaches to the type it immediately follows.
#   T!            -> Status[T]
#   Array[u32]!   -> Status[Array[u32]]
#   Array[u32!]   -> Array[Status[u32]]
#   Status[u32]!  -> Status[Status[u32]]     (syntactically legal)
#
# The sugar collapses at parse time. Downstream (resolver, analyzer)
# sees a plain `Status[...]` ArgumentType — no distinct AST variant,
# no separate handling.
#
# When updating this sugar (different suffix, different wrapper type,
# arity checks, additional post-fix operators, etc.), touch:
#   - The `maybeBanged` block below.
#   - grammar.md — the ArgumentType production.
#   - validations.md — §4.8 (argument-type shorthand).
#   - tests/test_grammar.nim — the "argument type shorthand" suite.
#   - tests/test_analyzer.nim — end-to-end sugar tests.
#
# `argumentTypeConsumer` is self-referential: type params like
# `Map[String, List[Int]]` contain nested argument types. Nim's
# `proc` declarations handle recursion natively (a proc body can call
# the enclosing proc by name).

proc argumentTypeConsumer(parser: Parser): Result[ArgumentType, ParserError]
let argumentTypeSpec = newSpec[ArgumentType]("argument type", argumentTypeConsumer)

proc argumentTypeConsumer(parser: Parser): Result[ArgumentType, ParserError] =
  let rootIdent = ? parser.run(identifierSpec)
  # Optional `[T, U, ...]` type params — argumentTypeConsumer recurses
  # into itself for each element.
  let maybeImpls = ? parser.runOptional(contained("argument_impl_list", "[", separatedBy(argumentTypeSpec, commaWithSpacesSpec), "]"))
  let maybeBanged = ? parser.runOptional(bangSpec)

  let argType =
    if maybeImpls.isSome:
      newArgumentType(rootIdent, maybeImpls.get)
    else:
      newArgumentType(rootIdent)

  if maybeBanged.isSome:
    let statusIdent = ? newIdentifier("Status", maybeBanged.get.loc)
    ok(newArgumentType(statusIdent, @[argType]))
  else:
    ok(argType)

proc argumentDefConsumer(parser: Parser): Result[ArgumentDef, ParserError] =
  let name = ? parser.run(identifierSpec)
  discard ? parser.run(colonWithSpacesSpec)
  let argType = ? parser.run(argumentTypeSpec)
  ok(newArgumentDef(name, argType))

let argumentDefSpec* = newSpec[ArgumentDef]("argument_definition", argumentDefConsumer)

proc argumentDefListConsumer(parser: Parser): Result[ArgumentDefList, ParserError] =
  let loc = parser.loc
  let argDefs = ? parser.run(contained("argument_definition_list", "(",
    separatedBy(argumentDefSpec, commaWithSpacesSpec), ")"))
  newArgumentDefList(argDefs, loc)

let argumentDefListSpec = newSpec[ArgumentDefList]("argument definition list", argumentDefListConsumer)


# Variant pattern field: name [":" binding] — bare `name` is sugar for
# `name: name`, mirroring the initializer kwarg shorthand. When the
# binding suffix is absent the parser synthesizes a binding with the
# same identifier (and the same source location).
proc unionPatternFieldConsumer(parser: Parser): Result[UnionPatternField, ParserError] =
  let name = ? parser.run(identifierSpec)

  let maybeColon = parser.run(colonWithSpacesSpec)
  if maybeColon.isOk:
    let binding = ? parser.run(identifierSpec)
    ok(newUnionPatternField(name, binding, name.loc))
  else:
    ok(newUnionPatternField(name, name, name.loc))

# Spec adapter.
let unionPatternFieldSpec* = newSpec[UnionPatternField]("variant_pattern_field", unionPatternFieldConsumer)

# Variant pattern: VariantName { field: binding, field: binding }
proc unionPatternConsumer(parser: Parser): Result[UnionPattern, ParserError] =
  let name = ? parser.run(identifierSpec)
  discard ? parser.run(ws0)
  let fields = ? parser.run(contained("variant_fields", "{",
    separatedBy(unionPatternFieldSpec, commaWithSpacesSpec), "}"))
  newUnionPattern(name, fields)

let unionPatternSpec = newSpec[UnionPattern]("union pattern", unionPatternConsumer)

proc casePatternConsumer(parser: Parser): Result[CasePattern, ParserError] =
  var errors: seq[ParserError]
  let maybeInt = parser.run(integerLiteralSpec)
  if maybeInt.isOk: return ok(newCasePattern(maybeInt.get))
  errors.add(maybeInt.error)
  let maybeUnion = parser.run(unionPatternSpec)
  if maybeUnion.isOk: return ok(newCasePattern(maybeUnion.get))
  errors.add(maybeUnion.error)
  let maybeIdent = parser.run(identifierSpec)
  if maybeIdent.isOk: return ok(newCasePattern(maybeIdent.get))
  errors.add(maybeIdent.error)
  err(max(errors))

let casePatternSpec = newSpec[CasePattern]("case pattern", casePatternConsumer)

# import { Name, Name } from "path"
# identifier ("as" identifier)?
proc importedTypeConsumer(parser: Parser): Result[ImportedType, ParserError] =
  let name = ? parser.run(identifierSpec)
  let maybeAs = parser.run(ws1)
  if maybeAs.isOk:
    let maybeAsKeyword = parser.run(keywordSpec("as"))
    if maybeAsKeyword.isOk:
      discard ? parser.run(ws1)
      let alias = ? parser.run(identifierSpec)
      ok(newImportedType(name, alias))
    else:
      ok(newImportedType(name))
  else:
    ok(newImportedType(name))

# Spec adapter.
let importedTypeSpec* = newSpec[ImportedType]("import_name", importedTypeConsumer)

proc toImportPath*(source: string, loc: Location): Result[ImportPath, ParserError] =
  ## Converts a raw quoted-string source (the body of an `import "..."`
  ## clause) into a typed ImportPath. Sources starting with `@` are
  ## vendor references; the remainder is validated as an ASL
  ## identifier (head: letter or underscore; tail: letter, digit, or
  ## underscore). Anything else is treated as a relative path —
  ## extension and parent-escape checks happen later in
  ## toAbsPath.
  if not source.startsWith("@"):
    return ok(newRelativeImportPath(source))
  let name = source[1..^1]
  if name.len == 0:
    return err(newParserError("vendor import path '@' is missing a vendor name", loc))
  if not (name[0].isAlphaAscii or name[0] == '_'):
    return err(newParserError(fmt"vendor name '{name}' must start with a letter or underscore", loc))
  for c in name[1..^1]:
    if not (c.isAlphaNumeric or c == '_'):
      return err(newParserError(fmt"vendor name '{name}' contains invalid character '{c}' (allowed: letters, digits, underscore)", loc))
  ok(newVendorImportPath(name))

proc toAbsPath*(parsedPath: ImportPath, importingFile: string,
    vendorRoots: VendorRoots): Result[string, string] =
  ## Resolves an import path to an absolute file path.
  ##
  ## - `ipkRelative`: resolves the relative source against the
  ##   importing file's directory. Rejects paths that escape to a
  ##   parent directory (normalized so tricks like
  ##   `./sub/../../escape` are caught). The `.asl` / `.aslr`
  ##   suffix is *optional* on the source: if the source ends in
  ##   `.asl` or `.aslr` the resolved path is used as-is; otherwise
  ##   the compiler tries the resolved path as typed, then falls
  ##   back to `<source>.asl` and finally `<source>.aslr`. `.asl`
  ##   is tried before `.aslr` because user code overwhelmingly
  ##   imports other user code; the runtime-interface case is a
  ##   belt-and-braces last attempt (most runtime imports flow
  ##   through `@<vendor>` paths anyway). Only if none of the
  ##   candidates exist is an error raised.
  ## - `ipkVendor`: looks up the vendor name in `vendorRoots` (the
  ##   table populated from `--vendor="<name>:<path>"` CLI flags
  ##   plus the default `std`). The registered target path is
  ##   already absolute. Missing vendor → diagnostic listing the
  ##   known ones.
  case parsedPath.kind:
  of ipkRelative:
    let source = parsedPath.relativeSource
    let (_, _, ext) = source.splitFile()
    let dir = normalizedPath(importingFile.parentDir)
    let baseResolved = normalizedPath((dir / source).absolutePath)
    let dirPrefix = if dir.endsWith($DirSep): dir else: dir & $DirSep
    if not baseResolved.startsWith(dirPrefix):
      return err(fmt"{importingFile}: import path '{source}' escapes to parent directory — imports must be from adjacent files or subdirectories")
    if ext == ".asl" or ext == ".aslr":
      # Explicit extension — defer file-existence to the loader
      # (matching prior behaviour for typed paths).
      return ok(baseResolved)
    # Extensionless (or unrecognized-extension) source: try the bare
    # path first, then `<source>.asl`, then `<source>.aslr`. Loader
    # emits the natural "file not found" if none exist.
    if fileExists(baseResolved):
      return ok(baseResolved)
    let withAsl = baseResolved & ".asl"
    if fileExists(withAsl):
      return ok(withAsl)
    let withAslr = baseResolved & ".aslr"
    if fileExists(withAslr):
      return ok(withAslr)
    err(fmt"{importingFile}: import path '{source}' not found (also tried '{source}.asl' and '{source}.aslr')")
  of ipkVendor:
    let name = parsedPath.vendorName
    if name in vendorRoots:
      return ok(vendorRoots[name])
    var knownNames: seq[string]
    for vendorName in vendorRoots.keys:
      knownNames.add(vendorName)
    let knownDesc = if knownNames.len == 0: "(no vendors registered)" else: knownNames.join(", ")
    err(fmt"{importingFile}: unknown vendor '@{name}' — known vendors: {knownDesc}")

# Explicit form: `import { Name, Name as Alias } from "path"`.
proc explicitImportLineConsumer(parser: Parser): Result[Import, ParserError] =
  let loc = ? parser.run(keywordSpec("import"))
  discard ? parser.run(atLeastOne(spaceSpec))
  let names = ? parser.run(contained("import_names", "{",
    separatedBy(importedTypeSpec, commaWithSpacesSpec), "}"))
  discard ? parser.run(atLeastOne(spaceSpec))
  discard ? parser.run(keywordSpec("from"))
  discard ? parser.run(atLeastOne(spaceSpec))
  let source = ? parser.run(stringLiteralSpec)
  discard ? parser.run(emptyLineSpec)
  let parsedPath = ? toImportPath(source.value, source.loc)
  let maybePath = toAbsPath(parsedPath, parser.filepath, initTable[string, string]())
  if maybePath.isOk:
    newImport(names, parsedPath, maybePath.get, loc)
  else:
    err(newParserError(maybePath.error, source.loc))

let explicitImportLineSpec = newSpec[Import]("explicit import", explicitImportLineConsumer)

# Shorthand form: `import "path"` — brings every public defined
# type from the target file into scope under each type's original
# name. The names list is materialized by the resolver once the
# target file's types are resolved.
proc shorthandImportLineConsumer(parser: Parser): Result[Import, ParserError] =
  let loc = ? parser.run(keywordSpec("import"))
  discard ? parser.run(atLeastOne(spaceSpec))
  let source = ? parser.run(stringLiteralSpec)
  discard ? parser.run(emptyLineSpec)
  let parsedPath = ? toImportPath(source.value, source.loc)
  let maybePath = toAbsPath(parsedPath, parser.filepath, initTable[string, string]())
  if maybePath.isOk:
    newImport(parsedPath, maybePath.get, loc)
  else:
    err(newParserError(maybePath.error, source.loc))

let shorthandImportLineSpec = newSpec[Import]("implicit import", shorthandImportLineConsumer)

let importLineSpec =
  oneOf("import line", @[
    explicitImportLineSpec,
    shorthandImportLineSpec,
  ])

proc importConsumer(parser: Parser): Result[Import, ParserError] =
  ## Skips leading blank / comment lines, then parses one import line
  ## (either explicit `import { A, B } from "path"` or shorthand
  ## `import "path"`).
  discard ? parser.run(any(emptyLineSpec))
  parser.run(importLineSpec)

let importSpec = newSpec[Import]("import", importConsumer)

proc getterConsumer(parser: Parser): Result[Getter, ParserError] =
  let target = ? parser.run(identifierSpec)
  discard ? parser.run(punctuationSpec("."))
  let field = ? parser.run(identifierSpec)
  ok(newGetter(target, field, target.loc))

let getterSpec = newSpec[Getter]("getter", getterConsumer)

# type literal
proc literalInitializerConsumer(parser: Parser): Result[LiteralInitializer, ParserError] =
  let argType = ? parser.run(argumentTypeSpec)
  discard ? parser.run(ws1)
  let lit = ? parser.run(literalSpec)
  ok(newLiteralInitializer(argType, lit))

let literalInitSpec = newSpec[LiteralInitializer]("literal initializer", literalInitializerConsumer)

# ============================================================
# Body cluster — mutually recursive
# ============================================================
#
# Expression → FunctionCall → ArgumentList → Expression, and
# Match → CaseBlock → StatementList → StatementLine → Statement → Match.
# Nim's forward declarations resolve the cycle; each proc below is
# implemented later in this section.
proc expressionConsumer(parser: Parser): Result[Expression, ParserError]
proc statementListConsumer(parser: Parser): Result[StatementList, ParserError]
proc argumentListConsumer(parser: Parser): Result[ArgumentList, ParserError]
proc functionCallConsumer(parser: Parser): Result[FunctionCall, ParserError]
proc kwargConsumer(parser: Parser): Result[KeywordArgument, ParserError]
proc kwargListConsumer(parser: Parser): Result[KeywordArgumentList, ParserError]
proc unionInitializerConsumer(parser: Parser): Result[UnionInitializer, ParserError]
proc structInitializerConsumer(parser: Parser): Result[StructInitializer, ParserError]
proc initializerConsumer(parser: Parser): Result[Initializer, ParserError]
proc assignmentConsumer(parser: Parser): Result[Assignment, ParserError]
proc setterConsumer(parser: Parser): Result[Setter, ParserError]
proc inlineStatementConsumer(parser: Parser): Result[Statement, ParserError]
proc caseConsumer(parser: Parser): Result[CaseBlock, ParserError]
proc matchConsumer(parser: Parser): Result[MatchExpression, ParserError]
proc statementLineConsumer(parser: Parser): Result[Statement, ParserError]

# Spec adapter — `expressionSpec` is still consumed by `argumentListConsumer`'s
# `separatedBy(expressionSpec, ...)` combinator chain.
let expressionSpec* = newSpec[Expression]("expression", expressionConsumer)

proc argumentListConsumer(parser: Parser): Result[ArgumentList, ParserError] =
  let loc = parser.loc
  let args = ? parser.run(contained("argument_list", "(",
    separatedBy(expressionSpec, commaWithSpacesSpec), ")"))
  ok(newArgumentList(args, loc))

let argumentListSpec = newSpec[ArgumentList]("argument list", argumentListConsumer)

proc functionCallConsumer(parser: Parser): Result[FunctionCall, ParserError] =
  let target = ? parser.run(identifierSpec)
  discard ? parser.run(punctuationSpec("."))
  let method0 = ? parser.run(identifierSpec)
  discard ? parser.run(ws0)
  let args = ? parser.run(argumentListSpec)
  ok(newFunctionCall(target, method0, args))

let fncallSpec = newSpec[FunctionCall]("function call", functionCallConsumer)


proc kwargConsumer(parser: Parser): Result[KeywordArgument, ParserError] =
  let name = ? parser.run(identifierSpec)
  let maybeColon = parser.run(colonWithSpacesSpec)
  if maybeColon.isOk:
    let expression = ? parser.run(expressionSpec)
    ok(newKeywordArgument(name, expression, name.loc))
  else:
    ok(newKeywordArgument(name, newExpression(name), name.loc))

# Spec adapter (kwargListSpec uses this via `separatedBy(kwargSpec, ...)`).
let kwargSpec* = newSpec[KeywordArgument]("keyword_argument", kwargConsumer)

proc kwargListConsumer(parser: Parser): Result[KeywordArgumentList, ParserError] =
  let loc = parser.loc
  let args = ? parser.run(contained("keyword_argument_list", "{",
    separatedBy(kwargSpec, commaWithSpacesSpec), "}"))
  newKeywordArgumentList(args, loc)

let kwargListSpec = newSpec[KeywordArgumentList]("keyword argument list", kwargListConsumer)

proc parseUnionRef(parser: Parser): Result[UnionRef, ParserError] =
  let typeRef = ? parser.run(argumentTypeSpec)
  discard ? parser.run(punctuationSpec("."))
  let variant = ? parser.run(identifierSpec)
  ok(newUnionRef(typeRef, variant))

let unionRefSpec = newSpec[UnionRef]("union ref", parseUnionRef)

# LocalType.Variant { fields } (bare — drives leave-as-is inference) or
# LocalType[Impls].Variant { fields } (explicit-impls — escape hatch when
# leave-as-is can't produce a fully-bound type). Both productions land
# on the same UnionRef shape carrying an impls seq; empty means bare.
proc unionInitializerConsumer(parser: Parser): Result[UnionInitializer, ParserError] =
  let unionRef = ? parser.run(unionRefSpec)
  discard ? parser.run(ws0)
  let fields = ? parser.run(kwargListSpec)
  ok(newUnionInitializer(unionRef, fields))

let unionInitSpec = newSpec[UnionInitializer]("union initializer", unionInitializerConsumer)

# Either `LocalType { fields }` (bare) or `LocalType[Impls] { fields }` (explicit
# impls, used for phantom-typed structs whose module declares a
# `struct(A):` header). Both productions land on the same StructRef
# shape carrying an impls seq; empty means bare.
proc parseStructRef(parser: Parser): Result[StructRef, ParserError] =
  let argType = ? parser.run(argumentTypeSpec)
  ok(newStructRef(argType))

let structRefSpec = newSpec[StructRef]("struct ref", parseStructRef)

proc structInitializerConsumer(parser: Parser): Result[StructInitializer, ParserError] =
  let structRef = ? parser.run(structRefSpec)
  discard ? parser.run(ws0)
  let fields = ? parser.run(kwargListSpec)
  ok(newStructInitializer(structRef, fields))

let structInitSpec = newSpec[StructInitializer]("struct initializer", structInitializerConsumer)

proc initializerConsumer(parser: Parser): Result[Initializer, ParserError] =
  var errors: seq[ParserError]
  let maybeUnion = parser.run(unionInitSpec)
  if maybeUnion.isOk: return ok(newInitializer(maybeUnion.get))
  errors.add(maybeUnion.error)
  let maybeStruct = parser.run(structInitSpec)
  if maybeStruct.isOk: return ok(newInitializer(maybeStruct.get))
  errors.add(maybeStruct.error)
  let maybeLit = parser.run(literalInitSpec)
  if maybeLit.isOk: return ok(newInitializer(maybeLit.get))
  errors.add(maybeLit.error)
  err(max(errors))

let initSpec = newSpec[Initializer]("initializer spec", initializerConsumer)

proc expressionConsumer(parser: Parser): Result[Expression, ParserError] =
  var errors: seq[ParserError]
  let maybeLit = parser.run(literalSpec)
  if maybeLit.isOk: return ok(newExpression(maybeLit.get))
  errors.add(maybeLit.error)
  let maybeInit = parser.run(initSpec)
  if maybeInit.isOk: return ok(newExpression(maybeInit.get))
  errors.add(maybeInit.error)
  let maybeCall = parser.run(fncallSpec)
  if maybeCall.isOk: return ok(newExpression(maybeCall.get))
  errors.add(maybeCall.error)
  let maybeGetter = parser.run(getterSpec)
  if maybeGetter.isOk: return ok(newExpression(maybeGetter.get))
  errors.add(maybeGetter.error)
  let maybeIdent = parser.run(identifierSpec)
  if maybeIdent.isOk: return ok(newExpression(maybeIdent.get))
  errors.add(maybeIdent.error)
  err(max(errors))

proc assignmentConsumer(parser: Parser): Result[Assignment, ParserError] =
  let target = ? parser.run(identifierSpec)
  discard ? parser.run(equalsSeparatorSpec)
  let expr = ? parser.run(expressionSpec)
  ok(newAssignment(target, expr, target.loc))

let assignmentSpec = newSpec[Assignment]("assignment", assignmentConsumer)

proc setterConsumer(parser: Parser): Result[Setter, ParserError] =
  let target = ? parser.run(getterSpec)
  discard ? parser.run(equalsSeparatorSpec)
  let expr = ? parser.run(expressionSpec)
  ok(newSetter(target, expr, target.loc))

let setterSpec = newSpec[Setter]("setter", setterConsumer)

proc inlineStatementConsumer(parser: Parser): Result[Statement, ParserError] =
  var errors: seq[ParserError]
  let maybeSet = parser.run(setterSpec)
  if maybeSet.isOk: return ok(newStatement(maybeSet.get))
  errors.add(maybeSet.error)
  let maybeAssign = parser.run(assignmentSpec)
  if maybeAssign.isOk: return ok(newStatement(maybeAssign.get))
  errors.add(maybeAssign.error)
  let maybeExpr = parser.run(expressionSpec)
  if maybeExpr.isOk: return ok(newStatement(maybeExpr.get))
  errors.add(maybeExpr.error)
  err(max(errors))

let statementSpec = newSpec[Statement]("statement", inlineStatementConsumer)

proc parseCaseLine(parser: Parser): Result[CasePattern, ParserError] =
  discard ? parser.run(keywordSpec("case"))
  discard ? parser.run(ws1)
  let pat = ? parser.run(casePatternSpec)
  discard ? parser.run(ws0)
  discard ? parser.run(punctuationSpec(":"))
  ok(pat)

let caseLineSpec = newSpec[CasePattern]("case line", parseCaseLine)

proc caseConsumer(parser: Parser): Result[CaseBlock, ParserError] =
  discard ? parser.run(indentationSpec)
  let pat = ? parser.run(caseLineSpec)
  discard ? parser.run(emptyLineSpec)
  parser.level += 1
  let bodyResult = statementListConsumer(parser)
  parser.level -= 1
  if bodyResult.isErr:
    bodyResult.error.fatal = true
    return err(bodyResult.error)
  ok(newCaseBlock(pat, bodyResult.get, pat.loc))

let caseBlockSpec = newSpec[CaseBlock]("case block", caseConsumer)

# Match body: parses "match" keyword + subject + ":" + newline + caseBlocks
# Does NOT consume indentation — caller handles that
proc matchConsumer(parser: Parser): Result[MatchExpression, ParserError] =
  let loc = ? parser.run(keywordSpec("match"))
  discard ? parser.run(ws1)
  # Match expressions cannot be the subject of another match expression.
  # expressionConsumer intentionally excludes match (match is parsed separately
  # in statementLineConsumer). This check guards against future changes that
  # might add match to expressionConsumer.
  let subject = ? parser.run(expressionSpec)
  case subject.kind:
  of ekMatch:
    return err(newParserError(
      "match expression cannot be the subject of another match", loc))
  of ekLiteral, ekFnCall, ekGetter, ekInitializer, ekVariable: discard
  discard parser.run(ws0)
  discard ? parser.run(punctuationSpec(":"))
  discard ? parser.run(emptyLineSpec)
  parser.level += 1
  var cases: seq[CaseBlock]
  let firstCaseResult = block:
    discard parser.run(any(emptyLineSpec))
    parser.run(caseBlockSpec)
  if firstCaseResult.isErr:
    parser.level -= 1
    firstCaseResult.error.fatal = true
    return err(firstCaseResult.error)
  cases.add(firstCaseResult.get)
  while true:
    discard parser.run(any(emptyLineSpec))
    let nextCase = parser.run(caseBlockSpec)
    if nextCase.isErr:
      if nextCase.error.fatal:
        parser.level -= 1
        return err(nextCase.error)
      break
    cases.add(nextCase.get)
  parser.level -= 1
  ok(newMatchExpression(subject, cases, loc))

let matchSpec = newSpec[MatchExpression]("match", matchConsumer)

# identifier = match ...: — parsed atomically so a non-match assignment
# (`x = expr`) or a bare expression statement backtracks cleanly instead
# of committing to the match path on the leading identifier.
proc parseMatchAssignment(parser: Parser): Result[Statement, ParserError] =
  let target = ? parser.run(identifierSpec)
  discard ? parser.run(equalsSeparatorSpec)
  let matchExpr = ? parser.run(matchSpec)
  ok(newStatement(newAssignment(target, newExpression(matchExpr), target.loc)))

let matchAssignmentSpec = newSpec[Statement]("match assignment", parseMatchAssignment)

proc statementLineConsumer(parser: Parser): Result[Statement, ParserError] =
  discard parser.run(any(emptyLineSpec))
  discard ? parser.run(indentationSpec)
  # Try match assignment: identifier = match ...:
  let maybeMatchAssign = parser.run(matchAssignmentSpec)
  if maybeMatchAssign.isOk: return ok(maybeMatchAssign.get)
  # Try standalone match: match ...:
  let maybeMatch = parser.run(matchSpec)
  if maybeMatch.isOk:
    return ok(newStatement(newExpression(maybeMatch.get)))
  # Inline statements: statement + newline
  let statement = ? parser.run(statementSpec)
  discard ? parser.run(emptyLineSpec)
  ok(statement)

let statementLineSpec = newSpec[Statement]("statement line", statementLineConsumer)

proc statementListConsumer(parser: Parser): Result[StatementList, ParserError] =
  var stmts: seq[Statement]
  let first = ? parser.run(statementLineSpec)
  stmts.add(first)
  while true:
    let maybeNext = parser.run(statementLineSpec)
    if maybeNext.isErr:
      if maybeNext.error.fatal: return err(maybeNext.error)
      break
    stmts.add(maybeNext.get)
  ok(newStatementList(stmts))

# TODO(post-analysis-expander): re-wire expansion after the analyzer once the
# post-analysis expander lands (see plans/plan_post_analysis_expansion.md).
# The expand* procs above (lines 540-748) are kept as reference for that move.


proc parseFunctionDef(parser: Parser): Result[FunctionDef, ParserError] =
  let public = ? parser.run(presence(keywordSpec("public")))
  if public: discard ? parser.run(ws1)

  let funcLoc = ? parser.run(keywordSpec("func"))
  discard ? parser.run(ws1)
  let funcName = ? parser.run(identifierSpec)
  discard parser.run(ws0)
  let argDefList = ? parser.run(argumentDefListSpec)
  discard ? parser.run(colonWithSpacesSpec)
  let returnType = ? parser.run(argumentTypeSpec)
  ok(newFunctionDef(public, funcName, argDefList, returnType, funcLoc))

let functionDefSpec = newSpec[FunctionDef]("function def", parseFunctionDef)

proc parseFunctionDefLine(parser: Parser): Result[FunctionDef, ParserError] =
  ## Indented single-line variant used by `parseFunctionDefs`.
  discard ? parser.run(indentationSpec)
  let def = ? parser.run(functionDefSpec)
  discard ? parser.run(emptyLineSpec)
  ok(def)

let funcDefLineSpec = newSpec[FunctionDef]("function def line", parseFunctionDefLine)

proc parseFunctionDefs(parser: Parser): Result[seq[FunctionDef], ParserError] =
  ## Parses one-or-more function-definition lines. Used inside a
  ## `generic` block, which only carries signatures — no bodies.
  var defs: seq[FunctionDef]
  let first = ? parser.run(funcDefLineSpec)
  defs.add(first)
  while true:
    let maybeNext = parser.run(funcDefLineSpec)
    if maybeNext.isErr:
      if maybeNext.error.fatal: return err(maybeNext.error)
      break
    defs.add(maybeNext.get)
  ok(defs)

proc parseUserFunction(parser: Parser): Result[UserFunction, ParserError] =
  ## Parses a user function block: optional decorator lines, then the
  ## function signature, then an indented statement-list body. Body
  ## failures are marked fatal — once past the header, the block can't
  ## be backtracked out of.
  let decorators = ? parser.run(any(decoratorSpec))
  discard ? parser.run(indentationSpec)
  let h = ? parser.run(functionDefSpec)
  discard ? parser.run(emptyLineSpec)
  parser.level += 1
  let bodyResult = statementListConsumer(parser)
  parser.level -= 1
  if bodyResult.isErr:
    bodyResult.error.fatal = true
    return err(bodyResult.error)
  ok(newUserFunction(decorators, h, bodyResult.get))

let userFuncSpec = newSpec[UserFunction]("user function", parseUserFunction)

# @extern("symbol")
# public func name(args): ReturnType
proc parseExternFunction(parser: Parser): Result[ExternFunction, ParserError] =
  discard ? parser.run(indentationSpec)
  discard ? parser.run(punctuationSpec("@"))
  discard ? parser.run(keywordSpec("extern"))
  discard parser.run(ws0)
  let loc = parser.loc
  let symbol = ? parser.run(contained("extern_symbol", "(", stringLiteralSpec, ")"))
  discard ? parser.run(emptyLineSpec)
  discard ? parser.run(indentationSpec)
  let def = ? parser.run(functionDefSpec)
  discard ? parser.run(emptyLineSpec)
  ok(newExternFunction(symbol.value, def, loc))

let externFuncSpec = newSpec[ExternFunction]("extern function", parseExternFunction)

proc parseFunction(parser: Parser): Result[Function, ParserError] =
  ## Parses one function block — skips leading blank lines, then tries
  ## the extern form; falls back to user function on non-fatal failure.
  discard parser.run(any(emptyLineSpec))
  let f = parser.run(externFuncSpec)
  if f.isOk: return ok(newFunction(f.get))
  let u = ? parser.run(userFuncSpec)
  ok(newFunction(u))

let funcSpec = newSpec[Function]("function", parseFunction)

proc parseFunctionList(parser: Parser): Result[FunctionList, ParserError] =
  ## Parses zero-or-more function blocks (extern or user), then wraps
  ## them into a FunctionList (which enforces name+arity uniqueness).
  var funcs: seq[Function]
  while true:
    let maybeFn = parser.run(funcSpec)
    if maybeFn.isErr:
      if maybeFn.error.fatal: return err(maybeFn.error)
      break
    funcs.add(maybeFn.get)
  newFunctionList(funcs)

let functionListSpec = newSpec[FunctionList]("function list", parseFunctionList)

proc parseStructRequires(parser: Parser): Result[seq[Identifier], ParserError] =
  ## Parses the `(A, B, C)` clause of a `struct(A, B, C):` header —
  ## a parenthesised comma-separated identifier list naming the
  ## struct's required generic impls.
  let generics = ? parser.run(contained("struct_requires_generics", "(",
    separatedBy(identifierSpec, commaWithSpacesSpec), ")"))
  ok(generics)

let requiredStructGenerics = newSpec[seq[Identifier]]("required struct generics", parseStructRequires)

# struct: field+ (field is identifier ":" argumentType)
proc parseStructHeader(parser: Parser): Result[StructDefHeader, ParserError] =
  let loc = ? parser.run(keywordSpec("struct"))
  let maybeRequires = ? parser.runOptional(requiredStructGenerics)
  discard ? parser.run(ws0)
  discard ? parser.run(punctuationSpec(":"))
  let requires = if maybeRequires.isSome: maybeRequires.get else: @[]
  # newStructDefHeader validation errors (duplicate generic in header)
  # must be fatal — we're past `struct(...)` so an outer runOptional
  # shouldn't swallow the failure and treat the whole struct as absent.
  let headerResult = newStructDefHeader(requires, loc)
  if headerResult.isErr:
    headerResult.error.fatal = true
  headerResult

let structHeaderSpec = newSpec[StructDefHeader]("struct def header", parseStructHeader)

# Each field line: (blank lines) + indentation + argumentDef + newline
proc parseArgumentDefLine(parser: Parser): Result[ArgumentDef, ParserError] =
  discard ? parser.run(any(emptyLineSpec))
  discard ? parser.run(indentationSpec)
  let def = ? parser.run(argumentDefSpec)
  discard ? parser.run(emptyLineSpec)
  ok(def)

let argDefLineSpec = newSpec[ArgumentDef]("argument def", parseArgumentDefLine)

proc parseStructBody(parser: Parser): Result[seq[ArgumentDef], ParserError] =
  var fields: seq[ArgumentDef]
  let first = ? parser.run(argDefLineSpec)
  fields.add(first)
  while true:
    let maybeNext = parser.run(argDefLineSpec)
    if maybeNext.isErr:
      if maybeNext.error.fatal: return err(maybeNext.error)
      break
    fields.add(maybeNext.get)
  ok(fields)

proc parseStruct(parser: Parser): Result[StructDef, ParserError] =
  discard ? parser.run(indentationSpec)
  let header = ? parser.run(structHeaderSpec)
  discard ? parser.run(emptyLineSpec)
  parser.level += 1
  let bodyResult = parseStructBody(parser)
  parser.level -= 1
  if bodyResult.isErr:
    bodyResult.error.fatal = true
    return err(bodyResult.error)
  # newStructDef validation errors (duplicate generic in header,
  # duplicate field name) must also be fatal — we're past the header,
  # so an outer runOptional shouldn't swallow the failure and treat
  # the whole struct as absent.
  let structResult = newStructDef(header, bodyResult.get)
  if structResult.isErr:
    structResult.error.fatal = true
  structResult

let structDefSpec = newSpec[StructDef]("struct def", parseStruct)

# union: variant+ (variant is identifier space* "{" (argDef, argDef)* "}")
# Braces are required — empty variants must be written `Timeout { }`. This
# mirrors the case-pattern side (`case Timeout { }:`) so the two shapes
# stay visually consistent and there's no bare `Timeout` form to confuse
# with a variable-binding case pattern.
proc parseVariantDefLine(parser: Parser): Result[VariantDef, ParserError] =
  discard parser.run(any(emptyLineSpec))
  discard ? parser.run(indentationSpec)
  let name = ? parser.run(identifierSpec)
  discard parser.run(ws0)
  let fields = ? parser.run(contained("variant_fields", "{",
    separatedBy(argumentDefSpec, commaWithSpacesSpec), "}"))
  discard ? parser.run(emptyLineSpec)
  newVariantDef(name, fields, name.loc)

let variantDefLineSpec = newSpec[VariantDef]("variant def line", parseVariantDefLine)

proc parseUnionHeader(parser: Parser): Result[Location, ParserError] =
  let loc = ? parser.run(keywordSpec("union"))
  discard ? parser.run(ws0)
  discard ? parser.run(punctuationSpec(":"))
  ok(loc)

let unionHeaderSpec = newSpec[Location]("union header", parseUnionHeader)

proc parseUnionBody(parser: Parser): Result[seq[VariantDef], ParserError] =
  var variants: seq[VariantDef]
  let first = ? parser.run(variantDefLineSpec)
  variants.add(first)
  while true:
    let maybeNext = parser.run(variantDefLineSpec)
    if maybeNext.isErr:
      if maybeNext.error.fatal: return err(maybeNext.error)
      break
    variants.add(maybeNext.get)
  ok(variants)

proc parseUnion(parser: Parser): Result[UnionDef, ParserError] =
  discard ? parser.run(indentationSpec)
  let loc = ? parser.run(unionHeaderSpec)
  discard ? parser.run(emptyLineSpec)
  parser.level += 1
  let bodyResult = parseUnionBody(parser)
  parser.level -= 1
  if bodyResult.isErr:
    bodyResult.error.fatal = true
    return err(bodyResult.error)
  newUnionDef(bodyResult.get, loc)

let unionDefSpec = newSpec[UnionDef]("union def", parseUnion)

proc parseData(parser: Parser): Result[DataDef, ParserError] =
  ## Parses a module's data block: literal, struct, or union. Tries
  ## each in order; returns the error from whichever candidate
  ## reached farthest into the token stream. A fatal error from any
  ## branch short-circuits — once a branch has committed past the
  ## point of no-return, its error must propagate rather than being
  ## swallowed by trying the next branch.
  var errors: seq[ParserError]
  let maybeLiteral = parser.run(literalDefSpec)
  if maybeLiteral.isOk: return ok(newDataDef(maybeLiteral.get))
  if maybeLiteral.error.fatal: return err(maybeLiteral.error)
  errors.add(maybeLiteral.error)
  let maybeStruct = parser.run(structDefSpec)
  if maybeStruct.isOk: return ok(newDataDef(maybeStruct.get))
  if maybeStruct.error.fatal: return err(maybeStruct.error)
  errors.add(maybeStruct.error)
  let maybeUnion = parser.run(unionDefSpec)
  if maybeUnion.isOk: return ok(newDataDef(maybeUnion.get))
  if maybeUnion.error.fatal: return err(maybeUnion.error)
  errors.add(maybeUnion.error)
  err(max(errors))

let dataDefSpec = newSpec[DataDef]("data def", parseData)

proc parseGenericHeader(parser: Parser): Result[GenericHeader, ParserError] =
  let public = ? parser.run(presence(keywordSpec("public")))
  if public: discard ? parser.run(ws1)
  let loc = ? parser.run(keywordSpec("generic"))
  discard ? parser.run(ws1)
  let nameIdent = ? parser.run(identifierSpec)
  discard parser.run(ws0)
  discard ? parser.run(punctuationSpec(":"))
  ok(newGenericHeader(public, nameIdent, loc))

let genericHeaderSpec = newSpec[GenericHeader]("generic header", parseGenericHeader)

proc parseGeneric(parser: Parser): Result[Generic, ParserError] =
  ## Parses a `[public] generic Name:` block followed by its function
  ## definitions. Body failures are marked fatal — once past the
  ## header, the block cannot be backtracked out of.
  discard ? parser.run(indentationSpec)
  let h = ? parser.run(genericHeaderSpec)
  discard ? parser.run(emptyLineSpec)
  parser.level += 1
  let bodyResult = parseFunctionDefs(parser)
  parser.level -= 1
  if bodyResult.isErr:
    bodyResult.error.fatal = true
    return err(bodyResult.error)
  ok(newGeneric(@[], h.public, h.name, bodyResult.get, h.loc))

let genericSpec = newSpec[Generic]("generic", parseGeneric)

proc parseModuleHeader(parser: Parser): Result[ModuleHeader, ParserError] =
  let public = ? parser.run(presence(keywordSpec("public")))
  if public: discard ? parser.run(ws1)

  let loc = ? parser.run(keywordSpec("module"))
  discard ? parser.run(ws1)
  let nameIdent = ? parser.run(identifierSpec)
  discard parser.run(ws0)
  discard ? parser.run(punctuationSpec(":"))
  ok(newModuleHeader(public, nameIdent, loc))

let moduleHeaderSpec = newSpec[ModuleHeader]("module header", parseModuleHeader)

proc parseModuleBody(parser: Parser): Result[ModuleBody, ParserError] =
  discard parser.run(any(emptyLineSpec))
  let data = ? parser.runOptional(dataDefSpec)
  let funcList = ? parser.run(functionListSpec)
  ok(newModuleBody(data, funcList))

let moduleBodySpec = newSpec[ModuleBody]("module body", parseModuleBody)

proc parseModule(parser: Parser): Result[Module, ParserError] =
  ## Parses a `[public] module Name:` block with optional decorator
  ## lines. Body failures are marked fatal — once past the header,
  ## the block cannot be backtracked out of.
  let decorators = ? parser.run(any(decoratorSpec))
  discard ? parser.run(indentationSpec)
  let h = ? parser.run(moduleHeaderSpec)
  discard ? parser.run(emptyLineSpec)
  parser.level += 1
  let bodyResult = parseModuleBody(parser)
  parser.level -= 1
  if bodyResult.isErr:
    bodyResult.error.fatal = true
    return err(bodyResult.error)
  let b = bodyResult.get
  newModule(decorators, h.public, h.name, b.data, b.funcList, h.loc)

let moduleSpec = newSpec[Module]("module", parseModule)


proc parseType(parser: Parser): Result[LocalType, ParserError] =
  ## Parses either a module or a generic block and wraps it as `LocalType`.
  ## Tries module first; if that fails non-fatally, tries generic;
  ## returns whichever error carried further into the token stream.
  ## Fatal errors short-circuit — once a branch has committed past
  ## the point of no-return, its error must propagate rather than
  ## being swallowed by trying the next branch.
  var errors: seq[ParserError]
  let maybeModule = parser.run(moduleSpec)
  if maybeModule.isOk: return ok(newLocalType(maybeModule.get))
  if maybeModule.error.fatal: return err(maybeModule.error)
  errors.add(maybeModule.error)
  let maybeGeneric = parser.run(genericSpec)
  if maybeGeneric.isOk: return ok(newLocalType(maybeGeneric.get))
  if maybeGeneric.error.fatal: return err(maybeGeneric.error)
  errors.add(maybeGeneric.error)
  err(max(errors))

let typeSpec = newSpec[LocalType]("type", parseType)

proc parseDefinedType(parser: Parser): Result[LocalType, ParserError] =
  ## Skips leading blank / comment lines, then parses a module or
  ## generic block. Used at file level between top-level type blocks.
  discard ? parser.run(any(emptyLineSpec))
  parser.run(typeSpec)

let localTypeSpec = newSpec[LocalType]("local type", parseDefinedType)

proc parseDefinedTypes(parser: Parser): Result[seq[LocalType], ParserError] =
  ## Parses one-or-more top-level `LocalType` blocks (module / generic),
  ## skipping blank lines between them. Fails if the first attempt
  ## does not yield a type.
  var items: seq[LocalType]
  let first = ? parser.run(localTypeSpec)
  items.add(first)
  while true:
    let maybeNext = parser.run(localTypeSpec)
    if maybeNext.isErr:
      if maybeNext.error.fatal: return err(maybeNext.error)
      break
    items.add(maybeNext.get)
  ok(items)

let definedTypesSpec = newSpec[seq[LocalType]]("defined types", parseDefinedTypes)

# aslFile: import* (module | generic)*  — user-authored source files.
proc parseAslFile(parser: Parser, vendorRoots: VendorRoots): Result[File, ParserError] =
  let imports = ? parser.run(any(importSpec))
  let items = ? parser.run(definedTypesSpec)
  discard parser.run(any(emptyLineSpec))
  # Force a parse attempt to get a specific error message
  if not parser.done(): discard ? parser.run(typeSpec)
  newAslFile(parser.filepath, imports, items, vendorRoots)

# aslrFile: (module | generic)*  — no imports section. Aslr files
# are the runtime interface; they cannot reference other files.
proc parseAslrFile(parser: Parser): Result[File, ParserError] =
  let items = ? parser.run(definedTypesSpec)
  discard parser.run(any(emptyLineSpec))
  # Force a parse attempt to get a specific error message
  if not parser.done(): discard ? parser.run(typeSpec)
  newAslrFile(parser.filepath, items, @[])

proc toStringErr(r: Result[File, ParserError]): Result[File, string] =
  if r.isOk: ok(r.get) else: err(fmt"{r.error}")

proc parseFile*(parser: Parser, vendorRoots: VendorRoots): Result[File, string] =
  ## Runs the grammar against `parser` and returns the parsed `File`.
  ## Dispatches on the filepath extension: `.asl` files parse imports
  ## plus modules/generics; `.aslr` files parse modules/generics only
  ## (runtime interface — no imports allowed).
  let (_, _, ext) = parser.filepath.splitFile()
  case ext:
  of ".asl": parseAslFile(parser, vendorRoots).toStringErr
  of ".aslr": parseAslrFile(parser).toStringErr
  else: err(fmt"{parser.filepath}: unrecognized file extension '{ext}' — expected '.asl' or '.aslr'")

proc readFileSafe(filepath: string): Result[string, string] =
  const MaxFileByteSize = 1 * 1024 * 1024 # 1 MB
  if not fileExists(filepath):
    return err(fmt"{filepath}: file not found")
  try:
    let fileByteSize = getFileSize(filepath)
    if fileByteSize > MaxFileByteSize:
      err(fmt"{filepath} file exceeds 1 MB limit ({fileByteSize} bytes).")
    else:
      let source = readFile(filepath)
      let pos = validateUtf8(source)
      if pos == -1: ok(source)
      else: err(fmt"{filepath} invalid UTF-8 byte at position {pos}.")
  except CatchableError:
    err(fmt"{filepath} failed to read file.")

proc dump(filepath: string, tokens: seq[Token]): string =
  var content: seq[string]
  content.add(fmt"--- // START {filepath} tokens ({tokens.len}) ---")
  for token in tokens:
    content.add($(token))
  content.add(fmt"--- // END {filepath} ---")
  return content.join("\n")

proc loadFile(filepath: string, indentWidth: uint32,
    dumpTokens: bool, vendorRoots: VendorRoots): Result[File, string] =
  let source = ? readFileSafe(filepath)
  let tokens = ? tokenize(source, filepath)
  if dumpTokens: echo filepath.dump(tokens)
  let parser = newParser(filepath, indentWidth, tokens)
  parser.parseFile(vendorRoots)

proc parse*(rootPath: string, indentWidth: uint32, dumpTokens: bool, vendorRoots: VendorRoots): Result[App, string] =
  ## BFS through imports, tokenize + parse each file.
  ## Returns App with files in topological order: leaves first, root last.
  ## `vendorRoots` threads through every `parseFile` call so the
  ## per-file `aslFileSpec` can hand it to `newAslFile` (which uses
  ## it to auto-inject `import "@std"` in W10).
  ##
  ## `imp.absPath` was already resolved when the importing file was
  ## parsed (toAbsPath ran inside the import-line spec).
  ## Both the BFS walk and the topoSort reuse it directly through
  ## `importPaths` — re-resolving would produce the same value and
  ## slow down parsing unnecessarily.
  let parsed = ? bfs(
    rootPath,
    proc(path: string): Result[File, string] =
      loadFile(path, indentWidth, dumpTokens, vendorRoots),
    importPaths)

  # Topological sort with cycle detection (leaves first, root last)
  let sortedPaths = ? topoSort(rootPath, proc(path: string): seq[string] =
    if parsed.hasKey(path): importPaths(parsed[path])
    else: @[])

  var files: seq[File]
  for path in sortedPaths:
    files.add(parsed[path])
  ok(newApp(files))
