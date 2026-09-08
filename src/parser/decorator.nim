import strformat, results

import parser
import error

import identifiers

# ============================================================
# Decorator
# ============================================================

type Decorator* = ref object
  name: Identifier

proc newDecorator*(name: Identifier): Decorator =
  Decorator(name: name)

proc asl*(decorator: Decorator): string =
  fmt"@{decorator.name.asl}"

proc decoratorConsumer(parser: Parser): Result[Decorator, ParserError] =
  discard ? parser.expect(indentationSpec)
  discard ? parser.expect("@")
  let ident = ? parser.expect(identifierSpec)
  discard ? parser.expect(emptyLineSpec)
  ok(newDecorator(ident))

let decoratorSpec* = newSpec("decorator", decoratorConsumer)