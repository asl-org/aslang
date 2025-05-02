import hashes, results, strformat, strutils

import "../location"

type
  NumericLiteralKind* = enum
    NLK_INTEGER, NLK_FLOAT
  NumericLiteral* = ref object of RootObj
    location: Location
    case kind: NumericLiteralKind
    of NLK_INTEGER: integer_value: string
    of NLK_FLOAT: float_value: string

proc kind*(native_literal: NumericLiteral): NumericLiteralKind = native_literal.kind

proc new_native_int_literal*(value: string,
    location: Location): NumericLiteral =
  NumericLiteral(kind: NLK_INTEGER, integer_value: value, location: location)

proc new_native_float_literal*(value: string,
    location: Location): NumericLiteral =
  NumericLiteral(kind: NLK_FLOAT, float_value: value, location: location)

proc `$`*(literal: NumericLiteral): string =
  case literal.kind:
    of NLK_INTEGER: literal.integer_value
    of NLK_FLOAT: literal.float_value

proc hash*(literal: NumericLiteral): Hash =
  let sub_hash =
    case literal.kind:
    of NLK_INTEGER: hash(literal.integer_value)
    of NLK_FLOAT: hash(literal.float_value)

  hash(literal.kind) !& sub_hash

proc safe_parse_number[T](input: string): Result[string, string] =
  when T is SomeSignedInt:
    try:
      let parsed = input.parseBiggestInt()
      if parsed >= T.low.int and parsed <= T.high.int:
        return ok($(T(parsed)))
      return err(fmt"Expected value between {T.low.int} and {T.high.int} but found {input}")
    except ValueError:
      return err(fmt"Failed to parse input: {input}")
  elif T is SomeUnsignedInt:
    try:
      let parsed = input.parseBiggestUInt()
      if parsed <= T.high.uint:
        return ok($(T(parsed)))
      return err(fmt"Expected value between 0 and {T.high.uint} but found {input}")
    except ValueError:
      return err(fmt"Failed to parse input: {input}")
  elif T is SomeFloat:
    try:
      let parsed = input.parseFloat()
      let reconstructed = $(T(parsed))
      if reconstructed == input.strip:
        return ok(reconstructed)
      return err(fmt"Precision loss encountered original: {parsed} stored: {T(parsed)}")
    except ValueError:
      return err(fmt"Failed to parse input: {input}")

proc as_integer*(native_literal: NumericLiteral): Result[string, string] =
  case native_literal.kind:
  of NLK_INTEGER: safe_parse_number[int64](native_literal.integer_value)
  else: err(fmt"Numeric literal {native_literal} must an integer")

proc as_float*(native_literal: NumericLiteral): Result[string, string] =
  case native_literal.kind:
  of NLK_FLOAT: safe_parse_number[float64](native_literal.float_value)
  else: err(fmt"Numeric literal {native_literal} must a float")
