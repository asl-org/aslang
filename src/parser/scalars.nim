## Scalar literal leaves: the concrete string / integer / float literal
## AST nodes and their token specs. The `Literal` umbrella that unifies
## them (plus the numeric validation logic and the literal def /
## initializer) lives in literals.nim, which re-exports this module.

import results, strformat

import parser

# ============================================================
# StringLiteral
# ============================================================

type StringLiteral* = ref object
  value: string
  loc: Location

proc newStringLiteral*(value: string, loc: Location): StringLiteral =
  StringLiteral(value: value, loc: loc)

proc newStringLiteral(token: Token): StringLiteral =
  newStringLiteral(token.value, token.loc)

proc loc*(strLit: StringLiteral): Location = strLit.loc
proc content*(strLit: StringLiteral): string = strLit.value[1..^2]
proc asl*(strLit: StringLiteral): string = "\"" & strLit.content & "\""

# The tokenizer scans a whole string literal into one `tkString` token
# whose value is the raw `"…"` slice (quotes + verbatim escapes);
# newStringLiteral keeps the raw value and strips the quotes on access.
let stringLiteralSpec* = newSpec[StringLiteral]("string", tkString, newStringLiteral)

# ============================================================
# Integer literals
# ============================================================

type UnsignedIntegerLiteral* = ref object
  value: string
  loc: Location

proc newUnsignedIntegerLiteral*(value: string,
    loc: Location): UnsignedIntegerLiteral =
  UnsignedIntegerLiteral(value: value, loc: loc)

proc asl(unsigned: UnsignedIntegerLiteral): string = unsigned.value

type SignedIntegerLiteral* = ref object
  sign: string
  value: UnsignedIntegerLiteral
  loc: Location

proc newSignedIntegerLiteral*(sign: string, value: UnsignedIntegerLiteral,
    loc: Location): SignedIntegerLiteral =
  SignedIntegerLiteral(sign: sign, value: value, loc: loc)


proc asl*(signed: SignedIntegerLiteral): string =
  fmt"{signed.sign}{asl(signed.value)}"

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

proc newIntegerLiteral*(value: string, loc: Location): IntegerLiteral =
  # `value` is the raw tokenized `(+|-)?digit+`; a leading sign makes it
  # signed, otherwise it is an unsigned magnitude.
  if value.len > 0 and (value[0] == '+' or value[0] == '-'):
    let magnitude = newUnsignedIntegerLiteral(value[1 .. ^1], loc)
    newIntegerLiteral(newSignedIntegerLiteral($value[0], magnitude, loc))
  else:
    newIntegerLiteral(newUnsignedIntegerLiteral(value, loc))

proc newIntegerLiteral(token: Token): IntegerLiteral =
  newIntegerLiteral(token.value, token.loc)

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

# The tokenizer scans `(+|-)?digit+` into one tkInteger token;
# newIntegerLiteral splits its optional leading sign into signed/unsigned.
let integerLiteralSpec* = newSpec[IntegerLiteral]("integer", tkInteger, newIntegerLiteral)

# ============================================================
# FloatLiteral
# ============================================================

type FloatLiteral* = ref object
  value: string
  loc: Location

proc newFloatLiteral*(value: string, loc: Location): FloatLiteral =
  FloatLiteral(value: value, loc: loc)

proc newFloatLiteral(token: Token): FloatLiteral =
  newFloatLiteral(token.value, token.loc)

proc loc*(floatLit: FloatLiteral): Location = floatLit.loc
proc asl*(floatLit: FloatLiteral): string = floatLit.value

# Every float form is a single tkFloat token: the tokenizer scans the
# numeric form `(+|-)?digit+(.digit+)?((e|E)(+|-)?digit+)?` and the special
# IEEE-754 values `nan` / `inf` / `+inf` / `-inf` (the sign folds into the
# token so downstream `analyzeFloatLiteral` can tell `+inf` from `-inf`).
# So one consumer covers them all — no per-form alternation.
let floatLiteralSpec* = newSpec("float", tkFloat, newFloatLiteral)
