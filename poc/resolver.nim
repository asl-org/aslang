import results, tables, strformat, sequtils, parseutils, sets

import tokenizer
import parser
import blocks

type File = blocks.File

proc safe_parse*[T](input: string): Result[void, string] =
  when T is SomeSignedInt:
    var temp: BiggestInt
    let code = parseBiggestInt(input, temp)
    if code == 0 or code != input.len:
      return err("Failed to parse signed int from: " & input)
    if temp < T.low.BiggestInt or temp > T.high.BiggestInt:
      return err("Overflow: Value out of range for type " & $T)
    ok()
  elif T is SomeUnsignedInt:
    var temp: BiggestUInt
    let code = parseBiggestUInt(input, temp)
    if code == 0 or code != input.len:
      return err("Failed to parse unsigned int from: " & input)
    if temp < T.low.BiggestUInt or temp > T.high.BiggestUInt:
      return err("Overflow: Value out of range for type " & $T)
    ok()
  elif T is SomeFloat:
    var temp: BiggestFloat
    let code = parseBiggestFloat(input, temp)
    if code == 0 or code != input.len:
      return err("Failed to parse float from: " & input)
    let casted = T(temp)
    if BiggestFloat(casted) != temp:
      return err("Precision loss when converting to " & $T)
    ok()
  else:
    err("safe_parse only supports signed/unsigned integers and floating-point types")

proc resolve_argument(scope: Table[string, ArgumentDefinition],
    arg_def: ArgumentDefinition, arg_value: Token): Result[void, string] =
  case arg_value.kind:
  of TK_ID:
    if $(arg_value) notin scope:
      return err(fmt"{arg_value.location} {arg_value} is not defined in the scope")
    if $(scope[$(arg_value)].arg_type) != $(arg_def.arg_type):
      return err(fmt"{arg_value.location} expected {arg_def.arg_type} but found {scope[$(arg_value)].arg_type}")
  of TK_INTEGER:
    case $(arg_def.arg_type):
    of "U8": ? safe_parse[uint8]($(arg_value))
    of "U16": ? safe_parse[uint16]($(arg_value))
    of "U32": ? safe_parse[uint32]($(arg_value))
    of "U64": ? safe_parse[uint64]($(arg_value))
    of "S8": ? safe_parse[int8]($(arg_value))
    of "S16": ? safe_parse[int16]($(arg_value))
    of "S32": ? safe_parse[int32]($(arg_value))
    of "S64": ? safe_parse[int64]($(arg_value))
    else: return err(fmt"{arg_value.location} arguments with builting types can be passed as integer")
  of TK_FLOAT:
    case $(arg_def.arg_type):
    of "F32": ? safe_parse[float32]($(arg_value))
    of "F64": ? safe_parse[float64]($(arg_value))
    else: return err(fmt"{arg_value.location} arguments with builting types can be passed as float")
  else: # TODO: Support strings as arguments
    return err(fmt"{arg_value.location} {arg_value} can not be passed to a function as argument")
  ok()

# matches individual function with function call
proc resolve_function_call(scope: Table[string, ArgumentDefinition],
    function: FunctionDefinition, function_call: FunctionCall): Result[
        FunctionDefinition, string] =
  if $(function.name) != $(function_call.name):
    return err(fmt"{function_call.location} expected function with name {function.name} but found {function_call.name}")
  if function.arg_def_list.len != function_call.arg_list.len:
    return err(fmt"{function_call.location} expected {function.arg_def_list.len} but found {function_call.arg_list.len}")

  for (arg_def, arg_value) in zip(function.arg_def_list,
      function_call.arg_list):
    ? scope.resolve_argument(arg_def, arg_value)
  ok(function)

# matches all functions with function call within a file
proc resolve_function_call(file: File, scope: Table[string,
    ArgumentDefinition], function_call: FunctionCall): Result[Function, string] =
  for function in file.functions:
    let maybe_resolved = scope.resolve_function_call(function.definition, function_call)
    if maybe_resolved.is_ok:
      return ok(function)
  return err(fmt"{function_call.location} `{function_call.name}` failed to find matching function in the file {file.name}")

proc resolve_builtin_function_call(file: File, scope: Table[string,
    ArgumentDefinition], function_call: FunctionCall): Result[
        FunctionDefinition, string] =
  for function_def in file.builtins:
    let maybe_resolved = scope.resolve_function_call(function_def, function_call)
    if maybe_resolved.is_ok:
      return ok(function_def)
  return err(fmt"{function_call.location} `{function_call.name}` failed to find matching function in the file {file.name}")

proc resolve_function(file: File, function: Function): Result[HashSet[Function], string] =
  var function_set = init_hashset[Function]()

  discard ? file.find_module(function.definition.return_type)
  # add function definition args
  for arg in function.arg_def_list:
    discard ? file.find_module(arg.arg_type)
    if $(arg.arg_name) in function.scope:
      let defined_arg = function.scope[$(arg.arg_name)]
      return err(fmt"{arg.location} {arg.arg_name} is already defined {defined_arg.location}")
    function.scope[$(arg.arg_name)] = arg

  for statement in function.statements:
    if $(statement.destination) in function.scope:
      let defined_arg = function.scope[$(statement.destination)]
      return err(fmt"{statement.destination.location} {statement.destination} is already defined {defined_arg.location}")

    # try looking up builtins function call
    let maybe_builtin = file.resolve_builtin_function_call(function.scope,
        statement.function_call)
    if maybe_builtin.is_ok:
      function.scope[$(statement.destination)] = new_argument_definition(
          maybe_builtin.get.return_type, statement.destination)
      continue

    # try looking up user function call
    let fn = ? file.resolve_function_call(function.scope,
        statement.function_call)
    function.scope[$(statement.destination)] = new_argument_definition(
        fn.definition.return_type, statement.destination)
    function_set.incl(fn)

  let return_argument = function.statements[^1].destination
  let actual_return_type = $(function.scope[$(return_argument)].arg_type)

  if function.return_type != actual_return_type:
    return err(fmt"{function.location} expected {function.name} to return {function.return_type} but found {actual_return_type}")

  return ok(function_set)

proc resolve*(file: File): Result[seq[Function], string] =
  var stack = @[ ? file.find_start_function()]
  var visited_functions = init_hashset[Function]()
  while stack.len > 0:
    let function = stack[^1]
    stack.set_len(stack.len - 1)
    if function in visited_functions: continue

    let new_functions = ? file.resolve_function(function)
    visited_functions.incl(function)

    for new_function in new_functions:
      if new_function notin visited_functions:
        stack.add(new_function)
  ok(visited_functions.to_seq)
