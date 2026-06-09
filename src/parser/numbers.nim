import strformat, results

import tokenizer
import combinators
import helpers

# ============================================================
# Integer literals
# ============================================================

type UnsignedIntegerLiteral* = ref object
  value: string
  loc: Location

proc newUnsignedIntegerLiteral*(value: string,
    loc: Location): UnsignedIntegerLiteral =
  UnsignedIntegerLiteral(value: value, loc: loc)

proc value*(literal: UnsignedIntegerLiteral): string = literal.value
proc loc*(uil: UnsignedIntegerLiteral): Location = uil.loc
proc asl(unsigned: UnsignedIntegerLiteral): string = unsigned.value

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

type SignedIntegerLiteral* = ref object
  sign: string
  value: UnsignedIntegerLiteral
  loc: Location

proc newSignedIntegerLiteral*(sign: string, value: UnsignedIntegerLiteral,
    loc: Location): SignedIntegerLiteral =
  SignedIntegerLiteral(sign: sign, value: value, loc: loc)

proc loc*(sil: SignedIntegerLiteral): Location = sil.loc

proc asl*(signed: SignedIntegerLiteral): string =
  fmt"{signed.sign}{asl(signed.value)}"

# (+ | -) digit+
let signedIntegerLiteralSpec* = Spec[SignedIntegerLiteral](
  name: "signed_integer_literal",
  parseFn: proc(parser: Parser): Result[SignedIntegerLiteral, ParserError] =
  let signToken = ? parser.run(oneOf("sign", [
    punctuationSpec("+"),
    punctuationSpec("-"),
  ]))
  let uint = ? parser.run(unsignedIntegerLiteralSpec)
  ok(newSignedIntegerLiteral(signToken.value, uint, signToken.loc))
)

type
  IntegerLiteralKind* = enum
    ilkSigned, ilkUnsigned
  IntegerLiteral* = ref object
    case kind: IntegerLiteralKind
    of ilkSigned: signed: SignedIntegerLiteral
    of ilkUnsigned: unsigned: UnsignedIntegerLiteral

proc newIntegerLiteral*(signed: SignedIntegerLiteral): IntegerLiteral =
  IntegerLiteral(kind: ilkSigned, signed: signed)

proc newIntegerLiteral*(unsigned: UnsignedIntegerLiteral): IntegerLiteral =
  IntegerLiteral(kind: ilkUnsigned, unsigned: unsigned)

proc kind*(il: IntegerLiteral): IntegerLiteralKind = il.kind

proc signed*(il: IntegerLiteral): SignedIntegerLiteral =
  assert il.kind == ilkSigned,
    fmt"IntegerLiteral.signed accessed but kind is {il.kind}"
  il.signed

proc unsigned*(il: IntegerLiteral): UnsignedIntegerLiteral =
  assert il.kind == ilkUnsigned,
    fmt"IntegerLiteral.unsigned accessed but kind is {il.kind}"
  il.unsigned

proc loc*(intLit: IntegerLiteral): Location =
  case intLit.kind:
  of ilkSigned: intLit.signed.loc
  of ilkUnsigned: intLit.unsigned.loc

proc asl*(intLit: IntegerLiteral): string =
  case intLit.kind:
  of ilkSigned: asl(intLit.signed)
  of ilkUnsigned: asl(intLit.unsigned)

let integerLiteralSpec* = oneOf("integer_literal", [
  signedIntegerLiteralSpec.map("signed_int",
    proc(v: SignedIntegerLiteral): IntegerLiteral = newIntegerLiteral(v)),
  unsignedIntegerLiteralSpec.map("unsigned_int",
    proc(v: UnsignedIntegerLiteral): IntegerLiteral = newIntegerLiteral(v)),
])

# ============================================================
# FloatLiteral
# ============================================================

type FloatLiteral* = ref object
  value: string
  loc: Location

proc newFloatLiteral*(value: string, loc: Location): FloatLiteral =
  FloatLiteral(value: value, loc: loc)

proc loc*(floatLit: FloatLiteral): Location = floatLit.loc
proc asl*(floatLit: FloatLiteral): string = floatLit.value

# (+|-)? digit+ ("." digit+)? ((e|E) (+|-)? digit+)?
# Must have either decimal part or exponent to distinguish from integer
let floatLiteralSpec* = Spec[FloatLiteral](
  name: "float_literal",
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
