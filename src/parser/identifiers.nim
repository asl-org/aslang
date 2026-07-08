import strformat, strutils, results, hashes

import ./tokenizer
import ./combinators

# ============================================================
# Identifier
# ============================================================

type Identifier* = ref object
  value: string
  loc: Location

proc newIdentifier*(value: string, loc: Location): Result[Identifier, ParserError] =
  if value.len > 256:
    err(newParserError(fmt"identifier can be of max length 256", loc))
  elif value.startsWith("__asl"):
    err(newParserError(fmt"identifier can not start with '__asl'", loc))
  else:
    ok(Identifier(value: value, loc: loc))

proc value*(id: Identifier): string = id.value
proc loc*(id: Identifier): Location = id.loc

proc hash*(id: Identifier): Hash = hash(id.value)
proc `==`*(id: Identifier, other: Identifier): bool = hash(id) == hash(other)

proc asl*(identifier: Identifier): string = identifier.value

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

proc indentedLine*[T](inner: Spec[T]): Spec[T] =
  ## Parse `indentation inner ignorable_line`; return only inner.
  ## The grammar-natural shape for "one item on its own indented
  ## line" — decorators, field definitions, function definitions,
  ## etc. Prepend `blankLines` at the call site when the line may
  ## be preceded by blank/comment lines.
  prefixed(indentationSpec, suffixed(inner, ignorableLineSpec))

# ============================================================
# Decorator
# ============================================================

type Decorator* = ref object
  name: Identifier

proc newDecorator*(name: Identifier): Decorator =
  Decorator(name: name)

proc asl*(decorator: Decorator): string =
  fmt"@{asl(decorator.name)}"

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
