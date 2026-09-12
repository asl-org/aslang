## Getter — a `source.property` field read. A non-recursive leaf of the
## expression grammar (both fields are plain identifiers), used by the
## setter target and the getter arm of InlineExpression in statement.nim.

import strformat, results

import ../tokenizer/main as tokenizer
import parser
import error

import identifiers

# ============================================================
# Getter
# ============================================================

type Getter* = ref object
  source: Identifier
  property: Identifier
  loc: Location

proc newGetter*(source: Identifier, property: Identifier, loc: Location): Getter =
  Getter(source: source, property: property, loc: loc)

proc source*(g: Getter): Identifier = g.source
proc property*(g: Getter): Identifier = g.property
proc loc*(g: Getter): Location = g.loc

proc asl*(getter: Getter): string =
  fmt"{asl(getter.source)}.{asl(getter.property)}"

proc getterConsumer(parser: Parser): Result[Getter, ParserError] =
  let target = ? parser.expect(identifierSpec)
  discard ? parser.expect(".")
  let field = ? parser.expect(identifierSpec)
  ok(newGetter(target, field, target.loc))

let getterSpec* = newSpec[Getter]("getter", getterConsumer)
