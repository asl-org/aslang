import results, strformat, strutils

import common

proc safe_parse_integer*(s: string, lo: int, hi: int, convert: proc(
    value: int): string): Result[string, string] =
  try:
    let parsed = s.parseBiggestInt()
    if parsed >= lo and parsed <= hi:
      return ok(convert(parsed))
    return err(fmt"Expected a value between {lo} to {hi} but found {s}")
  except ValueError:
    return err(fmt"Failed to parse integer {s}")

proc safe_parse_int8*(s: string): Result[string, string] =
  safe_parse_integer(s, int8.low.int, int8.high.int, proc (v: int): string = $(int8(v)))

proc safe_parse_int16*(s: string): Result[string, string] =
  safe_parse_integer(s, int16.low.int, int16.high.int, proc (
      v: int): string = $(int16(v)))

proc safe_parse_int32*(s: string): Result[string, string] =
  safe_parse_integer(s, int32.low.int, int32.high.int, proc (
      v: int): string = $(int32(v)))

proc safe_parse_int64*(s: string): Result[string, string] =
  safe_parse_integer(s, int64.low.int, int64.high.int, proc (
      v: int): string = $(int64(v)))

proc safe_parse_uint8*(s: string): Result[string, string] =
  safe_parse_integer(s, uint8.low.int, uint8.high.int, proc (
      v: int): string = $(uint8(v)))

proc safe_parse_uint16*(s: string): Result[string, string] =
  safe_parse_integer(s, uint16.low.int, uint16.high.int, proc (
      v: int): string = $(uint16(v)))

proc safe_parse_uint32*(s: string): Result[string, string] =
  safe_parse_integer(s, uint32.low.int, uint32.high.int, proc (
      v: int): string = $(uint32(v)))

proc safe_parse_uint64*(s: string): Result[string, string] =
  safe_parse_integer(s, uint64.low.int, uint64.high.int, proc (
      v: int): string = $(uint64(v)))

proc safe_parse_float32*(s: string): Result[string, string] =
  try:
    let parsed = s.parseFloat()
    # make sure we do not lose any precision while casting
    if float64(float32(parsed)) == parsed:
      return ok($(float32(parsed)))
    return err(fmt"1 Expected a float value but found {s}")
  except ValueError:
    return err(fmt"Expected a float value but found {s}")

proc safe_parse_float64*(s: string): Result[string, string] =
  try:
    let parsed = s.parseFloat()
    return ok($(float64(parsed)))
  except ValueError:
    return err(fmt"Expected a float value but found {s}")

type Scope* = object
  variables*: seq[Variable]
  functions*: seq[Function]

proc get_variable*(scope: Scope, variable_name: string): Result[Variable, string] =
  for v in scope.variables:
    if variable_name == v.name:
      return ok(v)
  return err(fmt"Variable {variable_name} is not defined in the scope")

proc get_function*(scope: Scope, func_name: string): Result[Function, string] =
  for f in scope.functions:
    if f.name == func_name:
      return ok(f)
  return err(fmt"Function {func_name} is not defined in the scope")

proc initialize_variable*(scope: var Scope, variable: Variable): Result[
    Scope, string] =
  let variable_defined_in_scope = scope.get_variable(variable.name)
  if variable_defined_in_scope.is_ok:
    return err(fmt"Variable {variable.name} is already defined at {variable_defined_in_scope.get.datatype.location}")
  scope.variables.add(variable)
  ok(scope)

proc move_value*(scope: Scope, dest: Variable,
    src: string): Result[Scope, string] =
  let src_variable = ? scope.get_variable(src)
  let dest_datatype = dest.datatype.name
  let src_datatype = src_variable.datatype.name
  if src_datatype != dest_datatype:
    return err(fmt"Variable {src} ({src_datatype}) can not be assigned to {dest.name} ({dest_datatype})")
  ok(scope)

proc get_native_function_call(scope: Scope, def: FunctionDefinition, args: seq[
    Argument]): Result[string, string] =

  var call_args: seq[string]
  for index, arg in pairs(args):
    case arg.kind:
    of ArgumentKind.AK_IDENTIFIER:
      discard ? scope.move_value(def.args[index], arg.identifier.name)
      call_args.add(arg.identifier.name)
    of ArgumentKind.AK_LITERAL:
      case arg.literal.kind:
      of LiteralKind.LK_INTEGER:
        case def.args[index].datatype.name:
        of "S8":
          if safe_parse_int8(arg.literal.value).is_ok:
            call_args.add(arg.literal.value)
          else: break
        of "S16":
          if safe_parse_int16(arg.literal.value).is_ok:
            call_args.add(arg.literal.value)
          else:
            break
        of "S32":
          if safe_parse_int32(arg.literal.value).is_ok:
            call_args.add(arg.literal.value)
          else:
            break
        of "S64":
          if safe_parse_int64(arg.literal.value).is_ok:
            call_args.add(arg.literal.value)
          else:
            break
        of "U8":
          if safe_parse_uint8(arg.literal.value).is_ok:
            call_args.add(arg.literal.value)
          else:
            break
        of "U16":
          if safe_parse_uint16(arg.literal.value).is_ok:
            call_args.add(arg.literal.value)
          else:
            break
        of "U32":
          if safe_parse_uint32(arg.literal.value).is_ok:
            call_args.add(arg.literal.value)
          else:
            break
        of "U64":
          if safe_parse_uint64(arg.literal.value).is_ok:
            call_args.add(arg.literal.value)
          else:
            break
      of LiteralKind.LK_FLOAT:
        case def.args[index].datatype.name:
        of "F32":
          if safe_parse_float32(arg.literal.value).is_ok:
            call_args.add(arg.literal.value)
          else:
            break
        of "F64":
          if safe_parse_float64(arg.literal.value).is_ok:
            call_args.add(arg.literal.value)
          else:
            break
      of LiteralKind.LK_STRING:
        return err(fmt"String literal are not yet supported")

  let native_call_args = call_args.join(", ")
  return ok(fmt"{def.native_function}({native_call_args});")

proc find_function*(scope: Scope, func_name: string, args: seq[
    Argument]): Result[string, string] =
  let function = ? get_function(scope, func_name)
  for def in function.defs:
    # arg len must be same for call and defintion
    if def.args.len != args.len: continue

    let native_function_call = scope.get_native_function_call(def, args)
    if native_function_call.is_ok: return ok(native_function_call.get)

  return err(fmt"Failed to resolve the function none of the function defintions match")
