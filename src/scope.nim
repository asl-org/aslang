import results, strformat, strutils

import common

const ASL_VAR_PREFIX = "__asl_"

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

proc to_c_number(input: string, datatype: string): Result[string, string] =
  case datatype:
    of "S8": safe_parse_number[int8](input)
    of "S16": safe_parse_number[int16](input)
    of "S32": safe_parse_number[int32](input)
    of "S64": safe_parse_number[int64](input)
    of "U8": safe_parse_number[uint8](input)
    of "U16": safe_parse_number[uint16](input)
    of "U32": safe_parse_number[uint32](input)
    of "U64": safe_parse_number[uint64](input)
    of "F32": safe_parse_number[float32](input)
    of "F64": safe_parse_number[float64](input)
    else: err(fmt"Found unexpected datatype {datatype}")

proc to_c_datatype(datatype: string): Result[string, string] =
  case datatype:
  of "S8", "S16", "S32", "S64", "U8", "U16", "U32", "U64", "F32", "F64": ok(
      datatype)
  else: err(fmt"Found unexpected datatype {datatype}")

type Scope* = object
  variables*: seq[Variable]
  functions*: seq[Function]
  temp_var_count: int = 0

proc get_variable(scope: Scope, variable_name: string): Result[Variable, string] =
  for v in scope.variables:
    if variable_name == v.name:
      return ok(v)
  return err(fmt"Variable {variable_name} is not defined in the scope")

proc match_datatypes(scope: var Scope, dest: Variable,
    src: string): Result[Scope, string] =
  let src_variable = ? scope.get_variable(src)
  let dest_datatype = dest.datatype.name
  let src_datatype = src_variable.datatype.name
  if src_datatype != dest_datatype:
    return err(fmt"Variable {src} ({src_datatype}) can not be assigned to {dest.name} ({dest_datatype})")
  ok(scope)

proc get_function_defintions(scope: Scope, func_name: string): Result[seq[
    FunctionDefinition], string] =
  for f in scope.functions:
    if f.name == func_name:
      return ok(f.defs)
  return err(fmt"Function {func_name} is not defined in the scope")

proc c_function_arg(scope: var Scope, def_arg: Variable,
    arg: Argument): Result[string, string] =
  case arg.kind:
  of ArgumentKind.AK_IDENTIFIER:
    scope = ? scope.match_datatypes(def_arg, arg.identifier.name)
    ok(fmt"{ASL_VAR_PREFIX}{arg.identifier.name}")
  of ArgumentKind.AK_LITERAL:
    case arg.literal.kind:
    of LiteralKind.LK_INTEGER, LiteralKind.LK_FLOAT:
      arg.literal.value.to_c_number(def_arg.datatype.name)
    of LiteralKind.LK_STRING:
      return err(fmt"String literal are not yet supported")

proc c_function_call(scope: var Scope, def: FunctionDefinition,
    args: seq[Argument]): Result[string, string] =

  var call_args: seq[string]
  for index, arg in pairs(args):
    let call_arg = ? scope.c_function_arg(def.args[index], arg)
    call_args.add(call_arg)

  let native_call_args = call_args.join(", ")
  return ok(fmt"{def.native_function}({native_call_args});")

proc define_variable(scope: var Scope, variable: Variable): Result[
    Scope, string] =
  let variable_defined_in_scope = scope.get_variable(variable.name)
  if variable_defined_in_scope.is_ok:
    return err(fmt"Variable {variable.name} is already defined at {variable_defined_in_scope.get.datatype.location}")
  scope.variables.add(variable)
  ok(scope)

proc move_variable(scope: var Scope, dest: Variable,
    src: string): Result[Scope, string] =
  scope = ? scope.match_datatypes(dest, src)
  scope = ? scope.define_variable(dest)
  ok(scope)

proc get_destination_variable(scope: var Scope, dest_var_name: string,
    datatype: Datatype): Result[Variable, string] =
  var dest_name: string
  # in case output is ignored in ASL make a temporary variable to assign to
  if dest_var_name == "_":
    dest_name = fmt"_temp_{scope.temp_var_count}"
    scope.temp_var_count += 1
  else:
    dest_name = dest_var_name

  let dest_variable = Variable(name: dest_name, datatype: datatype)
  scope = ? scope.define_variable(dest_variable)
  return ok(dest_variable)

proc init*(scope: var Scope, i: Initializer): Result[string, string] =
  let asl_datatype = i.variable.datatype.name
  let c_datatype: string = ? asl_datatype.to_c_datatype()

  case i.value.kind:
  of ArgumentKind.AK_LITERAL:
    let literal = i.value.literal
    case literal.kind:
    of LiteralKind.LK_INTEGER, LiteralKind.LK_FLOAT:
      var number_value: string = ? literal.value.to_c_number(asl_datatype)
      scope = ? scope.define_variable(i.variable)
      ok(fmt"{c_datatype} {ASL_VAR_PREFIX}{i.variable.name} = {number_value};")
    else:
      err(fmt"Expected an integer/float value but found {literal}")
  of ArgumentKind.AK_IDENTIFIER:
    scope = ? scope.move_variable(i.variable, i.value.identifier.name)
    ok(fmt"{c_datatype} {ASL_VAR_PREFIX}{i.variable.name} = {ASL_VAR_PREFIX}{i.value.identifier.name};")

proc call*(scope: var Scope, f: FunctionCall): Result[string, string] =
  let args = f.arglist.args
  let func_defs = ? get_function_defintions(scope, f.name)
  for def in func_defs:
    # arg len must be same for call and defintion
    if def.args.len != args.len: continue

    let native_function_call = scope.c_function_call(def, args)
    if native_function_call.is_ok:
      let dest_var = ? scope.get_destination_variable(f.variable.name, def.result)
      return ok(fmt"{dest_var.datatype.name} {ASL_VAR_PREFIX}{dest_var.name} = {native_function_call.get}")

  return err(fmt"Failed to resolve the function none of the function defintions match {f.location}")
