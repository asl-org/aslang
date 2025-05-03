import hashes, results, strformat

import "../location"
import numeric_literal, string_literal, struct_literal

type
  LiteralKind = enum
    LK_NUMERIC, LK_STRING, LK_STRUCT
  Literal* = ref object of RootObj
    location: Location
    case kind: LiteralKind
    of LK_NUMERIC: numeric_literal: NumericLiteral
    of LK_STRING: string_literal: StringLiteral
    of LK_STRUCT: struct_literal: StructLiteral

proc `$`*(literal: Literal): string =
  case literal.kind:
    of LK_NUMERIC: $(literal.numeric_literal)
    of LK_STRING: $(literal.string_literal)
    of LK_STRUCT: $(literal.struct_literal)

proc new_numeric_literal*(value: NumericLiteral, location: Location): Literal =
  Literal(kind: LK_NUMERIC, numeric_literal: value, location: location)

proc new_string_literal*(value: StringLiteral, location: Location): Literal =
  Literal(kind: LK_STRING, string_literal: value, location: location)

proc new_struct_literal*(value: StructLiteral, location: Location): Literal =
  Literal(kind: LK_STRUCT, struct_literal: value, location: location)

proc hash*(literal: Literal): Hash =
  let sub_hash =
    case literal.kind:
    of LK_NUMERIC: hash(literal.numeric_literal)
    of LK_STRING: hash(literal.string_literal)
    of LK_STRUCT: hash(literal.struct_literal)

  hash(literal.kind) !& sub_hash

proc as_integer*(literal: Literal): Result[string, string] =
  case literal.kind:
  of LK_NUMERIC: literal.numeric_literal.as_integer
  else: err(fmt"Literal {literal} must be an integer.")

proc as_float*(literal: Literal): Result[string, string] =
  case literal.kind:
  of LK_NUMERIC: literal.numeric_literal.as_float
  else: err(fmt"Literal {literal} must be a float.")
