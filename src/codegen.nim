import results, strutils, strformat, sequtils

import common

proc safe_parse_int8(s: string): Result[string, string] =
  try:
    let parsed = s.parseBiggestInt()
    if parsed >= int8.low.int and parsed <= int8.high.int:
      return ok($(int8(parsed)))
    return err(fmt"Expected a value between {int8.low} to {int8.high} but found {s}")
  except ValueError:
    return err(fmt"Expected a value between {int8.low} to {int8.high} but found {s}")

proc safe_parse_int16(s: string): Result[string, string] =
  try:
    let parsed = s.parseBiggestInt()
    if parsed >= int16.low.int and parsed <= int16.high.int:
      return ok($(int16(parsed)))
    return err(fmt"Expected a value between {int16.low} to {int16.high} but found {s}")
  except ValueError:
    return err(fmt"Expected a value between {int16.low} to {int16.high} but found {s}")

proc safe_parse_int32(s: string): Result[string, string] =
  try:
    let parsed = s.parseBiggestInt()
    if parsed >= int32.low.int and parsed <= int32.high.int:
      return ok($(int32(parsed)))
    return err(fmt"Expected a value between {int32.low} to {int32.high} but found {s}")
  except ValueError:
    return err(fmt"Expected a value between {int32.low} to {int32.high} but found {s}")

proc safe_parse_int64(s: string): Result[string, string] =
  try:
    let parsed = s.parseBiggestInt()
    if parsed >= int64.low.int and parsed <= int64.high.int:
      return ok($(int64(parsed)))
    return err(fmt"Expected a value between {int64.low} to {int64.high} but found {s}")
  except ValueError:
    return err(fmt"Expected a value between {int64.low} to {int64.high} but found {s}")

proc safe_parse_uint8(s: string): Result[string, string] =
  try:
    let parsed = s.parseBiggestInt()
    if parsed >= uint8.low.int and parsed <= uint8.high.int:
      return ok($(uint8(parsed)))
    return err(fmt"Expected a value between {uint8.low} to {uint8.high} but found {s}")
  except ValueError:
    return err(fmt"Expected a value between {uint8.low} to {uint8.high} but found {s}")

proc safe_parse_uint16(s: string): Result[string, string] =
  try:
    let parsed = s.parseBiggestInt()
    if parsed >= uint16.low.int and parsed <= uint16.high.int:
      return ok($(uint16(parsed)))
    return err(fmt"Expected a value between {uint16.low} to {uint16.high} but found {s}")
  except ValueError:
    return err(fmt"Expected a value between {uint16.low} to {uint16.high} but found {s}")

proc safe_parse_uint32(s: string): Result[string, string] =
  try:
    let parsed = s.parseBiggestInt()
    if parsed >= uint32.low.int and parsed <= uint32.high.int:
      return ok($(uint32(parsed)))
    return err(fmt"Expected a value between {uint32.low} to {uint32.high} but found {s}")
  except ValueError:
    return err(fmt"Expected a value between {uint32.low} to {uint32.high} but found {s}")

proc safe_parse_uint64(s: string): Result[string, string] =
  try:
    let parsed = s.parseBiggestInt()
    return ok($(uint64(parsed)))
  except ValueError:
    return err(fmt"Expected a value between {uint64.low} to {uint64.high} but found {s}")

proc can_represent_float32(value: float64): bool =
  let as_float32 = float32(value)
  let back_to_float64 = float64(as_float32)
  return back_to_float64 == value

proc safe_parse_float32(s: string): Result[string, string] =
  try:
    let parsed = s.parseFloat()
    if parsed.can_represent_float32:
      return ok($(float32(parsed)))
    return err(fmt"1 Expected a float value but found {s}")
  except ValueError:
    return err(fmt"Expected a float value but found {s}")

proc safe_parse_float64(s: string): Result[string, string] =
  try:
    let parsed = s.parseFloat()
    return ok($(float64(parsed)))
  except ValueError:
    return err(fmt"Expected a float value but found {s}")

proc generate_init_code(i: Initializer): Result[string, string] =
  let datatype = i.datatype.refs.map(proc(
      x: Identifier): string = x.name).join("_")
  var code: string
  let literal = i.literal
  if literal.kind == LiteralKind.LK_INTEGER:
    var integer_value: string
    var native_function: string
    case datatype:
    of "S8":
      integer_value = ? safe_parse_int8(literal.value)
      native_function = "s8_as_number"
    of "S16":
      integer_value = ? safe_parse_int16(literal.value)
      native_function = "s16_as_number"
    of "S32":
      integer_value = ? safe_parse_int32(literal.value)
      native_function = "s32_as_number"
    of "S64":
      integer_value = ? safe_parse_int64(literal.value)
      native_function = "s64_as_number"
    of "U8":
      integer_value = ? safe_parse_uint8(literal.value)
      native_function = "u8_as_number"
    of "U16":
      integer_value = ? safe_parse_uint16(literal.value)
      native_function = "u16_as_number"
    of "U32":
      integer_value = ? safe_parse_uint32(literal.value)
      native_function = "u32_as_number"
    of "U64":
      integer_value = ? safe_parse_uint64(literal.value)
      native_function = "u64_as_number"
    else: return err(fmt"Found unexpected integer literal {literal}")
    code = fmt"Number {i.variable.name} = {native_function}({integer_value});"
  elif literal.kind == LiteralKind.LK_FLOAT:
    var float_value: string
    var native_function: string
    case datatype:
    of "F32":
      float_value = ? safe_parse_float32(literal.value)
      native_function = "f32_as_number"
    of "F64":
      float_value = ? safe_parse_float64(literal.value)
      native_function = "f64_as_number"
    else: return err(fmt"Found unexpected float literal {literal}")
    code = fmt"Number {i.variable.name} = {native_function}({float_value});"
  else:
    return err(fmt"Expected an integer/float value but found {literal}")
  ok(code)

proc generate_fncall_code(f: FunctionCall): Result[string, string] =
  var left: string

  # if function call output is not ignored
  if f.variable.name != "_":
    left = f.variable.name & " = "

  var c_args: seq[string] = @[]
  for arg in f.arglist.args:
    if arg.kind == AK_IDENTIFIER:
      c_args.add(arg.identifier.name)
    else:
      return err(fmt"Expected an identifier but found {arg}")

  let c_arglist = c_args.join(", ")
  let fname = f.name.name
  ok(fmt"{left}{fname}({c_arglist});")

proc add_base_context(code: string): string =
  let head = """
#include "asl.h"

c_int main(c_int argc, c_char **argv)
{

"""
  let tail = """

return 0;
}
"""
  return head & code & tail

proc generate*(statements: seq[Statement]): Result[string, string] =
  var c_statements: seq[string] = @[]
  var code: string

  for s in statements:
    case s.kind
    of StatementKind.SK_INIT:
      code = ? generate_init_code(s.initializer)
      c_statements.add(code)
    of StatementKind.SK_FNCALL:
      code = ? generate_fncall_code(s.fncall)
      c_statements.add(code)

  code = c_statements.join("\n")
  ok(add_base_context(code))

