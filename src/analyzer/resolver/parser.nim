import strformat, strutils, unicode, results, options, tables, os

# Location is re-exported so downstream layers (resolver, analyzer,
# tests) can consume it via a single `import parser` — it's part of
# the parser's public surface (every AST node carries one). The rest
# of the tokenizer (Token, TokenKind, tokenize) stays private to the
# parser layer.
import ./parser/tokenizer
export tokenizer.location

# combinators.nim (Spec[T] + oneOf / any / pair / prefixed / ...) is
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

import ./parser/argdef
export argdef

import ./parser/structref
export structref

import ./parser/unionref
export unionref

import ./parser/requires
export requires

import ./parser/structdef
export structdef

import ./parser/variantdef
export variantdef

import ./parser/uniondef
export uniondef

import ./parser/datadef
export datadef

import ./parser/funcdef
export funcdef

import ./parser/externfunc
export externfunc

import ./parser/getter
export getter

import ./parser/literalinit
export literalinit

import ./parser/patterns
export patterns

import ./parser/statement
export statement

import ./parser/userfunc
export userfunc

import ./parser/function
export function

import ./parser/generics
export generics

import ./parser/modules
export modules

import ./parser/types
export types

import ./parser/files
export files

import ./parser/app
export app

# import ./parser/combinators
# export combinators
import ./parser/error
import ./parser/decorator
import ./parser/utils

type File = files.File

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

proc run*[T](parser: Parser, spec: Spec[T]): Result[T, ParserError] =
  let indexCheckpoint = parser.index
  let levelCheckpoint = parser.level
  let maybeValue = spec.parseFn(parser)
  if maybeValue.isErr and not maybeValue.error.fatal:
    parser.index = indexCheckpoint
    parser.level = levelCheckpoint
  return maybeValue

proc run*[T](parser: Parser, parseFn: proc(p: Parser): Result[T, ParserError]): Result[T, ParserError] =
  ## Same checkpoint/restore semantics as the Spec[T] overload, but
  ## accepts a plain parsing proc directly. Used when converting
  ## `Spec[T]`-wrapped specs to top-level procs.
  let indexCheckpoint = parser.index
  let levelCheckpoint = parser.level
  let maybeValue = parseFn(parser)
  if maybeValue.isErr and not maybeValue.error.fatal:
    parser.index = indexCheckpoint
    parser.level = levelCheckpoint
  return maybeValue

proc runOptional*[T](parser: Parser, parseFn: proc(p: Parser): Result[T, ParserError]): Result[Option[T], ParserError] =
  ## Runs `parseFn` and returns `some(value)` on success, `none(T)` on
  ## non-fatal failure, and propagates fatal errors. Mirrors the
  ## `optional(spec)` combinator for plain parsing procs.
  let maybeValue = parser.run(parseFn)
  if maybeValue.isOk: ok(some(maybeValue.get))
  elif maybeValue.error.fatal: err(maybeValue.error)
  else: ok(none(T))

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

proc separated*[A, S, B](a: Spec[A], sep: Spec[S], b: Spec[B]): Spec[(A, B)] =
  ## Parse `a sep b`; discard the separator, return `(A, B)`. Reads
  ## like the grammar rule "a separated-by sep from b". The
  ## grammar-natural collapse of `pair(a, prefixed(sep, b))` — same
  ## behaviour, one atom instead of two nested ones.
  pair(a, prefixed(sep, b))

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
  let composed = prefixed(
    pair(punctuationSpec(open), ws0),
    suffixed(inner, pair(ws0, punctuationSpec(close))))
  Spec[T](name: name, parseFn: composed.parseFn)

# ============================================================
# Comment + ignorable line
# ============================================================

proc parseComment*(parser: Parser): Result[Location, ParserError] =
  let hashtag = ? parser.run(hashSpec)
  discard parser.run(any(anyTokenExceptNewlineSpec("comment character")))
  ok(hashtag.loc)

# space* comment? newline
proc parseIgnorableLine*(parser: Parser): Result[Location, ParserError] =
  let loc = parser.loc
  discard ? parser.run(ws0)
  discard ? parser.runOptional(parseComment)
  discard ? parser.run(newlineSpec)
  ok(loc)

proc parseBlankLines*(parser: Parser): Result[seq[Location], ParserError] =
  ## Zero-or-more blank / comment lines.
  var lines: seq[Location]
  while true:
    let maybeLine = parser.run(parseIgnorableLine)
    if maybeLine.isErr:
      if maybeLine.error.fatal: return err(maybeLine.error)
      break
    lines.add(maybeLine.get)
  ok(lines)


# ============================================================
# Separator helpers
# ============================================================

proc separatorSpec*(sep: string): Spec[Token] =
  ## Parse `ws0 sep ws0`; return the sep token. Whitespace-tolerant
  ## on both sides of the punctuation.
  prefixed(ws0, suffixed(punctuationSpec(sep), ws0))

let commaWithSpacesSpec* = separatorSpec(",")
let colonWithSpacesSpec* = separatorSpec(":")
let equalsSeparatorSpec* = separatorSpec("=")



# ============================================================
# Space + indentation
# ============================================================

type Space* = ref object
  spaces: uint32
  loc: Location

proc newSpace*(spaces: uint32, loc: Location): Space =
  Space(spaces: spaces, loc: loc)


proc parseIndentation*(parser: Parser): Result[Space, ParserError] =
  let loc = parser.loc
  let spaces = ? parser.run(ws0)

  var count: uint32 = 0
  for space in spaces: count += space.value.len.uint32
  let expected = parser.indentWidth * parser.level
  if count != expected:
    let msg = fmt"indentation error expected {expected} but found {count} space(s)"
    err(newParserError(msg, loc))
  else:
    ok(newSpace(count, loc))

let identifierHeadCharSpec = oneOf("identifier_head", [
  underscoreSpec,
  alphabetSpec,
])

let identifierTailCharSpec = oneOf("identifier_tail", [
  identifierHeadCharSpec,
  digitSpec,
])

proc parseIdentifier*(parser: Parser): Result[Identifier, ParserError] =
  let head = ? parser.run(identifierHeadCharSpec)
  let tails = ? parser.run(any(identifierTailCharSpec))
  var content = head.value
  for tail in tails: content.add(tail.value)
  newIdentifier(content, head.loc)

proc parseKeyword*(parser: Parser, keyword: string): Result[Location, ParserError] =
  let ident = ? parser.parseIdentifier()
  if ident.value != keyword:
    let msg = fmt"expected keyword '{keyword}' but found '{ident.value}'"
    return err(newParserError(msg, ident.loc))
  ok(ident.loc)

# Curried adapter for callers still using `parser.run(keywordSpec("foo"))`.
proc keywordSpec*(keyword: string): Spec[Location] =
  Spec[Location](
    name: "'" & keyword & "'",
    parseFn: proc(parser: Parser): Result[Location, ParserError] =
      parser.parseKeyword(keyword))

# Spec adapter — `identifierSpec` is still consumed by the `requires`
# clause's `separatedBy(identifierSpec, ...)` combinator chain.
let identifierSpec* = Spec[Identifier](name: "identifier", parseFn: parseIdentifier)

proc parseDecoratorLine*(parser: Parser): Result[Decorator, ParserError] =
  discard ? parser.parseIndentation()
  discard ? parser.run(punctuationSpec("@"))
  let ident = ? parser.parseIdentifier()
  discard ? parser.run(parseIgnorableLine)
  ok(newDecorator(ident))

proc parseDecoratorLines*(parser: Parser): Result[seq[Decorator], ParserError] =
  ## Zero-or-more decorator lines (blank/comment lines between them
  ## are NOT skipped — that mirrors the previous `any(decoratorLineSpec)`
  ## semantics, which stopped at the first line that wasn't a
  ## decorator).
  var decorators: seq[Decorator]
  while true:
    let maybeDec = parser.run(parseDecoratorLine)
    if maybeDec.isErr:
      if maybeDec.error.fatal: return err(maybeDec.error)
      break
    decorators.add(maybeDec.get)
  ok(decorators)


proc makeEscapedParser(character: string, charSpec: Spec[Token]):
    proc(parser: Parser): Result[StringContent, ParserError] =
  ## Returns a parser proc for a single `\X` escape sequence.
  result = proc(parser: Parser): Result[StringContent, ParserError] =
    let backslash = ? parser.run(backslashSpec)
    let token = ? parser.run(charSpec)
    if token.value != character:
      return err(newParserError(
        fmt"expected '\\{character}' but found '\\{token.value}'", token.loc))
    ok(newStringContent("\\" & character, backslash.loc))

let parseEscapedBackslash = makeEscapedParser("\\", backslashSpec)
let parseEscapedDoubleQuote = makeEscapedParser("\"", doubleQuoteSpec)
let parseEscapedNewline = makeEscapedParser("n", alphabetSpec)
let parseEscapedTab = makeEscapedParser("t", alphabetSpec)

proc parseEscapedStringContent(parser: Parser): Result[StringContent, ParserError] =
  var errors: seq[ParserError]
  let maybeBackslash = parser.run(parseEscapedBackslash)
  if maybeBackslash.isOk: return maybeBackslash
  errors.add(maybeBackslash.error)
  let maybeQuote = parser.run(parseEscapedDoubleQuote)
  if maybeQuote.isOk: return maybeQuote
  errors.add(maybeQuote.error)
  let maybeNewline = parser.run(parseEscapedNewline)
  if maybeNewline.isOk: return maybeNewline
  errors.add(maybeNewline.error)
  let maybeTab = parser.run(parseEscapedTab)
  if maybeTab.isOk: return maybeTab
  errors.add(maybeTab.error)
  err(max(errors))

proc parseUnescapedStringContent(parser: Parser): Result[StringContent, ParserError] =
  let token = ? parser.run(anyTokenExceptNewlineSpec("unescaped string character"))
  if token.value == "\"" or token.value == "\\":
    return err(newParserError(
      fmt"expected a valid string character but found '{token.value}'", token.loc))
  ok(newStringContent(token.value, token.loc))

proc parseStringContent(parser: Parser): Result[StringContent, ParserError] =
  let maybeEscaped = parser.run(parseEscapedStringContent)
  if maybeEscaped.isOk: return maybeEscaped
  let maybeUnescaped = parser.run(parseUnescapedStringContent)
  if maybeUnescaped.isOk: return maybeUnescaped
  err(max(@[maybeEscaped.error, maybeUnescaped.error]))

proc parseStringLiteral*(parser: Parser): Result[StringLiteral, ParserError] =
  let openQuote = ? parser.run(doubleQuoteSpec)
  var content: string
  while true:
    let maybeChar = parser.run(parseStringContent)
    if maybeChar.isErr:
      if maybeChar.error.fatal: return err(maybeChar.error)
      break
    content.add(maybeChar.get.content)
  discard ? parser.run(doubleQuoteSpec)
  ok(newStringLiteral(content, openQuote.loc))

# Spec adapter for stringLiteralSpec — still consumed by remaining
# combinator chains (import specs, literalTypeSpec, etc.).
let stringLiteralSpec* = Spec[StringLiteral](name: "string_literal", parseFn: parseStringLiteral)

# digit+
proc parseUnsignedIntegerLiteral*(parser: Parser): Result[UnsignedIntegerLiteral, ParserError] =
  let loc = parser.loc
  let digits = ? parser.run(atLeastOne(digitSpec))
  var value: string
  for d in digits: value.add(d.value)
  ok(newUnsignedIntegerLiteral(value, loc))

# (+ | -) digit+
let signSpec = oneOf("sign", [punctuationSpec("+"), punctuationSpec("-")])

proc parseSignedIntegerLiteral*(parser: Parser): Result[SignedIntegerLiteral, ParserError] =
  let sign = ? parser.run(signSpec)
  let magnitude = ? parser.parseUnsignedIntegerLiteral()
  ok(newSignedIntegerLiteral(sign.value, magnitude, sign.loc))

proc parseIntegerLiteral*(parser: Parser): Result[IntegerLiteral, ParserError] =
  var errors: seq[ParserError]
  let maybeSigned = parser.run(parseSignedIntegerLiteral)
  if maybeSigned.isOk: return ok(newIntegerLiteral(maybeSigned.get))
  errors.add(maybeSigned.error)
  let maybeUnsigned = parser.run(parseUnsignedIntegerLiteral)
  if maybeUnsigned.isOk: return ok(newIntegerLiteral(maybeUnsigned.get))
  errors.add(maybeUnsigned.error)
  err(max(errors))

# Float-literal is a three-way alternation over per-form parsers, each with a
# single responsibility:
#   `parseNanFloat`     — matches the bare token `nan` (no sign allowed).
#   `parseInfFloat`     — matches `inf` with an optional `+` / `-` prefix.
#   `parseNumericFloat` — matches the digit-starting numeric form.
# Special-value forms run first because they start with identifier
# tokens; the numeric form couldn't reach them anyway (it requires a
# leading digit or sign+digit).

# `nan` — IEEE-754 quiet NaN. Unsigned only: `+nan` / `-nan` are
# rejected at parse time (the NaN sign bit exists in the hardware
# representation but is rarely meaningful in source code).
proc parseNanFloat(parser: Parser): Result[FloatLiteral, ParserError] =
  let ident = ? parser.parseIdentifier()
  if ident.value != "nan":
    return err(newParserError(fmt"expected 'nan' but found `{ident.value}`", ident.loc))
  ok(newFloatLiteral("nan", ident.loc))

# `inf` — IEEE-754 infinity. Optional `+` / `-` sign prefix; the sign
# folds into the stored literal value so downstream `analyzeFloatLiteral`
# can distinguish `+inf` from `-inf`.
proc parseInfFloat(parser: Parser): Result[FloatLiteral, ParserError] =
  let loc = parser.loc
  let maybeSign = parser.run(signSpec)
  let signStr = if maybeSign.isOk: maybeSign.get.value else: ""
  let ident = ? parser.parseIdentifier()
  if ident.value != "inf":
    return err(newParserError(fmt"expected 'inf' but found `{ident.value}`", ident.loc))
  ok(newFloatLiteral(signStr & "inf", loc))

# (+|-)? digit+ ("." digit+)? ((e|E) (+|-)? digit+)?
# Must have either decimal part or exponent to distinguish from integer
proc parseNumericFloat(parser: Parser): Result[FloatLiteral, ParserError] =
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

proc parseFloatLiteral*(parser: Parser): Result[FloatLiteral, ParserError] =
  var errors: seq[ParserError]
  let maybeNan = parser.run(parseNanFloat)
  if maybeNan.isOk: return maybeNan
  errors.add(maybeNan.error)
  let maybeInf = parser.run(parseInfFloat)
  if maybeInf.isOk: return maybeInf
  errors.add(maybeInf.error)
  let maybeNum = parser.run(parseNumericFloat)
  if maybeNum.isOk: return maybeNum
  errors.add(maybeNum.error)
  err(max(errors))

proc parseLiteral*(parser: Parser): Result[Literal, ParserError] =
  var errors: seq[ParserError]
  let maybeString = parser.run(parseStringLiteral)
  if maybeString.isOk: return ok(newLiteral(maybeString.get))
  errors.add(maybeString.error)
  let maybeFloat = parser.run(parseFloatLiteral)
  if maybeFloat.isOk: return ok(newLiteral(maybeFloat.get))
  errors.add(maybeFloat.error)
  let maybeInt = parser.run(parseIntegerLiteral)
  if maybeInt.isOk: return ok(newLiteral(maybeInt.get))
  errors.add(maybeInt.error)
  err(max(errors))

proc parseLiteralType*(parser: Parser): Result[LiteralDef, ParserError] =
  discard ? parser.parseIndentation()
  let loc = ? parser.parseKeyword("literal")
  discard ? parser.run(colonWithSpacesSpec)
  let strLit = ? parser.parseStringLiteral()
  ok(newLiteralDef(strLit, loc))


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
# `parseArgumentType` is self-referential: type params like
# `Map[String, List[Int]]` contain nested argument types. Nim's
# `proc` declarations handle recursion natively (a proc body can call
# the enclosing proc by name).
proc parseArgumentType*(parser: Parser): Result[ArgumentType, ParserError] =
  let rootIdent = ? parser.parseIdentifier()
  # Optional `[T, U, ...]` type params — parseArgumentType recurses
  # into itself for each element.
  let maybeImpls = ? parser.runOptional(proc(p: Parser): Result[seq[ArgumentType], ParserError] =
    discard ? p.run(punctuationSpec("["))
    discard ? p.run(ws0)
    var params: seq[ArgumentType]
    let firstAttempt = p.run(parseArgumentType)
    if firstAttempt.isOk:
      params.add(firstAttempt.get)
      while true:
        let sep = p.run(commaWithSpacesSpec)
        if sep.isErr: break
        let next = ? p.parseArgumentType()
        params.add(next)
    discard ? p.run(ws0)
    discard ? p.run(punctuationSpec("]"))
    ok(params))
  let maybeBanged = ? parser.runOptional(proc(p: Parser): Result[Token, ParserError] =
    p.run(bangSpec))

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

proc parseArgumentDef*(parser: Parser): Result[ArgumentDef, ParserError] =
  let name = ? parser.parseIdentifier()
  discard ? parser.run(colonWithSpacesSpec)
  let argType = ? parser.parseArgumentType()
  ok(newArgumentDef(name, argType))

# Spec adapter.
let argumentDefSpec* = Spec[ArgumentDef](name: "argument_definition", parseFn: parseArgumentDef)

proc parseArgumentDefList*(parser: Parser): Result[ArgumentDefList, ParserError] =
  let loc = parser.loc
  let argDefs = ? parser.run(contained("argument_definition_list", "(",
    separatedBy(argumentDefSpec, commaWithSpacesSpec), ")"))
  newArgumentDefList(argDefs, loc)


# Variant pattern field: name [":" binding] — bare `name` is sugar for
# `name: name`, mirroring the initializer kwarg shorthand. When the
# binding suffix is absent the parser synthesizes a binding with the
# same identifier (and the same source location).
proc parseUnionPatternField*(parser: Parser): Result[UnionPatternField, ParserError] =
  let name = ? parser.parseIdentifier()
  let maybeBinding = ? parser.runOptional(proc(p: Parser): Result[Identifier, ParserError] =
    discard ? p.run(colonWithSpacesSpec)
    p.parseIdentifier())
  let binding = if maybeBinding.isSome: maybeBinding.get else: name
  ok(newUnionPatternField(name, binding, name.loc))

# Spec adapter.
let unionPatternFieldSpec* = Spec[UnionPatternField](
  name: "variant_pattern_field", parseFn: parseUnionPatternField)

# Variant pattern: VariantName { field: binding, field: binding }
proc parseUnionPattern*(parser: Parser): Result[UnionPattern, ParserError] =
  let name = ? parser.parseIdentifier()
  discard ? parser.run(ws0)
  let fields = ? parser.run(contained("variant_fields", "{",
    separatedBy(unionPatternFieldSpec, commaWithSpacesSpec), "}"))
  newUnionPattern(name, fields)

proc parseCasePattern*(parser: Parser): Result[CasePattern, ParserError] =
  var errors: seq[ParserError]
  let maybeInt = parser.run(parseIntegerLiteral)
  if maybeInt.isOk: return ok(newCasePattern(maybeInt.get))
  errors.add(maybeInt.error)
  let maybeUnion = parser.run(parseUnionPattern)
  if maybeUnion.isOk: return ok(newCasePattern(maybeUnion.get))
  errors.add(maybeUnion.error)
  let maybeIdent = parser.run(parseIdentifier)
  if maybeIdent.isOk: return ok(newCasePattern(maybeIdent.get))
  errors.add(maybeIdent.error)
  err(max(errors))

# import { Name, Name } from "path"
# identifier ("as" identifier)?
proc parseImportedType*(parser: Parser): Result[ImportedType, ParserError] =
  let name = ? parser.parseIdentifier()
  let maybeAs = parser.run(ws1)
  if maybeAs.isErr:
    return ok(newImportedType(name, none(Identifier), name.loc))
  let maybeAsKeyword = parser.run(keywordSpec("as"))
  if maybeAsKeyword.isErr:
    return ok(newImportedType(name, none(Identifier), name.loc))
  discard ? parser.run(ws1)
  let alias = ? parser.parseIdentifier()
  ok(newImportedType(name, some(alias), name.loc))

# Spec adapter.
let importedTypeSpec* = Spec[ImportedType](name: "import_name", parseFn: parseImportedType)

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
proc parseExplicitImportLine*(parser: Parser): Result[Import, ParserError] =
  let loc = ? parser.parseKeyword("import")
  discard ? parser.run(ws1)
  let names = ? parser.run(contained("import_names", "{",
    separatedBy(importedTypeSpec, commaWithSpacesSpec), "}"))
  discard ? parser.run(ws1)
  discard ? parser.parseKeyword("from")
  discard ? parser.run(ws1)
  let source = ? parser.parseStringLiteral()
  discard ? parser.run(parseIgnorableLine)
  let parsedPath = ? toImportPath(source.value, source.loc)
  let maybePath = toAbsPath(parsedPath, parser.filepath, initTable[string, string]())
  if maybePath.isOk:
    newImport(names, parsedPath, maybePath.get, loc)
  else:
    err(newParserError(maybePath.error, source.loc))

# Shorthand form: `import "path"` — brings every public defined
# type from the target file into scope under each type's original
# name. The names list is materialized by the resolver via
# `publicTypes()` once the target file's parser AST is available.
proc parseShorthandImportLine*(parser: Parser): Result[Import, ParserError] =
  let loc = ? parser.parseKeyword("import")
  discard ? parser.run(ws1)
  let source = ? parser.parseStringLiteral()
  discard ? parser.run(parseIgnorableLine)
  let parsedPath = ? toImportPath(source.value, source.loc)
  let maybePath = toAbsPath(parsedPath, parser.filepath, initTable[string, string]())
  if maybePath.isOk:
    newImport(parsedPath, maybePath.get, loc)
  else:
    err(newParserError(maybePath.error, source.loc))

# Try explicit first — the `{` after `import ` disambiguates
# immediately; shorthand backtracks cleanly once explicit fails.
proc parseImportLine*(parser: Parser): Result[Import, ParserError] =
  let maybeExplicit = parser.run(parseExplicitImportLine)
  if maybeExplicit.isOk: return maybeExplicit
  let maybeShorthand = parser.run(parseShorthandImportLine)
  if maybeShorthand.isOk: return maybeShorthand
  err(max(@[maybeExplicit.error, maybeShorthand.error]))

proc parseImport*(parser: Parser): Result[Import, ParserError] =
  ## Skips leading blank / comment lines, then parses one import line
  ## (either explicit `import { A, B } from "path"` or shorthand
  ## `import "path"`).
  discard ? parser.run(parseBlankLines)
  parser.parseImportLine()

proc parseImports*(parser: Parser): Result[seq[Import], ParserError] =
  ## Parses zero-or-more consecutive import lines. Stops at the first
  ## non-fatal parse failure (typically the start of a module block).
  var imports: seq[Import]
  while true:
    let maybeImp = parser.run(parseImport)
    if maybeImp.isErr:
      if maybeImp.error.fatal: return err(maybeImp.error)
      break
    imports.add(maybeImp.get)
  ok(imports)


proc parseGetter*(parser: Parser): Result[Getter, ParserError] =
  let target = ? parser.parseIdentifier()
  discard ? parser.run(punctuationSpec("."))
  let field = ? parser.parseIdentifier()
  ok(newGetter(target, field, target.loc))

# type literal
proc parseLiteralInitializer*(parser: Parser): Result[LiteralInitializer, ParserError] =
  let argType = ? parser.parseArgumentType()
  discard ? parser.run(ws1)
  let lit = ? parser.parseLiteral()
  ok(newLiteralInitializer(argType, lit, argType.loc))

# ============================================================
# Body cluster — mutually recursive
# ============================================================
#
# Expression → FunctionCall → ArgumentList → Expression, and
# Match → CaseBlock → StatementList → StatementLine → Statement → Match.
# Nim's forward declarations resolve the cycle; each proc below is
# implemented later in this section.
proc parseExpression*(parser: Parser): Result[Expression, ParserError]
proc parseStatementList*(parser: Parser): Result[StatementList, ParserError]
proc parseArgumentList*(parser: Parser): Result[ArgumentList, ParserError]
proc parseFunctionCall*(parser: Parser): Result[FunctionCall, ParserError]
proc parseKwarg*(parser: Parser): Result[KeywordArgument, ParserError]
proc parseKwargList*(parser: Parser): Result[KeywordArgumentList, ParserError]
proc parseUnionInitializer*(parser: Parser): Result[UnionInitializer, ParserError]
proc parseStructInitializer*(parser: Parser): Result[StructInitializer, ParserError]
proc parseInitializer*(parser: Parser): Result[Initializer, ParserError]
proc parseAssignment*(parser: Parser): Result[Assignment, ParserError]
proc parseSetter*(parser: Parser): Result[Setter, ParserError]
proc parseInlineStatement*(parser: Parser): Result[Statement, ParserError]
proc parseCase*(parser: Parser): Result[CaseBlock, ParserError]
proc parseMatch*(parser: Parser): Result[MatchExpression, ParserError]
proc parseStatementLine*(parser: Parser): Result[Statement, ParserError]

# Spec adapter — `expressionSpec` is still consumed by `parseArgumentList`'s
# `separatedBy(expressionSpec, ...)` combinator chain.
let expressionSpec* = Spec[Expression](name: "expression",
  parseFn: proc(p: Parser): Result[Expression, ParserError] = parseExpression(p))

proc parseArgumentList*(parser: Parser): Result[ArgumentList, ParserError] =
  let loc = parser.loc
  let args = ? parser.run(contained("argument_list", "(",
    separatedBy(expressionSpec, commaWithSpacesSpec), ")"))
  ok(newArgumentList(args, loc))

proc parseFunctionCall*(parser: Parser): Result[FunctionCall, ParserError] =
  let target = ? parser.parseIdentifier()
  discard ? parser.run(punctuationSpec("."))
  let method0 = ? parser.parseIdentifier()
  discard ? parser.run(ws0)
  let args = ? parser.parseArgumentList()
  ok(newFunctionCall(target, method0, args))

proc parseKwarg*(parser: Parser): Result[KeywordArgument, ParserError] =
  let name = ? parser.parseIdentifier()
  let maybeExpr = ? parser.runOptional(proc(p: Parser): Result[Expression, ParserError] =
    discard ? p.run(colonWithSpacesSpec)
    p.parseExpression())
  # Shorthand: `Struct { x }` is sugar for `Struct { x: x }`. When
  # the `: expression` suffix is absent the value is synthesized as
  # a bare Variable of the same name; the shorthand identifier's
  # location carries through so diagnostics point at the source
  # token the user actually wrote.
  let expr = if maybeExpr.isSome: maybeExpr.get else: newExpression(name)
  ok(newKeywordArgument(name, expr, name.loc))

# Spec adapter (kwargListSpec uses this via `separatedBy(kwargSpec, ...)`).
let kwargSpec* = Spec[KeywordArgument](name: "keyword_argument", parseFn: parseKwarg)

proc parseKwargList*(parser: Parser): Result[KeywordArgumentList, ParserError] =
  let loc = parser.loc
  let args = ? parser.run(contained("keyword_argument_list", "{",
    separatedBy(kwargSpec, commaWithSpacesSpec), "}"))
  newKeywordArgumentList(args, loc)

# Type.Variant { fields } (bare — drives leave-as-is inference) or
# Type[Impls].Variant { fields } (explicit-impls — escape hatch when
# leave-as-is can't produce a fully-bound type). Both productions land
# on the same UnionRef shape carrying an impls seq; empty means bare.
proc parseUnionInitializer*(parser: Parser): Result[UnionInitializer, ParserError] =
  let typeRef = ? parser.parseArgumentType()
  discard ? parser.run(punctuationSpec("."))
  let variant = ? parser.parseIdentifier()
  discard ? parser.run(ws0)
  let fields = ? parser.parseKwargList()
  let unionRef = newUnionRef(typeRef.root, typeRef.impls, typeRef.loc)
  ok(newUnionInitializer(unionRef, variant, fields, typeRef.loc))

# Either `Type { fields }` (bare) or `Type[Impls] { fields }` (explicit
# impls, used for phantom-typed structs whose module declares a requires
# block). Both productions land on the same StructRef shape carrying an
# impls seq; empty means bare.
proc parseStructInitializer*(parser: Parser): Result[StructInitializer, ParserError] =
  let typeRef = ? parser.parseArgumentType()
  discard ? parser.run(ws0)
  let fields = ? parser.parseKwargList()
  let structRef = newStructRef(typeRef.root, typeRef.impls, typeRef.loc)
  ok(newStructInitializer(structRef, fields, typeRef.loc))

proc parseInitializer*(parser: Parser): Result[Initializer, ParserError] =
  var errors: seq[ParserError]
  let maybeUnion = parser.run(parseUnionInitializer)
  if maybeUnion.isOk: return ok(newInitializer(maybeUnion.get))
  errors.add(maybeUnion.error)
  let maybeStruct = parser.run(parseStructInitializer)
  if maybeStruct.isOk: return ok(newInitializer(maybeStruct.get))
  errors.add(maybeStruct.error)
  let maybeLit = parser.run(parseLiteralInitializer)
  if maybeLit.isOk: return ok(newInitializer(maybeLit.get))
  errors.add(maybeLit.error)
  err(max(errors))

proc parseExpression*(parser: Parser): Result[Expression, ParserError] =
  var errors: seq[ParserError]
  let maybeLit = parser.run(parseLiteral)
  if maybeLit.isOk: return ok(newExpression(maybeLit.get))
  errors.add(maybeLit.error)
  let maybeInit = parser.run(parseInitializer)
  if maybeInit.isOk: return ok(newExpression(maybeInit.get))
  errors.add(maybeInit.error)
  let maybeCall = parser.run(parseFunctionCall)
  if maybeCall.isOk: return ok(newExpression(maybeCall.get))
  errors.add(maybeCall.error)
  let maybeGetter = parser.run(parseGetter)
  if maybeGetter.isOk: return ok(newExpression(maybeGetter.get))
  errors.add(maybeGetter.error)
  let maybeIdent = parser.run(parseIdentifier)
  if maybeIdent.isOk: return ok(newExpression(maybeIdent.get))
  errors.add(maybeIdent.error)
  err(max(errors))

proc parseAssignment*(parser: Parser): Result[Assignment, ParserError] =
  let target = ? parser.parseIdentifier()
  discard ? parser.run(equalsSeparatorSpec)
  let expr = ? parser.parseExpression()
  ok(newAssignment(target, expr, target.loc))

proc parseSetter*(parser: Parser): Result[Setter, ParserError] =
  let target = ? parser.parseGetter()
  discard ? parser.run(equalsSeparatorSpec)
  let expr = ? parser.parseExpression()
  ok(newSetter(target, expr, target.loc))

proc parseInlineStatement*(parser: Parser): Result[Statement, ParserError] =
  var errors: seq[ParserError]
  let maybeSet = parser.run(parseSetter)
  if maybeSet.isOk: return ok(newStatement(maybeSet.get))
  errors.add(maybeSet.error)
  let maybeAssign = parser.run(parseAssignment)
  if maybeAssign.isOk: return ok(newStatement(maybeAssign.get))
  errors.add(maybeAssign.error)
  let maybeExpr = parser.run(parseExpression)
  if maybeExpr.isOk: return ok(newStatement(maybeExpr.get))
  errors.add(maybeExpr.error)
  err(max(errors))

proc parseCaseLine(parser: Parser): Result[CasePattern, ParserError] =
  discard ? parser.parseKeyword("case")
  discard ? parser.run(ws1)
  let pat = ? parser.parseCasePattern()
  discard ? parser.run(ws0)
  discard ? parser.run(punctuationSpec(":"))
  ok(pat)

proc parseCase*(parser: Parser): Result[CaseBlock, ParserError] =
  discard ? parser.parseIndentation()
  let pat = ? parser.run(parseCaseLine)
  discard ? parser.run(parseIgnorableLine)
  parser.level += 1
  let bodyResult = parseStatementList(parser)
  parser.level -= 1
  if bodyResult.isErr:
    bodyResult.error.fatal = true
    return err(bodyResult.error)
  ok(newCaseBlock(pat, bodyResult.get, pat.loc))

# Match body: parses "match" keyword + subject + ":" + newline + caseBlocks
# Does NOT consume indentation — caller handles that
proc parseMatch*(parser: Parser): Result[MatchExpression, ParserError] =
  let loc = ? parser.parseKeyword("match")
  discard ? parser.run(ws1)
  # Match expressions cannot be the subject of another match expression.
  # parseExpression intentionally excludes match (match is parsed separately
  # in parseStatementLine). This check guards against future changes that
  # might add match to parseExpression.
  let subject = ? parser.parseExpression()
  case subject.kind:
  of ekMatch:
    return err(newParserError(
      "match expression cannot be the subject of another match", loc))
  of ekLiteral, ekFnCall, ekGetter, ekInitializer, ekVariable: discard
  discard parser.run(ws0)
  discard ? parser.run(punctuationSpec(":"))
  discard ? parser.run(parseIgnorableLine)
  parser.level += 1
  var cases: seq[CaseBlock]
  let firstCaseResult = block:
    discard parser.run(parseBlankLines)
    parser.run(parseCase)
  if firstCaseResult.isErr:
    parser.level -= 1
    firstCaseResult.error.fatal = true
    return err(firstCaseResult.error)
  cases.add(firstCaseResult.get)
  while true:
    discard parser.run(parseBlankLines)
    let nextCase = parser.run(parseCase)
    if nextCase.isErr:
      if nextCase.error.fatal:
        parser.level -= 1
        return err(nextCase.error)
      break
    cases.add(nextCase.get)
  parser.level -= 1
  ok(newMatchExpression(subject, cases, loc))

proc parseStatementLine*(parser: Parser): Result[Statement, ParserError] =
  discard parser.run(parseBlankLines)
  discard ? parser.parseIndentation()
  # Try match assignment: identifier = match ...:
  let maybeMatchAssign = parser.run(proc(p: Parser): Result[Statement, ParserError] =
    let target = ? p.parseIdentifier()
    discard ? p.run(equalsSeparatorSpec)
    let matchExpr = ? p.parseMatch()
    ok(newStatement(newAssignment(target, newExpression(matchExpr), target.loc))))
  if maybeMatchAssign.isOk: return ok(maybeMatchAssign.get)
  # Try standalone match: match ...:
  let maybeMatch = parser.run(parseMatch)
  if maybeMatch.isOk:
    return ok(newStatement(newExpression(maybeMatch.get)))
  # Inline statements: statement + newline
  let statement = ? parser.run(parseInlineStatement)
  discard ? parser.run(parseIgnorableLine)
  ok(statement)

proc parseStatementList*(parser: Parser): Result[StatementList, ParserError] =
  var stmts: seq[Statement]
  let first = ? parser.run(parseStatementLine)
  stmts.add(first)
  while true:
    let maybeNext = parser.run(parseStatementLine)
    if maybeNext.isErr:
      if maybeNext.error.fatal: return err(maybeNext.error)
      break
    stmts.add(maybeNext.get)
  ok(newStatementList(stmts))

# TODO(post-analysis-expander): re-wire expansion after the analyzer once the
# post-analysis expander lands (see plans/plan_post_analysis_expansion.md).
# The expand* procs above (lines 540-748) are kept as reference for that move.


proc parseFunctionDef*(parser: Parser): Result[FunctionDef, ParserError] =
  let public = ? parser.run(presence(keywordSpec("public")))
  if public: discard ? parser.run(ws1)

  let funcLoc = ? parser.parseKeyword("func")
  discard ? parser.run(ws1)
  let funcName = ? parser.parseIdentifier()
  discard parser.run(ws0)
  let argDefList = ? parser.parseArgumentDefList()
  discard ? parser.run(colonWithSpacesSpec)
  let returnType = ? parser.parseArgumentType()
  ok(newFunctionDef(public, funcName, argDefList, returnType, funcLoc))

proc parseFunctionDefLine(parser: Parser): Result[FunctionDef, ParserError] =
  ## Indented single-line variant used by `parseFunctionDefs`.
  discard ? parser.parseIndentation()
  let def = ? parser.parseFunctionDef()
  discard ? parser.run(parseIgnorableLine)
  ok(def)

proc parseFunctionDefs*(parser: Parser): Result[seq[FunctionDef], ParserError] =
  ## Parses one-or-more function-definition lines. Used inside a
  ## `generic` block, which only carries signatures — no bodies.
  var defs: seq[FunctionDef]
  let first = ? parser.run(parseFunctionDefLine)
  defs.add(first)
  while true:
    let maybeNext = parser.run(parseFunctionDefLine)
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
  let decorators = ? parser.parseDecoratorLines()
  discard ? parser.parseIndentation()
  let h = ? parser.parseFunctionDef()
  discard ? parser.run(parseIgnorableLine)
  parser.level += 1
  let bodyResult = parseStatementList(parser)
  parser.level -= 1
  if bodyResult.isErr:
    bodyResult.error.fatal = true
    return err(bodyResult.error)
  ok(newUserFunction(decorators, h, bodyResult.get))

# @extern("symbol")
# public func name(args): ReturnType
proc parseExternFunction(parser: Parser): Result[ExternFunction, ParserError] =
  discard ? parser.parseIndentation()
  discard ? parser.run(punctuationSpec("@"))
  discard ? parser.parseKeyword("extern")
  discard parser.run(ws0)
  let loc = parser.loc
  let symbol = ? parser.run(contained("extern_symbol", "(", stringLiteralSpec, ")"))
  discard ? parser.run(parseIgnorableLine)
  discard ? parser.parseIndentation()
  let def = ? parser.parseFunctionDef()
  discard ? parser.run(parseIgnorableLine)
  ok(newExternFunction(symbol.value, def, loc))

proc parseFunction(parser: Parser): Result[Function, ParserError] =
  ## Parses one function block — skips leading blank lines, then tries
  ## the extern form; falls back to user function on non-fatal failure.
  discard parser.run(parseBlankLines)
  let f = parser.run(parseExternFunction)
  if f.isOk: return ok(newFunction(f.get))
  let u = ? parser.run(parseUserFunction)
  ok(newFunction(u))

proc parseFunctionList*(parser: Parser): Result[FunctionList, ParserError] =
  ## Parses zero-or-more function blocks (extern or user), then wraps
  ## them into a FunctionList (which enforces name+arity uniqueness).
  var funcs: seq[Function]
  while true:
    let maybeFn = parser.run(parseFunction)
    if maybeFn.isErr:
      if maybeFn.error.fatal: return err(maybeFn.error)
      break
    funcs.add(maybeFn.get)
  newFunctionList(funcs)


# struct: field+ (field is identifier ":" argumentType)
proc parseStructHeader(parser: Parser): Result[Location, ParserError] =
  let loc = ? parser.parseKeyword("struct")
  discard ? parser.run(ws0)
  discard ? parser.run(punctuationSpec(":"))
  ok(loc)

# Each field line: (blank lines) + indentation + argumentDef + newline
proc parseArgumentDefLine(parser: Parser): Result[ArgumentDef, ParserError] =
  discard ? parser.run(parseBlankLines)
  discard ? parser.parseIndentation()
  let def = ? parser.parseArgumentDef()
  discard ? parser.run(parseIgnorableLine)
  ok(def)

proc parseStructBody(parser: Parser): Result[seq[ArgumentDef], ParserError] =
  var fields: seq[ArgumentDef]
  let first = ? parser.run(parseArgumentDefLine)
  fields.add(first)
  while true:
    let maybeNext = parser.run(parseArgumentDefLine)
    if maybeNext.isErr:
      if maybeNext.error.fatal: return err(maybeNext.error)
      break
    fields.add(maybeNext.get)
  ok(fields)

proc parseStruct*(parser: Parser): Result[StructDef, ParserError] =
  discard ? parser.parseIndentation()
  let loc = ? parser.run(parseStructHeader)
  discard ? parser.run(parseIgnorableLine)
  parser.level += 1
  let bodyResult = parseStructBody(parser)
  parser.level -= 1
  if bodyResult.isErr:
    bodyResult.error.fatal = true
    return err(bodyResult.error)
  newStructDef(bodyResult.get, loc)

# union: variant+ (variant is identifier space* "{" (argDef, argDef)* "}")
# Braces are required — empty variants must be written `Timeout { }`. This
# mirrors the case-pattern side (`case Timeout { }:`) so the two shapes
# stay visually consistent and there's no bare `Timeout` form to confuse
# with a variable-binding case pattern.
proc parseVariantDefLine(parser: Parser): Result[VariantDef, ParserError] =
  discard parser.run(parseBlankLines)
  discard ? parser.parseIndentation()
  let name = ? parser.parseIdentifier()
  discard parser.run(ws0)
  let fields = ? parser.run(contained("variant_fields", "{",
    separatedBy(argumentDefSpec, commaWithSpacesSpec), "}"))
  discard ? parser.run(parseIgnorableLine)
  newVariantDef(name, fields, name.loc)

proc parseUnionHeader(parser: Parser): Result[Location, ParserError] =
  let loc = ? parser.parseKeyword("union")
  discard ? parser.run(ws0)
  discard ? parser.run(punctuationSpec(":"))
  ok(loc)

proc parseUnionBody(parser: Parser): Result[seq[VariantDef], ParserError] =
  var variants: seq[VariantDef]
  let first = ? parser.run(parseVariantDefLine)
  variants.add(first)
  while true:
    let maybeNext = parser.run(parseVariantDefLine)
    if maybeNext.isErr:
      if maybeNext.error.fatal: return err(maybeNext.error)
      break
    variants.add(maybeNext.get)
  ok(variants)

proc parseUnion*(parser: Parser): Result[UnionDef, ParserError] =
  discard ? parser.parseIndentation()
  let loc = ? parser.run(parseUnionHeader)
  discard ? parser.run(parseIgnorableLine)
  parser.level += 1
  let bodyResult = parseUnionBody(parser)
  parser.level -= 1
  if bodyResult.isErr:
    bodyResult.error.fatal = true
    return err(bodyResult.error)
  newUnionDef(bodyResult.get, loc)

proc parseData*(parser: Parser): Result[DataDef, ParserError] =
  ## Parses a module's data block: literal, struct, or union. Tries
  ## each in order; returns the error from whichever candidate
  ## reached farthest into the token stream.
  var errors: seq[ParserError]
  let maybeLiteral = parser.run(parseLiteralType)
  if maybeLiteral.isOk: return ok(newDataDef(maybeLiteral.get))
  else: errors.add(maybeLiteral.error)
  let maybeStruct = parser.run(parseStruct)
  if maybeStruct.isOk: return ok(newDataDef(maybeStruct.get))
  else: errors.add(maybeStruct.error)
  let maybeUnion = parser.run(parseUnion)
  if maybeUnion.isOk: return ok(newDataDef(maybeUnion.get))
  else: errors.add(maybeUnion.error)
  err(max(errors))

proc parseGenericHeader(parser: Parser): Result[GenericHeader, ParserError] =
  let public = ? parser.run(presence(keywordSpec("public")))
  if public: discard ? parser.run(ws1)
  let loc = ? parser.parseKeyword("generic")
  discard ? parser.run(ws1)
  let nameIdent = ? parser.parseIdentifier()
  discard parser.run(ws0)
  discard ? parser.run(punctuationSpec(":"))
  ok((public, nameIdent, loc))

proc parseGeneric*(parser: Parser): Result[Generic, ParserError] =
  ## Parses a `[public] generic Name:` block followed by its function
  ## definitions. Body failures are marked fatal — once past the
  ## header, the block cannot be backtracked out of.
  discard ? parser.parseIndentation()
  let h = ? parser.run(parseGenericHeader)
  discard ? parser.run(parseIgnorableLine)
  parser.level += 1
  let bodyResult = parseFunctionDefs(parser)
  parser.level -= 1
  if bodyResult.isErr:
    bodyResult.error.fatal = true
    return err(bodyResult.error)
  newGeneric(@[], h.public, h.name, bodyResult.get, h.loc)

# requires(Generic, Generic, ...)
proc parseRequires*(parser: Parser): Result[Requires, ParserError] =
  ## Parses a `requires(A, B, C)` line: the `requires` keyword followed
  ## by a parenthesised comma-separated identifier list.
  discard ? parser.parseIndentation()
  let loc = ? parser.parseKeyword("requires")
  discard ? parser.run(ws0)
  let names = ? parser.run(contained("requires_generics", "(",
    separatedBy(identifierSpec, commaWithSpacesSpec), ")"))
  discard ? parser.run(parseIgnorableLine)
  ok(newRequires(names, loc))


proc parseModuleHeader(parser: Parser): Result[ModuleHeader, ParserError] =
  let public = ? parser.run(presence(keywordSpec("public")))
  if public: discard ? parser.run(ws1)

  let loc = ? parser.parseKeyword("module")
  discard ? parser.run(ws1)
  let nameIdent = ? parser.parseIdentifier()
  discard parser.run(ws0)
  discard ? parser.run(punctuationSpec(":"))
  ok((public, nameIdent, loc))


proc parseModuleBody(parser: Parser): Result[ModuleBody, ParserError] =
  discard parser.run(parseBlankLines)
  let requires = ? parser.runOptional(parseRequires)
  discard parser.run(parseBlankLines)
  let data = ? parser.runOptional(parseData)
  let funcList = ? parser.parseFunctionList()
  ok((requires, data, funcList))

proc parseModule*(parser: Parser): Result[Module, ParserError] =
  ## Parses a `[public] module Name:` block with optional decorator
  ## lines. Body failures are marked fatal — once past the header,
  ## the block cannot be backtracked out of.
  let decorators = ? parser.parseDecoratorLines()
  discard ? parser.parseIndentation()
  let h = ? parser.run(parseModuleHeader)
  discard ? parser.run(parseIgnorableLine)
  parser.level += 1
  let bodyResult = parseModuleBody(parser)
  parser.level -= 1
  if bodyResult.isErr:
    bodyResult.error.fatal = true
    return err(bodyResult.error)
  let b = bodyResult.get
  newModule(decorators, h.public, h.name, b.requires, b.data, b.funcList, h.loc)



proc parseType(parser: Parser): Result[Type, ParserError] =
  ## Parses either a module or a generic block and wraps it as `Type`.
  ## Tries module first; if that fails non-fatally, tries generic;
  ## returns whichever error carried further into the token stream.
  var errors: seq[ParserError]
  let maybeModule = parser.run(parseModule)
  if maybeModule.isOk: return ok(newType(maybeModule.get))
  else: errors.add(maybeModule.error)
  let maybeGeneric = parser.run(parseGeneric)
  if maybeGeneric.isOk: return ok(newType(maybeGeneric.get))
  else: errors.add(maybeGeneric.error)
  err(max(errors))

proc parseDefinedType(parser: Parser): Result[Type, ParserError] =
  ## Skips leading blank / comment lines, then parses a module or
  ## generic block. Used at file level between top-level type blocks.
  discard ? parser.run(parseBlankLines)
  parser.parseType()

proc parseDefinedTypes(parser: Parser): Result[seq[Type], ParserError] =
  ## Parses one-or-more top-level `Type` blocks (module / generic),
  ## skipping blank lines between them. Fails if the first attempt
  ## does not yield a type.
  var items: seq[Type]
  let first = ? parser.run(parseDefinedType)
  items.add(first)
  while true:
    let maybeNext = parser.run(parseDefinedType)
    if maybeNext.isErr:
      if maybeNext.error.fatal: return err(maybeNext.error)
      break
    items.add(maybeNext.get)
  ok(items)

# aslFile: import* (module | generic)*  — user-authored source files.
proc parseAslFile(parser: Parser, vendorRoots: VendorRoots): Result[File, ParserError] =
  let imports = ? parser.parseImports()
  let items = ? parser.parseDefinedTypes()
  discard parser.run(parseBlankLines)
  # Force a parse attempt to get a specific error message
  if not parser.done(): discard ? parseType(parser)
  newAslFile(parser.filepath, imports, items, vendorRoots)

# aslrFile: (module | generic)*  — no imports section. Aslr files
# are the runtime interface; they cannot reference other files.
proc parseAslrFile(parser: Parser): Result[File, ParserError] =
  let items = ? parser.parseDefinedTypes()
  discard parser.run(parseBlankLines)
  # Force a parse attempt to get a specific error message
  if not parser.done(): discard ? parseType(parser)
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
