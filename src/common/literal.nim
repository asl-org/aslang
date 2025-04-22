import hashes, results, strformat

import location, native_literal, struct

type
  LiteralKind = enum
    LK_NATIVE, LK_STRUCT
  Literal* = ref object of RootObj
    location: Location
    case kind: LiteralKind
    of LK_NATIVE: native: NativeLiteral
    of LK_STRUCT: struct: Struct

proc `$`*(literal: Literal): string =
  case literal.kind:
    of LK_NATIVE: $(literal.native)
    of LK_STRUCT: $(literal.struct)

proc new_native_literal*(value: NativeLiteral, location: Location): Literal =
  Literal(kind: LK_NATIVE, native: value, location: location)

proc new_struct_literal*(value: Struct,
    location: Location): Literal =
  Literal(kind: LK_STRUCT, struct: value, location: location)

proc hash*(literal: Literal): Hash =
  let sub_hash =
    case literal.kind:
    of LK_NATIVE: hash(literal.native)
    of LK_STRUCT: hash(literal.struct)

  hash(literal.kind) !& sub_hash

proc as_integer*(literal: Literal): Result[string, string] =
  case literal.kind:
  of LK_NATIVE: literal.native.as_integer
  of LK_STRUCT: err(fmt"Literal {literal} must be an integer.")

proc as_float*(literal: Literal): Result[string, string] =
  case literal.kind:
  of LK_NATIVE: literal.native.as_float
  of LK_STRUCT: err(fmt"Literal {literal} must be a float.")
