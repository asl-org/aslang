import results, strutils, strformat

import common
import scope
import builtins

proc generate_init_code(scope: var Scope, i: Initializer): Result[string, string] =
  let datatype = i.variable.datatype.name
  case i.value.kind:
  of ValueKind.VK_LITERAL:
    let literal = i.value.literal
    case literal.kind:
    of LiteralKind.LK_INTEGER:
      var integer_value: string
      var native_datatype: string
      case datatype:
      of "S8":
        integer_value = ? safe_parse_int8(literal.value)
        native_datatype = "s8"
      of "S16":
        integer_value = ? safe_parse_int16(literal.value)
        native_datatype = "s16"
      of "S32":
        integer_value = ? safe_parse_int32(literal.value)
        native_datatype = "s32"
      of "S64":
        integer_value = ? safe_parse_int64(literal.value)
        native_datatype = "s64"
      of "U8":
        integer_value = ? safe_parse_uint8(literal.value)
        native_datatype = "u8"
      of "U16":
        integer_value = ? safe_parse_uint16(literal.value)
        native_datatype = "u16"
      of "U32":
        integer_value = ? safe_parse_uint32(literal.value)
        native_datatype = "u32"
      of "U64":
        integer_value = ? safe_parse_uint64(literal.value)
        native_datatype = "u64"
      else:
        return err(fmt"Found unexpected integer literal {literal}")

      scope = ? scope.initialize_variable(i.variable)
      return ok(fmt"{native_datatype} {i.variable.name} = {integer_value};")
    of LiteralKind.LK_FLOAT:
      var float_value: string
      var native_datatype: string
      case datatype:
      of "F32":
        float_value = ? safe_parse_float32(literal.value)
        native_datatype = "f32"
      of "F64":
        float_value = ? safe_parse_float64(literal.value)
        native_datatype = "f64"
      else: return err(fmt"Found unexpected float literal {literal}")

      scope = ? scope.initialize_variable(i.variable)
      return ok(fmt"{native_datatype} {i.variable.name} = {float_value};")
    else:
      return err(fmt"Expected an integer/float value but found {literal}")
  of ValueKind.VK_IDENTIFIER:
    scope = ? scope.move_value(i.variable, i.value.identifier.name)
    scope = ? scope.initialize_variable(i.variable)
    return ok(fmt"{i.variable.datatype.name.toLowerAscii} {i.variable.name} = {i.value.identifier.name};")

proc generate_fncall_code(scope: var Scope, f: FunctionCall): Result[string, string] =
  var left: string

  # if function call output is not ignored
  if f.variable.name != "_":
    left = f.variable.name & " = "

  var fncall = ? scope.find_function(f.name, f.arglist.args)
  ok(left & fncall)

proc add_base_context(code: string): string =
  let context = @[
    """#include "asl.h"""",
    "",
    "c_int main(c_int argc, c_char **argv)",
    "{",
    "",
    code,
    "",
    "return 0;",
    "}",
  ]

  return context.join("\n")

proc generate*(statements: seq[Statement]): Result[string, string] =
  var c_statements: seq[string] = @[]
  var code: string
  var scope = Scope(functions: builtin_functions())

  for s in statements:
    case s.kind
    of StatementKind.SK_INIT:
      code = ? scope.generate_init_code(s.initializer)
      c_statements.add(code)
    of StatementKind.SK_FNCALL:
      code = ? scope.generate_fncall_code(s.fncall)
      c_statements.add(code)
  code = c_statements.join("\n")
  ok(add_base_context(code))

