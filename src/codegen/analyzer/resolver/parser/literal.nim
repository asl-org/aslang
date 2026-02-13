import results

import core

# =============================================================================
# UnsignedIntegerLiteral
# =============================================================================

type UnsignedIntegerLiteral = ref object of RootObj
  value: string
  location: Location

proc new_unsigned_integer(digits: Token): UnsignedIntegerLiteral =
  UnsignedIntegerLiteral(value: digits.value, location: digits.location)

proc asl(unsigned_integer: UnsignedIntegerLiteral): string =
  unsigned_integer.value

proc unsigned_integer_spec(parser: Parser): Result[UnsignedIntegerLiteral,
    core.Error] =
  # TODO: Support underscore separated values as integers as well.
  let int_value_token = ? parser.token_kind_spec(TK_DIGITS)
  ok(new_unsigned_integer(int_value_token))

# =============================================================================
# SignedIntegerLiteral
# =============================================================================

type
  SignedIntegerLiteralKind = enum
    SIK_POSITIVE, SIK_NEGATIVE
  SignedIntegerLiteral = ref object of RootObj
    kind: SignedIntegerLiteralKind
    value: string
    location: Location

proc new_signed_integer(sign: Token, unsigned_integer: UnsignedIntegerLiteral): Result[
    SignedIntegerLiteral, core.Error] =
  case sign.kind:
  of TK_PLUS:
    ok(SignedIntegerLiteral(kind: SIK_POSITIVE, value: unsigned_integer.value,
        location: sign.location))
  of TK_MINUS:
    ok(SignedIntegerLiteral(kind: SIK_NEGATIVE, value: unsigned_integer.value,
        location: sign.location))
  else:
    return err(err_parser_expected_sign(sign.location, sign.value))

proc asl(signed_integer: SignedIntegerLiteral): string =
  let sign =
    case signed_integer.kind:
    of SIK_POSITIVE: ""
    of SIK_NEGATIVE: "-"
  return sign & signed_integer.value

proc sign_spec(parser: Parser): Result[Token, core.Error] =
  parser.expect_one_of([plus_spec, minus_spec])

proc signed_integer_spec(parser: Parser): Result[SignedIntegerLiteral,
    core.Error] =
  var sign = ? parser.expect(sign_spec)
  let unsigned_intvalue = ? parser.expect(unsigned_integer_spec)
  new_signed_integer(sign, unsigned_intvalue)

# =============================================================================
# IntegerLiteral
# =============================================================================

type
  IntegerLiteralKind* = enum
    ILK_SIGNED, ILK_UNSIGNED
  IntegerLiteral* = ref object of RootObj
    case kind: IntegerLiteralKind
    of ILK_SIGNED: signed: SignedIntegerLiteral
    of ILK_UNSIGNED: unsigned: UnsignedIntegerLiteral

proc new_integer_literal(signed: SignedIntegerLiteral): IntegerLiteral =
  IntegerLiteral(kind: ILK_SIGNED, signed: signed)

proc new_integer_literal(unsigned: UnsignedIntegerLiteral): IntegerLiteral =
  IntegerLiteral(kind: ILK_UNSIGNED, unsigned: unsigned)

proc location*(integer: IntegerLiteral): Location =
  case integer.kind:
  of ILK_SIGNED: integer.signed.location
  of ILK_UNSIGNED: integer.unsigned.location

proc kind*(integer: IntegerLiteral): IntegerLiteralKind = integer.kind

proc signed*(integer: IntegerLiteral): SignedIntegerLiteral =
  do_assert integer.kind == ILK_SIGNED, "expected signed integer but found unsigned"
  integer.signed

proc unsigned*(integer: IntegerLiteral): UnsignedIntegerLiteral =
  do_assert integer.kind == ILK_UNSIGNED, "expected unsigned integer but found signed"
  integer.unsigned

proc asl*(integer: IntegerLiteral): string =
  case integer.kind:
  of ILK_SIGNED: integer.signed.asl
  of ILK_UNSIGNED: integer.unsigned.asl

proc integer_spec(parser: Parser): Result[IntegerLiteral, core.Error] =
  var errors: seq[core.Error]

  let maybe_unsigned_integer = parser.expect(unsigned_integer_spec)
  if maybe_unsigned_integer.is_ok:
    return ok(new_integer_literal(maybe_unsigned_integer.get))
  else:
    errors.add(maybe_unsigned_integer.error)

  let maybe_signed_integer = parser.expect(signed_integer_spec)
  if maybe_signed_integer.is_ok:
    return ok(new_integer_literal(maybe_signed_integer.get))
  else:
    errors.add(maybe_signed_integer.error)

  err(errors.max())

# =============================================================================
# FloatLiteral
# =============================================================================

type FloatLiteral* = ref object of RootObj
  value: string
  location: Location

proc new_float_literal(first: IntegerLiteral,
    second: UnsignedIntegerLiteral): FloatLiteral =
  let value = first.asl & "." & second.asl
  FloatLiteral(value: value, location: first.location)

proc location*(float_literal: FloatLiteral): Location =
  float_literal.location

proc asl*(float_literal: FloatLiteral): string =
  float_literal.value

proc float_spec(parser: Parser): Result[FloatLiteral, core.Error] =
  # TODO: Improve float parsing to support scientific notation as well.
  let first = ? parser.expect(integer_spec)
  discard ? parser.expect(dot_spec)
  let second = ? parser.expect(unsigned_integer_spec)
  ok(new_float_literal(first, second))

# =============================================================================
# StringLiteral
# =============================================================================

type StringLiteral* = ref object of RootObj
  value: string
  location: Location

proc new_string_literal*(value: string, location: Location): StringLiteral =
  StringLiteral(value: value, location: location)

proc location*(string_literal: StringLiteral): Location =
  string_literal.location

proc asl*(string_literal: StringLiteral): string =
  string_literal.value

proc string_spec(parser: Parser): Result[StringLiteral, core.Error] =
  let token = ? parser.token_kind_spec(TK_STRING)
  ok(new_string_literal(token.value, token.location))

# =============================================================================
# Literal (variant type)
# =============================================================================

type
  LiteralKind* = enum
    LK_INTEGER, LK_FLOAT, LK_STRING
  Literal* = ref object of RootObj
    case kind: LiteralKind
    of LK_INTEGER: integer_literal: IntegerLiteral
    of LK_FLOAT: float_literal: FloatLiteral
    of LK_STRING: string_literal: StringLiteral

proc new_literal*(integer_literal: IntegerLiteral): Literal =
  Literal(kind: LK_INTEGER, integer_literal: integer_literal)

proc new_literal*(float_literal: FloatLiteral): Literal =
  Literal(kind: LK_FLOAT, float_literal: float_literal)

proc new_literal*(string_literal: StringLiteral): Literal =
  Literal(kind: LK_STRING, string_literal: string_literal)

proc location*(literal: Literal): Location =
  case literal.kind:
  of LK_INTEGER: literal.integer_literal.location
  of LK_FLOAT: literal.float_literal.location
  of LK_STRING: literal.string_literal.location

proc kind*(literal: Literal): LiteralKind = literal.kind

proc integer_literal*(literal: Literal): IntegerLiteral =
  do_assert literal.kind == LK_INTEGER, "expected integer literal"
  literal.integer_literal

proc float_literal*(literal: Literal): FloatLiteral =
  do_assert literal.kind == LK_FLOAT, "expected float literal"
  literal.float_literal

proc string_literal*(literal: Literal): StringLiteral =
  do_assert literal.kind == LK_STRING, "expected string literal"
  literal.string_literal

proc asl*(literal: Literal): string =
  case literal.kind:
  of LK_INTEGER: literal.integer_literal.asl
  of LK_FLOAT: literal.float_literal.asl
  of LK_STRING: literal.string_literal.asl

proc literal_spec*(parser: Parser): Result[Literal, core.Error] =
  var errors: seq[core.Error]

  let maybe_integer = parser.expect(integer_spec)
  if maybe_integer.is_ok: return ok(new_literal(maybe_integer.get))
  else: errors.add(maybe_integer.error)

  let maybe_float = parser.expect(float_spec)
  if maybe_float.is_ok: return ok(new_literal(maybe_float.get))
  else: errors.add(maybe_float.error)

  let maybe_string = parser.expect(string_spec)
  if maybe_string.is_ok: return ok(new_literal(maybe_string.get))
  else: errors.add(maybe_string.error)

  err(errors.max())
