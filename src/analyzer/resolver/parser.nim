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


let indentationSpec* = Spec[Space](
  name: "indentation",
  parseFn: proc(parser: Parser): Result[Space, ParserError] =
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
)

let identifierHeadCharSpec* = oneOf("identifier_head", [
  underscoreSpec,
  alphabetSpec,
])

let identifierTailCharSpec* = oneOf("identifier_tail", [
  identifierHeadCharSpec,
  digitSpec,
])

let identifierSpec* = Spec[Identifier](
  name: "identifier",
  parseFn: proc(parser: Parser): Result[Identifier, ParserError] =
  let head = ? parser.run(identifierHeadCharSpec)
  let tails = ? parser.run(any(identifierTailCharSpec))
  var content = head.value
  for tail in tails: content.add(tail.value)
  newIdentifier(content, head.loc)
)

proc keywordSpec*(keyword: string): Spec[Location] =
  Spec[Location](
    name: "'" & keyword & "'",
    parseFn: proc(parser: Parser): Result[Location, ParserError] =
    let ident = ? parser.run(identifierSpec)
    if ident.value != keyword:
      let msg = fmt"expected keyword '{keyword}' but found '{ident.value}'"
      return err(newParserError(msg, ident.loc))
    ok(ident.loc)
  )

proc indentedLine*[T](inner: Spec[T]): Spec[T] =
  ## Parse `indentation inner ignorable_line`; return only inner.
  ## The grammar-natural shape for "one item on its own indented
  ## line" — decorators, field definitions, function definitions,
  ## etc. Prepend `blankLines` at the call site when the line may
  ## be preceded by blank/comment lines.
  prefixed(indentationSpec, suffixed(inner, ignorableLineSpec))

let decoratorLineSpec* = indentedLine(
    prefixed(punctuationSpec("@"), identifierSpec)).map(
  "decorator_line",
  proc(v: Identifier): Decorator = newDecorator(v))

# ============================================================
# Block helpers
# ============================================================

# Block without decorator support (case, struct, union, generic)
proc blockSpec*[H, B, R](name: string,
    header: Spec[H], body: Spec[B],
    combine: proc(h: H, b: B): R): Spec[R] =
  Spec[R](
    name: name,
    parseFn: proc(parser: Parser): Result[R, ParserError] =
    discard ? parser.run(indentationSpec)
    let h = ? parser.run(header)
    discard ? parser.run(ignorableLineSpec)
    # After header succeeds, body errors are fatal — they propagate
    # through run and any without backtracking or being swallowed.
    parser.level += 1
    let bodyResult = body.parseFn(parser)
    parser.level -= 1
    if bodyResult.isErr:
      bodyResult.error.fatal = true
      return err(bodyResult.error)
    ok(combine(h, bodyResult.get))
  )

proc blockSpec*[H, B, R](name: string,
    header: Spec[H], body: Spec[B],
    combine: proc(h: H, b: B): Result[R, ParserError]): Spec[R] =
  Spec[R](
    name: name,
    parseFn: proc(parser: Parser): Result[R, ParserError] =
    discard ? parser.run(indentationSpec)
    let h = ? parser.run(header)
    discard ? parser.run(ignorableLineSpec)
    parser.level += 1
    let bodyResult = body.parseFn(parser)
    parser.level -= 1
    if bodyResult.isErr:
      bodyResult.error.fatal = true
      return err(bodyResult.error)
    combine(h, bodyResult.get)
  )

# Block with decorator support (module, function)
proc decoratedBlockSpec*[H, B, R](name: string,
    header: Spec[H], body: Spec[B],
    combine: proc(decorators: seq[Decorator], h: H, b: B): R): Spec[R] =
  Spec[R](
    name: name,
    parseFn: proc(parser: Parser): Result[R, ParserError] =
    let decorators = ? parser.run(any(decoratorLineSpec))
    discard ? parser.run(indentationSpec)
    let h = ? parser.run(header)
    discard ? parser.run(ignorableLineSpec)
    parser.level += 1
    let bodyResult = body.parseFn(parser)
    parser.level -= 1
    if bodyResult.isErr:
      bodyResult.error.fatal = true
      return err(bodyResult.error)
    ok(combine(decorators, h, bodyResult.get))
  )

proc decoratedBlockSpec*[H, B, R](name: string,
    header: Spec[H], body: Spec[B],
    combine: proc(decorators: seq[Decorator], h: H, b: B): Result[R,
        ParserError]): Spec[R] =
  Spec[R](
    name: name,
    parseFn: proc(parser: Parser): Result[R, ParserError] =
    let decorators = ? parser.run(any(decoratorLineSpec))
    discard ? parser.run(indentationSpec)
    let h = ? parser.run(header)
    discard ? parser.run(ignorableLineSpec)
    parser.level += 1
    let bodyResult = body.parseFn(parser)
    parser.level -= 1
    if bodyResult.isErr:
      bodyResult.error.fatal = true
      return err(bodyResult.error)
    combine(decorators, h, bodyResult.get)
  )


proc escapedSpec(character: string, charSpec: Spec[Token]): Spec[
    StringContent] =
  Spec[StringContent](
    name: "'\\" & character & "'",
    parseFn: proc(parser: Parser): Result[StringContent, ParserError] =
    let backslash = ? parser.run(backslashSpec)
    let token = ? parser.run(charSpec)
    if token.value != character:
      return err(newParserError(
        fmt"expected '\\{character}' but found '\\{token.value}'", token.loc))
    ok(newStringContent("\\" & character, backslash.loc))
  )

let escapedBackslash = escapedSpec("\\", backslashSpec)
let escapedDoubleQuote = escapedSpec("\"", doubleQuoteSpec)
let escapedNewline = escapedSpec("n", alphabetSpec)
let escapedTab = escapedSpec("t", alphabetSpec)

let escapedStringContentSpec = oneOf("escaped_string_character", [
  escapedBackslash,
  escapedDoubleQuote,
  escapedNewline,
  escapedTab,
])

let unescapedStringContentSpec = Spec[StringContent](
  name: "unescaped_string_character",
  parseFn: proc(parser: Parser): Result[StringContent, ParserError] =
  let token = ? parser.run(anyTokenExceptNewlineSpec("unescaped string character"))
  if token.value == "\"" or token.value == "\\":
    return err(newParserError(
      fmt"expected a valid string character but found '{token.value}'", token.loc))
  ok(newStringContent(token.value, token.loc))
)

let stringContentSpec = oneOf("string_content", [
  escapedStringContentSpec,
  unescapedStringContentSpec,
])

let stringLiteralSpec* = Spec[StringLiteral](
  name: "string_literal",
  parseFn: proc(parser: Parser): Result[StringLiteral, ParserError] =
  let openQuote = ? parser.run(doubleQuoteSpec)
  let chars = ? parser.run(any(stringContentSpec))
  var content: string; for ch in chars: content.add(ch.content)
  discard ? parser.run(doubleQuoteSpec)
  ok(newStringLiteral(content, openQuote.loc))
)

# digit+
let unsignedIntegerLiteralSpec* = Spec[UnsignedIntegerLiteral](
  name: "unsigned_integer_literal",
  parseFn: proc(parser: Parser): Result[UnsignedIntegerLiteral, ParserError] =
  let loc = parser.loc
  let digits = ? parser.run(atLeastOne(digitSpec))
  var value: string
  for d in digits: value.add(d.value)
  ok(newUnsignedIntegerLiteral(value, loc))
)

# (+ | -) digit+
let signSpec = oneOf("sign", [punctuationSpec("+"), punctuationSpec("-")])
let signedIntegerLiteralSpec* = pair(signSpec, unsignedIntegerLiteralSpec).map(
  "signed_integer_literal",
  proc(t: (Token, UnsignedIntegerLiteral)): SignedIntegerLiteral =
    newSignedIntegerLiteral(t[0].value, t[1], t[0].loc))

let integerLiteralSpec* = oneOf("integer_literal", [
  signedIntegerLiteralSpec.map("signed_int",
    proc(v: SignedIntegerLiteral): IntegerLiteral = newIntegerLiteral(v)),
  unsignedIntegerLiteralSpec.map("unsigned_int",
    proc(v: UnsignedIntegerLiteral): IntegerLiteral = newIntegerLiteral(v)),
])

# Float-literal is a three-way `oneOf` over per-form specs, each with a
# single responsibility:
#   `nanFloatSpec`     — matches the bare token `nan` (no sign allowed).
#   `infFloatSpec`     — matches `inf` with an optional `+` / `-` prefix.
#   `numericFloatSpec` — matches the digit-starting numeric form.
# Special-value forms run first because they start with identifier
# tokens; the numeric form couldn't reach them anyway (it requires a
# leading digit or sign+digit).

# `nan` — IEEE-754 quiet NaN. Unsigned only: `+nan` / `-nan` are
# rejected at parse time (the NaN sign bit exists in the hardware
# representation but is rarely meaningful in source code).
let nanFloatSpec = Spec[FloatLiteral](
  name: "nan_float_literal",
  parseFn: proc(parser: Parser): Result[FloatLiteral, ParserError] =
  let ident = ? parser.run(identifierSpec)
  if ident.value != "nan":
    return err(newParserError(fmt"expected 'nan' but found `{ident.value}`", ident.loc))
  ok(newFloatLiteral("nan", ident.loc))
)

# `inf` — IEEE-754 infinity. Optional `+` / `-` sign prefix; the sign
# folds into the stored literal value so downstream `analyzeFloatLiteral`
# can distinguish `+inf` from `-inf`.
let infFloatSpec = Spec[FloatLiteral](
  name: "inf_float_literal",
  parseFn: proc(parser: Parser): Result[FloatLiteral, ParserError] =
  let loc = parser.loc
  let signSpec = oneOf("sign", [punctuationSpec("+"), punctuationSpec("-")])
  let maybeSign = parser.run(signSpec)
  let signStr = if maybeSign.isOk: maybeSign.get.value else: ""
  let ident = ? parser.run(identifierSpec)
  if ident.value != "inf":
    return err(newParserError(fmt"expected 'inf' but found `{ident.value}`", ident.loc))
  ok(newFloatLiteral(signStr & "inf", loc))
)

# (+|-)? digit+ ("." digit+)? ((e|E) (+|-)? digit+)?
# Must have either decimal part or exponent to distinguish from integer
let numericFloatSpec = Spec[FloatLiteral](
  name: "numeric_float_literal",
  parseFn: proc(parser: Parser): Result[FloatLiteral, ParserError] =
  let loc = parser.loc
  var value: string
  let signSpec = oneOf("sign", [punctuationSpec("+"), punctuationSpec("-")])
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
)

let floatLiteralSpec* = oneOf("float_literal", [
  nanFloatSpec, infFloatSpec, numericFloatSpec])

let literalSpec* = oneOf("literal", [
  stringLiteralSpec.map("string_literal",
    proc(v: StringLiteral): Literal = newLiteral(v)),
  floatLiteralSpec.map("float_literal",
    proc(v: FloatLiteral): Literal = newLiteral(v)),
  integerLiteralSpec.map("integer_literal",
    proc(v: IntegerLiteral): Literal = newLiteral(v)),
])

let literalTypeSpec* = pair(prefixed(indentationSpec, keywordSpec("literal")),
    prefixed(colonWithSpacesSpec, stringLiteralSpec)).map(
  "literal_type",
  proc(t: (Location, StringLiteral)): LiteralDef = newLiteralDef(t[1], t[0]))


# Forward-declared via newSpec because argumentTypeSpec is self-referential:
# type params like Map[String, List[Int]] contain nested argument types.
# The ref is created first (parseFn: nil), then filled in below so the
# closure can capture the already-existing ref for recursive calls.
let argumentTypeSpec* = newSpec[ArgumentType]("argument_type")

# Argument-type sugar: a trailing `!` on an argument type expands to
# `Status[<argType>]`. Parsed uniformly here so every argument-type
# position picks it up — function args, return types, kwarg field
# types, and the initializer type prefix all route through this spec.
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
argumentTypeSpec.parseFn = proc(parser: Parser): Result[ArgumentType, ParserError] =
  let rootIdent = ? parser.run(identifierSpec)
  let typeParams = contained("type_params", "[", separatedBy(argumentTypeSpec,
      commaWithSpacesSpec), "]")
  let maybeImpls = ? parser.run(optional(typeParams))
  let maybeBanged = ? parser.run(optional(bangSpec))

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

let argumentDefSpec* = separated(identifierSpec, colonWithSpacesSpec, argumentTypeSpec).map(
  "argument_definition",
  proc(t: (Identifier, ArgumentType)): ArgumentDef = newArgumentDef(t[0], t[1]))

let argumentDefListSpec* = Spec[ArgumentDefList](
  name: "argument_definition_list",
  parseFn: proc(parser: Parser): Result[ArgumentDefList, ParserError] =
  let loc = parser.loc
  let argDefs = ? parser.run(contained("argument_definition_list", "(",
    separatedBy(argumentDefSpec, commaWithSpacesSpec), ")"))
  newArgumentDefList(argDefs, loc)
)


# Variant pattern field: name [":" binding] — bare `name` is sugar for
# `name: name`, mirroring the initializer kwarg shorthand. When the
# binding suffix is absent the parser synthesizes a binding with the
# same identifier (and the same source location).
let unionPatternFieldSpec* = pair(
    identifierSpec,
    optional(prefixed(colonWithSpacesSpec, identifierSpec))
  ).map("variant_pattern_field",
    proc(t: (Identifier, Option[Identifier])): UnionPatternField =
      let binding = if t[1].isSome: t[1].get else: t[0]
      newUnionPatternField(t[0], binding, t[0].loc))

# Variant pattern: VariantName { field: binding, field: binding }
let unionPatternSpec* = pair(identifierSpec,
    prefixed(ws0, contained("variant_fields", "{",
      separatedBy(unionPatternFieldSpec, commaWithSpacesSpec), "}"))).map(
  "variant_pattern",
  proc(t: (Identifier, seq[UnionPatternField])): Result[UnionPattern, ParserError] =
    newUnionPattern(t[0], t[1]))

let casePatternSpec* = oneOf("case_pattern", [
  integerLiteralSpec.map("integer_pattern",
    proc(v: IntegerLiteral): CasePattern = newCasePattern(v)),
  unionPatternSpec.map("variant_pattern",
    proc(v: UnionPattern): CasePattern = newCasePattern(v)),
  identifierSpec.map("variable_pattern",
    proc(v: Identifier): CasePattern = newCasePattern(v)),
])

# import { Name, Name } from "path"
# identifier ("as" identifier)?
let importedTypeSpec* = Spec[ImportedType](
  name: "import_name",
  parseFn: proc(parser: Parser): Result[ImportedType, ParserError] =
  let name = ? parser.run(identifierSpec)
  let maybeAs = parser.run(ws1)
  if maybeAs.isErr:
    return ok(newImportedType(name, none(Identifier), name.loc))
  let maybeAsKeyword = parser.run(keywordSpec("as"))
  if maybeAsKeyword.isErr:
    return ok(newImportedType(name, none(Identifier), name.loc))
  discard ? parser.run(ws1)
  let alias = ? parser.run(identifierSpec)
  ok(newImportedType(name, some(alias), name.loc))
)

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
let explicitImportLineSpec* = Spec[Import](
  name: "explicit_import_line",
  parseFn: proc(parser: Parser): Result[Import, ParserError] =
  let loc = ? parser.run(keywordSpec("import"))
  discard ? parser.run(ws1)
  let names = ? parser.run(contained("import_names", "{",
    separatedBy(importedTypeSpec, commaWithSpacesSpec), "}"))
  discard ? parser.run(ws1)
  discard ? parser.run(keywordSpec("from"))
  discard ? parser.run(ws1)
  let source = ? parser.run(stringLiteralSpec)
  discard ? parser.run(ignorableLineSpec)
  let parsedPath = ? toImportPath(source.value, source.loc)
  let maybePath = toAbsPath(parsedPath, parser.filepath, initTable[string, string]())
  if maybePath.isOk:
    newImport(names, parsedPath, maybePath.get, loc)
  else:
    err(newParserError(maybePath.error, source.loc))
)

# Shorthand form: `import "path"` — brings every public defined
# type from the target file into scope under each type's original
# name. The names list is materialized by the resolver in W5 via
# `publicTypes()` once the target file's parser AST is available.
let shorthandImportLineSpec* = Spec[Import](
  name: "shorthand_import_line",
  parseFn: proc(parser: Parser): Result[Import, ParserError] =
  let loc = ? parser.run(keywordSpec("import"))
  discard ? parser.run(ws1)
  let source = ? parser.run(stringLiteralSpec)
  discard ? parser.run(ignorableLineSpec)
  let parsedPath = ? toImportPath(source.value, source.loc)
  let maybePath = toAbsPath(parsedPath, parser.filepath, initTable[string, string]())
  if maybePath.isOk:
    newImport(parsedPath, maybePath.get, loc)
  else:
    err(newParserError(maybePath.error, source.loc))
)

# Try explicit first — the `{` after `import ` disambiguates
# immediately; shorthand backtracks cleanly once explicit fails.
let importLineSpec* = oneOf("import_line", [
  explicitImportLineSpec,
  shorthandImportLineSpec,
])

let importSpec* = Spec[Import](
  name: "import_block",
  parseFn: proc(parser: Parser): Result[Import, ParserError] =
  discard parser.run(blankLines)
  let imp = ? parser.run(importLineSpec)
  ok(imp)
)


let getterSpec* = separated(identifierSpec, punctuationSpec("."), identifierSpec).map(
  "getter",
  proc(t: (Identifier, Identifier)): Getter = newGetter(t[0], t[1], t[0].loc))

# type literal
let literalInitializerSpec* = separated(argumentTypeSpec, ws1, literalSpec).map(
  "literal_initializer",
  proc(t: (ArgumentType, Literal)): LiteralInitializer =
    newLiteralInitializer(t[0], t[1], t[0].loc))

# ============================================================
# Specs for the body cluster
# ============================================================

# Forward-declared because expressions appear inside argument lists
# of function calls, creating a mutual recursion:
# expression -> functionCall -> argumentList -> expression
let expressionSpec* = newSpec[Expression]("expression")

# Forward declare statementListSpec for mutual recursion:
# match -> caseBlock -> statementList -> statementLine -> statement -> match
let statementListSpec* = newSpec[StatementList]("statement_list")

let argumentListSpec* = Spec[ArgumentList](
  name: "argument_list",
  parseFn: proc(parser: Parser): Result[ArgumentList, ParserError] =
  let loc = parser.loc
  let args = ? parser.run(contained("argument_list", "(",
    separatedBy(expressionSpec, commaWithSpacesSpec), ")"))
  ok(newArgumentList(args, loc))
)

let functionCallSpec* = triple(
    identifierSpec,
    prefixed(punctuationSpec("."), identifierSpec),
    prefixed(ws0, argumentListSpec)
  ).map("function_call",
    proc(t: (Identifier, Identifier, ArgumentList)): FunctionCall =
      newFunctionCall(t[0], t[1], t[2]))

let kwargSpec* = pair(
    identifierSpec,
    optional(prefixed(colonWithSpacesSpec, expressionSpec))
  ).map("keyword_argument",
    proc(t: (Identifier, Option[Expression])): KeywordArgument =
      # Shorthand: `Struct { x }` is sugar for `Struct { x: x }`. When
      # the `: expression` suffix is absent the value is synthesized as
      # a bare Variable of the same name; the shorthand identifier's
      # location carries through so diagnostics point at the source
      # token the user actually wrote.
      let expr = if t[1].isSome: t[1].get else: newExpression(t[0])
      newKeywordArgument(t[0], expr, t[0].loc))

let kwargListSpec* = Spec[KeywordArgumentList](
  name: "keyword_argument_list",
  parseFn: proc(parser: Parser): Result[KeywordArgumentList, ParserError] =
  let loc = parser.loc
  let args = ? parser.run(contained("keyword_argument_list", "{",
    separatedBy(kwargSpec, commaWithSpacesSpec), "}"))
  newKeywordArgumentList(args, loc)
)

# Type.Variant { fields } (bare — drives leave-as-is inference) or
# Type[Impls].Variant { fields } (explicit-impls — escape hatch when
# leave-as-is can't produce a fully-bound type). Both productions land
# on the same UnionRef shape carrying an impls seq; empty means bare.
let unionInitializerSpec* = triple(
    argumentTypeSpec,
    prefixed(punctuationSpec("."), identifierSpec),
    prefixed(ws0, kwargListSpec)
  ).map("union_initializer",
    proc(t: (ArgumentType, Identifier, KeywordArgumentList)): UnionInitializer =
      let unionRef = newUnionRef(t[0].root, t[0].impls, t[0].loc)
      newUnionInitializer(unionRef, t[1], t[2], t[0].loc))

# Either `Type { fields }` (bare) or `Type[Impls] { fields }` (explicit
# impls, used for phantom-typed structs whose module declares a requires
# block). Both productions land on the same StructRef shape carrying an
# impls seq; empty means bare.
let structInitializerSpec* = separated(argumentTypeSpec, ws0, kwargListSpec).map(
  "struct_initializer",
  proc(t: (ArgumentType, KeywordArgumentList)): StructInitializer =
    let structRef = newStructRef(t[0].root, t[0].impls, t[0].loc)
    newStructInitializer(structRef, t[1], t[0].loc))

let initializerSpec* = oneOf("initializer", [
  unionInitializerSpec.map("union",
    proc(v: UnionInitializer): Initializer = newInitializer(v)),
  structInitializerSpec.map("struct",
    proc(v: StructInitializer): Initializer = newInitializer(v)),
  literalInitializerSpec.map("literal",
    proc(v: LiteralInitializer): Initializer = newInitializer(v)),
])

expressionSpec.parseFn = oneOf("expression", [
  literalSpec.map("literal_expression",
    proc(v: Literal): Expression = newExpression(v)),
  initializerSpec.map("initializer_expression",
    proc(v: Initializer): Expression = newExpression(v)),
  functionCallSpec.map("fncall_expression",
    proc(v: FunctionCall): Expression = newExpression(v)),
  getterSpec.map("getter_expression",
    proc(v: Getter): Expression = newExpression(v)),
  identifierSpec.map("variable_expression",
    proc(v: Identifier): Expression = newExpression(v)),
]).parseFn

let assignmentSpec* = separated(identifierSpec, equalsSeparatorSpec, expressionSpec).map(
  "assignment",
  proc(t: (Identifier, Expression)): Assignment = newAssignment(t[0], t[1], t[0].loc))

let setterSpec* = separated(getterSpec, equalsSeparatorSpec, expressionSpec).map(
  "setter",
  proc(t: (Getter, Expression)): Setter = newSetter(t[0], t[1], t[0].loc))

let inlineStatementSpec* = oneOf("inline_statement", [
  setterSpec.map("mutation_statement",
    proc(v: Setter): Statement = newStatement(v)),
  assignmentSpec.map("assignment_statement",
    proc(v: Assignment): Statement = newStatement(v)),
  expressionSpec.map("expression_statement",
    proc(v: Expression): Statement = newStatement(v)),
])

let caseLineSpec = prefixed(pair(keywordSpec("case"), ws1),
  suffixed(casePatternSpec, pair(ws0, punctuationSpec(":"))))

let caseSpec* = blockSpec("case", caseLineSpec, statementListSpec,
  proc(h: CasePattern, b: StatementList): CaseBlock =
  newCaseBlock(h, b, h.loc))

# Match body: parses "match" keyword + subject + ":" + newline + caseBlocks
# Does NOT consume indentation — caller handles that
let matchSpec* = Spec[MatchExpression](
  name: "match_body",
  parseFn: proc(parser: Parser): Result[MatchExpression, ParserError] =
  let loc = ? parser.run(keywordSpec("match"))
  discard ? parser.run(ws1)
  # Match expressions cannot be the subject of another match expression.
  # expressionSpec intentionally excludes match (match is parsed separately
  # in statementLineSpec). This check guards against future changes that
  # might add match to expressionSpec.
  let subject = ? parser.run(expressionSpec)
  case subject.kind:
  of ekMatch:
    return err(newParserError(
      "match expression cannot be the subject of another match", loc))
  of ekLiteral, ekFnCall, ekGetter, ekInitializer, ekVariable: discard
  discard parser.run(ws0)
  discard ? parser.run(punctuationSpec(":"))
  discard ? parser.run(ignorableLineSpec)
  parser.level += 1
  let casesBody = atLeastOne(Spec[CaseBlock](
    name: "case_block_line",
    parseFn: proc(parser: Parser): Result[CaseBlock, ParserError] =
    discard parser.run(blankLines)
    let cb = ? parser.run(caseSpec)
    ok(cb)
  ))
  let casesResult = casesBody.parseFn(parser)
  parser.level -= 1
  if casesResult.isErr:
    casesResult.error.fatal = true
    return err(casesResult.error)
  ok(newMatchExpression(subject, casesResult.get, loc))
)

let statementLineSpec* = Spec[Statement](
  name: "statement_line",
  parseFn: proc(parser: Parser): Result[Statement, ParserError] =
  discard parser.run(blankLines)
  discard ? parser.run(indentationSpec)
  # Try match assignment: identifier = match ...:
  let maybeMatchAssign = parser.run(Spec[Statement](
    name: "match_assignment",
    parseFn: proc(parser: Parser): Result[Statement, ParserError] =
    let target = ? parser.run(identifierSpec)
    discard ? parser.run(equalsSeparatorSpec)
    let matchExpr = ? parser.run(matchSpec)
    ok(newStatement(newAssignment(target, newExpression(matchExpr), target.loc)))
  ))
  if maybeMatchAssign.isOk: return ok(maybeMatchAssign.get)
  # Try standalone match: match ...:
  let maybeMatch = parser.run(matchSpec)
  if maybeMatch.isOk:
    return ok(newStatement(newExpression(maybeMatch.get)))
  # Inline statements: statement + newline
  let statement = ? parser.run(inlineStatementSpec)
  discard ? parser.run(ignorableLineSpec)
  ok(statement)
)

statementListSpec.parseFn = atLeastOne(statementLineSpec).map("statement_list",
  proc(stmts: seq[Statement]): StatementList = newStatementList(stmts)).parseFn
# TODO(post-analysis-expander): re-wire expansion after the analyzer once the
# post-analysis expander lands (see plans/plan_post_analysis_expansion.md).
# The expand* procs above (lines 540-748) are kept as reference for that move.


let functionDefSpec* = Spec[FunctionDef](
  name: "function_definition",
  parseFn: proc(parser: Parser): Result[FunctionDef, ParserError] =
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
)

# Function definition line: indentation + function signature + newline
# Used by genericSpec via functionDefListSpec.
let functionDefLineSpec* = indentedLine(functionDefSpec)

let functionDefListSpec* = atLeastOne(functionDefLineSpec)

let userFunctionSpec = decoratedBlockSpec("user_function", functionDefSpec,
  statementListSpec,
  proc(d: seq[Decorator], h: FunctionDef, b: StatementList): UserFunction =
  newUserFunction(d, h, b))

# @extern("symbol")
# public func name(args): ReturnType
let externFunctionSpec = Spec[ExternFunction](
  name: "extern_function",
  parseFn: proc(parser: Parser): Result[ExternFunction, ParserError] =
  discard ? parser.run(indentationSpec)
  discard ? parser.run(punctuationSpec("@"))
  discard ? parser.run(keywordSpec("extern"))
  discard parser.run(ws0)
  let loc = parser.loc
  let symbol = ? parser.run(contained("extern_symbol", "(", stringLiteralSpec, ")"))
  discard ? parser.run(ignorableLineSpec)
  discard ? parser.run(indentationSpec)
  let def = ? parser.run(functionDefSpec)
  discard ? parser.run(ignorableLineSpec)
  ok(newExternFunction(symbol.value, def, loc))
)

# Each function block skips leading ignorable lines then parses a function.
# any() backtracks the ignorable line consumption if no function follows.
let functionSpec = Spec[Function](
  name: "function_block",
  parseFn: proc(parser: Parser): Result[Function, ParserError] =
  discard parser.run(blankLines)
  let f = parser.run(externFunctionSpec)
  if f.isOk: return ok(newFunction(f.get))
  let u = ? parser.run(userFunctionSpec)
  ok(newFunction(u))
)

let functionListSpec* = any(functionSpec).map("function_list",
  proc(fns: seq[Function]): Result[FunctionList, ParserError] = newFunctionList(fns))


# struct: field+ (field is identifier ":" argumentType)
let structHeaderSpec = suffixed(keywordSpec("struct"),
  pair(ws0, punctuationSpec(":")))

# Each field line: (blank lines) + indentation + argumentDef + newline
let argumentDefLineSpec = prefixed(blankLines, indentedLine(argumentDefSpec))

let structSpec* = blockSpec("struct", structHeaderSpec,
  atLeastOne(argumentDefLineSpec),
  proc(h: Location, b: seq[ArgumentDef]): Result[StructDef, ParserError] =
  newStructDef(b, h))

# union: variant+ (variant is identifier space* "{" (argDef, argDef)* "}")
# Braces are required — empty variants must be written `Timeout { }`. This
# mirrors the case-pattern side (`case Timeout { }:`) so the two shapes
# stay visually consistent and there's no bare `Timeout` form to confuse
# with a variable-binding case pattern.
let variantDefLineSpec = Spec[VariantDef](
  name: "variant_definition_line",
  parseFn: proc(parser: Parser): Result[VariantDef, ParserError] =
  discard parser.run(blankLines)
  discard ? parser.run(indentationSpec)
  let name = ? parser.run(identifierSpec)
  discard parser.run(ws0)
  let fields = ? parser.run(contained("variant_fields", "{",
    separatedBy(argumentDefSpec, commaWithSpacesSpec), "}"))
  discard ? parser.run(ignorableLineSpec)
  newVariantDef(name, fields, name.loc)
)

let unionHeaderSpec = suffixed(keywordSpec("union"),
  pair(ws0, punctuationSpec(":")))

let unionSpec* = blockSpec("union", unionHeaderSpec,
  atLeastOne(variantDefLineSpec),
  proc(h: Location, b: seq[VariantDef]): Result[UnionDef, ParserError] =
  newUnionDef(b, h))

let dataSpec* = oneOf("data_block", [
  literalTypeSpec.map("literal_data",
    proc(v: LiteralDef): DataDef = newDataDef(v)),
  structSpec.map("struct_data",
    proc(v: StructDef): DataDef = newDataDef(v)),
  unionSpec.map("union_data",
    proc(v: UnionDef): DataDef = newDataDef(v)),
])

let genericHeaderSpec = Spec[GenericHeader](
  name: "generic_header",
  parseFn: proc(parser: Parser): Result[GenericHeader, ParserError] =
  let public = ? parser.run(presence(keywordSpec("public")))
  if public: discard ? parser.run(ws1)
  let loc = ? parser.run(keywordSpec("generic"))
  discard ? parser.run(ws1)
  let nameIdent = ? parser.run(identifierSpec)
  discard parser.run(ws0)
  discard ? parser.run(punctuationSpec(":"))
  ok((public, nameIdent, loc))
)

let genericSpec* = blockSpec("generic", genericHeaderSpec,
  functionDefListSpec,
  proc(h: GenericHeader, b: seq[FunctionDef]): Result[Generic, ParserError] =
  newGeneric(@[], h.public, h.name, b, h.loc))

# requires(Generic, Generic, ...)
let requiresSpec* = indentedLine(pair(keywordSpec("requires"),
    prefixed(ws0, contained("requires_generics", "(",
      separatedBy(identifierSpec, commaWithSpacesSpec), ")")))).map(
  "requires",
  proc(t: (Location, seq[Identifier])): Requires = newRequires(t[1], t[0]))


let moduleHeaderSpec = Spec[ModuleHeader](
  name: "module_header",
  parseFn: proc(parser: Parser): Result[ModuleHeader, ParserError] =
  let public = ? parser.run(presence(keywordSpec("public")))
  if public: discard ? parser.run(ws1)

  let loc = ? parser.run(keywordSpec("module"))
  discard ? parser.run(ws1)
  let nameIdent = ? parser.run(identifierSpec)
  discard parser.run(ws0)
  discard ? parser.run(punctuationSpec(":"))
  ok((public, nameIdent, loc))
)


let moduleBodySpec = Spec[ModuleBody](
  name: "module_body",
  parseFn: proc(parser: Parser): Result[ModuleBody, ParserError] =
  discard parser.run(blankLines)
  let requires = ? parser.run(optional(requiresSpec))
  discard parser.run(blankLines)
  let data = ? parser.run(optional(dataSpec))
  let funcList = ? parser.run(functionListSpec)
  ok((requires, data, funcList))
)

let moduleSpec* = decoratedBlockSpec("module", moduleHeaderSpec, moduleBodySpec,
  proc(d: seq[Decorator], h: ModuleHeader, b: ModuleBody): Result[Module, ParserError] =
  newModule(d, h.public, h.name, b.requires, b.data, b.funcList, h.loc))



let typeSpec = oneOf("type_block", [
  moduleSpec.map("module_item",
    proc(v: Module): Type = newType(v)),
  genericSpec.map("generic_item",
    proc(v: Generic): Type = newType(v)),
])

let definedTypeSpec = prefixed(blankLines, typeSpec)

# aslFile: import* (module | generic)*
#
# Parameterized by `vendorRoots` so the parseFn can pass it through
# to `newAslFile`. Each call to `aslFileSpec(roots)` returns a fresh
# Spec whose parseFn captures `roots` in its closure. The default
# closure shape (a `let` Spec) doesn't work here because the
# constructor needs runtime access to the vendor table.
proc aslFileSpec*(vendorRoots: VendorRoots): Spec[File] =
  Spec[File](
    name: "asl_file",
    parseFn: proc(parser: Parser): Result[File, ParserError] =
      let imports = ? parser.run(any(importSpec))
      let items = ? parser.run(atLeastOne(definedTypeSpec))
      discard parser.run(blankLines)
      # Force a parse attempt to get a specific error message
      if not parser.done(): discard ? parser.run(typeSpec)
      newAslFile(parser.filepath, imports, items, vendorRoots)
  )

# aslrFile: (module | generic)*  — no imports section. Aslr files
# are the runtime interface; they cannot reference other files.
let aslrFileSpec* = Spec[File](
  name: "aslr_file",
  parseFn: proc(parser: Parser): Result[File, ParserError] =
  let items = ? parser.run(atLeastOne(definedTypeSpec))
  discard parser.run(blankLines)
  # Force a parse attempt to get a specific error message
  if not parser.done(): discard ? parser.run(typeSpec)
  newAslrFile(parser.filepath, items, @[])
)

proc fileSpec*(ext: string, vendorRoots: VendorRoots): Spec[File] =
  if ext == ".asl": aslFileSpec(vendorRoots)
  else: aslrFileSpec

proc validate(filepath: string): Result[string, string] =
  let (_, _, ext) = filepath.splitFile()
  if ext in @[".aslr", ".asl"]: ok(ext)
  else: err(fmt"{filepath}: unrecognized file extension '{ext}' — expected '.asl' or '.aslr'")

proc parse*(parser: Parser, vendorRoots: VendorRoots): Result[
    File, string] =
  let ext = ? parser.filepath.validate()
  let maybeFile = parser.run(ext.fileSpec(vendorRoots))
  if maybeFile.isOk: ok(maybeFile.get)
  else: err(fmt"{maybeFile.error}")

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

proc parseFile(filepath: string, indentWidth: uint32,
    dumpTokens: bool, vendorRoots: VendorRoots): Result[File, string] =
  let source = ? readFileSafe(filepath)
  let tokens = ? tokenize(source, filepath)
  if dumpTokens: echo filepath.dump(tokens)
  let parser = newParser(filepath, indentWidth, tokens)
  parser.parse(vendorRoots)

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
      parseFile(path, indentWidth, dumpTokens, vendorRoots),
    importPaths)

  # Topological sort with cycle detection (leaves first, root last)
  let sortedPaths = ? topoSort(rootPath, proc(path: string): seq[string] =
    if parsed.hasKey(path): importPaths(parsed[path])
    else: @[])

  var files: seq[File]
  for path in sortedPaths:
    files.add(parsed[path])
  ok(newApp(files))
