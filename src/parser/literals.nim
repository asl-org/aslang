import strformat, results

import tokenizer
import combinators
import helpers
import identifiers
import strings
import numbers

# ============================================================
# Literal (umbrella over string / integer / float)
# ============================================================

type
  LiteralKind* = enum
    lkString, lkInteger, lkFloat
  Literal* = ref object
    case kind: LiteralKind
    of lkString: strLit: StringLiteral
    of lkInteger: intLit: IntegerLiteral
    of lkFloat: floatLit: FloatLiteral

proc newLiteral*(strLit: StringLiteral): Literal =
  Literal(kind: lkString, strLit: strLit)

proc newLiteral*(intLit: IntegerLiteral): Literal =
  Literal(kind: lkInteger, intLit: intLit)

proc newLiteral*(floatLit: FloatLiteral): Literal =
  Literal(kind: lkFloat, floatLit: floatLit)

proc kind*(l: Literal): LiteralKind = l.kind

proc strLit*(l: Literal): StringLiteral =
  assert l.kind == lkString,
    fmt"Literal.strLit accessed but kind is {l.kind}"
  l.strLit

proc intLit*(l: Literal): IntegerLiteral =
  assert l.kind == lkInteger,
    fmt"Literal.intLit accessed but kind is {l.kind}"
  l.intLit

proc floatLit*(l: Literal): FloatLiteral =
  assert l.kind == lkFloat,
    fmt"Literal.floatLit accessed but kind is {l.kind}"
  l.floatLit

proc loc*(literal: Literal): Location =
  case literal.kind:
  of lkString: literal.strLit.loc
  of lkInteger: literal.intLit.loc
  of lkFloat: literal.floatLit.loc

proc asl*(literal: Literal): string =
  case literal.kind:
  of lkString: asl(literal.strLit)
  of lkInteger: asl(literal.intLit)
  of lkFloat: asl(literal.floatLit)

let literalSpec* = oneOf("literal", [
  stringLiteralSpec.map("string_literal",
    proc(v: StringLiteral): Literal = newLiteral(v)),
  floatLiteralSpec.map("float_literal",
    proc(v: FloatLiteral): Literal = newLiteral(v)),
  integerLiteralSpec.map("integer_literal",
    proc(v: IntegerLiteral): Literal = newLiteral(v)),
])

# ============================================================
# LiteralType (data block: `literal: "..."`)
# ============================================================

type LiteralType* = ref object
  value: StringLiteral
  loc: Location

proc newLiteralType*(value: StringLiteral, loc: Location): LiteralType =
  LiteralType(value: value, loc: loc)

proc content*(literalType: LiteralType): string = literalType.value.content
proc loc*(literalType: LiteralType): Location = literalType.loc

proc asl*(l: LiteralType): seq[string] =
  @[fmt"literal: {asl(l.value)}"]

let literalTypeSpec* = Spec[LiteralType](
  name: "literal_type",
  parseFn: proc(parser: Parser): Result[LiteralType, ParserError] =
  discard ? parser.run(indentationSpec)
  let literalKeywordLoc = ? parser.run(keywordSpec("literal"))
  discard ? parser.run(colonWithSpacesSpec)
  let literalType = ? parser.run(stringLiteralSpec)
  ok(newLiteralType(literalType, literalKeywordLoc))
)
