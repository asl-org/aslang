import strformat, strutils, results

import ./tokenizer
import ./combinators
import ./identifiers

# ============================================================
# StringContent (internal — one character of a string literal)
# ============================================================

type StringContent* = ref object
  content: string
  loc: Location

proc newStringContent*(content: string,
    loc: Location): StringContent =
  StringContent(content: content, loc: loc)

proc content*(sc: StringContent): string = sc.content

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

# ============================================================
# StringLiteral
# ============================================================

type StringLiteral* = ref object
  content: string
  loc: Location

proc newStringLiteral*(content: string, loc: Location): StringLiteral =
  StringLiteral(content: content, loc: loc)

proc loc*(strLit: StringLiteral): Location = strLit.loc
proc value*(strLit: StringLiteral): string = strLit.content
proc content*(strLit: StringLiteral): string = strLit.content
proc asl*(strLit: StringLiteral): string = fmt"""{strLit.content}"""

let stringLiteralSpec* = Spec[StringLiteral](
  name: "string_literal",
  parseFn: proc(parser: Parser): Result[StringLiteral, ParserError] =
  let openQuote = ? parser.run(doubleQuoteSpec)
  let chars = ? parser.run(any(stringContentSpec))
  var content: string; for ch in chars: content.add(ch.content)
  discard ? parser.run(doubleQuoteSpec)
  ok(newStringLiteral(content, openQuote.loc))
)

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
let signSpec = oneOf("sign", [punctuationSpec("+"), punctuationSpec("-")])
let signedIntegerLiteralSpec* = pair(signSpec, unsignedIntegerLiteralSpec).map(
  "signed_integer_literal",
  proc(t: (Token, UnsignedIntegerLiteral)): SignedIntegerLiteral =
    newSignedIntegerLiteral(t[0].value, t[1], t[0].loc))

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
# LiteralDef (data block: `literal: "..."`)
# ============================================================

type LiteralDef* = ref object
  value: StringLiteral
  loc: Location

proc newLiteralDef*(value: StringLiteral, loc: Location): LiteralDef =
  LiteralDef(value: value, loc: loc)

proc content*(literalType: LiteralDef): string = literalType.value.content
proc loc*(literalType: LiteralDef): Location = literalType.loc

proc asl*(l: LiteralDef, level: int, indentWidth: uint32): seq[string] =
  let indent = " ".repeat(level * indentWidth.int)
  @[fmt"{indent}literal: {asl(l.value)}"]

let literalTypeSpec* = pair(prefixed(indentationSpec, keywordSpec("literal")),
    prefixed(colonWithSpacesSpec, stringLiteralSpec)).map(
  "literal_type",
  proc(t: (Location, StringLiteral)): LiteralDef = newLiteralDef(t[1], t[0]))
