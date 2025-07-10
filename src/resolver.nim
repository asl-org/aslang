import results, tables, strformat, sequtils, parseutils, sets, options, strutils

import blocks

import resolved/expression; export expression
import resolved/function_call; export function_call
import resolved/struct_init; export struct_init
import resolved/struct_getter; export struct_getter
import resolved/statement; export statement
import resolved/case_block; export case_block
import resolved/else_block; export else_block
import resolved/match; export match
import resolved/function_step; export function_step
import resolved/function; export function
import resolved/struct; export struct
import resolved/file; export file

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

proc resolve_expression(scope: Table[string, ArgumentDefinition],
    arg_def: ArgumentDefinition, arg_value: Token): Result[ResolvedExpression, string] =
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

  ok(new_resolved_expression(arg_def.arg_type, arg_value))

# matches individual function with function call
proc resolve_function_call_args(function_call: FunctionCall,
    function_def: FunctionDefinition, scope: Table[string,
    ArgumentDefinition]): Result[seq[ResolvedExpression], string] =
  if $(function_def.name) != $(function_call.name):
    return err(fmt"{function_call.location} expected function with name {function_call.name} but found {function_def.name}")
  if function_def.arg_def_list.len != function_call.arg_list.len:
    return err(fmt"{function_call.location} expected {function_def.arg_def_list.len} but found {function_call.arg_list.len}")

  var resolved_args: seq[ResolvedExpression]
  for (arg_def, arg_value) in zip(function_def.arg_def_list,
      function_call.arg_list):
    resolved_args.add( ? scope.resolve_expression(arg_def, arg_value))
  ok(resolved_args)

proc resolve_function_call(function_call: FunctionCall, file: blocks.File,
    scope: Table[string, ArgumentDefinition]): Result[ResolvedFunctionCall, string] =
  case function_call.func_ref.kind:
  of FRK_LOCAL:
    for function in file.functions:
      let maybe_resolved_args = function_call.resolve_function_call_args(
          function.definition, scope)
      if maybe_resolved_args.is_ok:
        return ok(new_resolved_function_call(function, maybe_resolved_args.get))
  of FRK_MODULE:
    let module = ? file.find_module(function_call.func_ref.module)
    case module.kind:
    of MK_BUILTIN:
      for function_def in module.function_defs:
        let maybe_resolved_args = function_call.resolve_function_call_args(
            function_def, scope)
        if maybe_resolved_args.is_ok:
          return ok(new_resolved_function_call(module, function_def,
              maybe_resolved_args.get))
    of MK_USER:
      for function in ( ? module.functions):
        let maybe_resolved_args = function_call.resolve_function_call_args(
            function.definition, scope)
        if maybe_resolved_args.is_ok:
          return ok(new_resolved_function_call(module, function,
              maybe_resolved_args.get))
  return err(fmt"{function_call.location} `{function_call.name}` failed to find matching function in the file {file.name}")

proc resolve_struct_init(struct_init: StructInit, file: blocks.File,
    scope: Table[string, ArgumentDefinition]): Result[ResolvedStructInit, string] =
  let struct_var = struct_init.struct
  let key_value_pairs = struct_init.fields

  let struct = ? file.find_struct(struct_var)
  var field_name_table: Table[string, ResolvedExpression]
  for (field_name, field_value) in key_value_pairs:
    if $(field_name) in field_name_table:
      return err(fmt"{field_name.location} {field_name} is already present in the initializer")
    let field = ? struct.find_field(field_name)
    field_name_table[$(field_name)] = ? scope.resolve_expression(field, field_value)

  let resolved_fields = struct.fields.map_it(field_name_table[$(it.arg_name)])
  let resolved_struct_init = new_resolved_struct_init(struct, resolved_fields)
  ok(resolved_struct_init)

proc resolve_struct_getter(struct_getter: StructGetter, file: blocks.File,
    scope: Table[string, ArgumentDefinition]): Result[ResolvedStructGetter, string] =
  let struct_var = struct_getter.struct
  let field_name = struct_getter.field

  if $(struct_var) notin scope:
    return err(fmt"{struct_var.location} {struct_var} is not defined in the scope")

  let struct = ? file.find_struct(scope[$(struct_var)].arg_type)
  let field = ? struct.find_field(field_name)
  let resolved_struct_getter = new_resolved_struct_getter(struct, field, struct_var)
  ok(resolved_struct_getter)

proc resolve_statement(statement: Statement, file: blocks.File, scope: Table[
    string, ArgumentDefinition]): Result[ResolvedStatement, string] =
  # check if variable is already defined in the local(case) scope
  if $(statement.destination) in scope:
    let defined_arg = scope[$(statement.destination)]
    return err(fmt"{statement.destination.location} {statement.destination} is already defined {defined_arg.location}")

  case statement.kind:
  of SK_STRUCT_INIT:
    let resolved_struct_init = ? statement.struct_init.resolve_struct_init(file,
        scope)
    ok(new_resolved_statement(resolved_struct_init, statement.destination))
  of SK_STRUCT_GETTER:
    let resolved_struct_getter = ? statement.struct_getter.resolve_struct_getter(
        file, scope)
    ok(new_resolved_statement(resolved_struct_getter, statement.destination))
  of SK_FUNCTION_CALL:
    let resolved_function_call = ? statement.function_call.resolve_function_call(
        file, scope)
    ok(new_resolved_statement(resolved_function_call, statement.destination))

proc resolve_case_block(case_block: Case, file: blocks.File,
    parent_scope: Table[string, ArgumentDefinition]): Result[ResolvedCase, string] =
  var resolved_statements: seq[ResolvedStatement]
  # copy current function scope to the case scope to avoid non local argument name conflicts
  var scope = parent_scope
  for (index, statement) in case_block.statements.pairs:
    let resolved_statement = ? statement.resolve_statement(file, scope)
    resolved_statements.add(resolved_statement)
    scope[$(statement.destination)] = resolved_statement.return_argument

  return ok(new_resolved_case(case_block, resolved_statements))

proc resolve_else_block(else_block: Else, file: blocks.File,
    parent_scope: Table[string, ArgumentDefinition]): Result[ResolvedElse, string] =
  var resolved_statements: seq[ResolvedStatement]
  # copy current function scope to the else scope to avoid non local argument name conflicts
  var scope = parent_scope
  for (index, statement) in else_block.statements.pairs:
    let resolved_statement = ? statement.resolve_statement(file, scope)
    resolved_statements.add(resolved_statement)
    scope[$(statement.destination)] = resolved_statement.return_argument

  return ok(new_resolved_else(else_block, resolved_statements))

proc resolve_match(match: Match, file: blocks.File, scope: Table[string,
    ArgumentDefinition]): Result[ResolvedMatch, string] =
  var resolved_case_blocks: seq[ResolvedCase]
  var resolved_else_blocks: seq[ResolvedElse]
  if $(match.destination) in scope:
    let defined_arg = scope[$(match.destination)]
    return err(fmt"{match.destination.location} {match.destination} is already defined {defined_arg.location}")

  if $(match.operand) notin scope:
    return err(fmt"{match.operand.location} {match.operand} is not defined in the scope")

  let match_operand_def = scope[$(match.operand)]
  for case_block in match.case_blocks:
    discard ? scope.resolve_expression(match_operand_def, case_block.value)
    let resolved_case_block = ? case_block.resolve_case_block(file, scope)
    resolved_case_blocks.add(resolved_case_block)

  # Note: Even though this is a for loop but there can only be at most 1 else block.
  for (index, else_block) in match.else_blocks.pairs:
    let resolved_else_block = ? else_block.resolve_else_block(file, scope)
    resolved_else_blocks.add(resolved_else_block)

  new_resolved_match(match, match.destination, match.operand,
      resolved_case_blocks, resolved_else_blocks)

proc resolve_function_step(step: FunctionStep, file: blocks.File,
    scope: var Table[string, ArgumentDefinition]): Result[ResolvedFunctionStep, string] =
  case step.kind:
  of FSK_STATEMENT:
    let resolved_statement = ? step.statement.resolve_statement(file, scope)
    return ok(new_resolved_function_step(resolved_statement))
  of FSK_MATCH:
    let resolved_match = ? step.match.resolve_match(file, scope)
    return ok(new_resolved_function_step(resolved_match))

proc resolve_function(module: Option[Module], function: Function,
    file: blocks.File): Result[ResolvedFunction, string] =
  var
    scope: Table[string, ArgumentDefinition]
    resolved_function_steps: seq[ResolvedFunctionStep]

  discard ? file.find_module(function.definition.return_type)
  for arg in function.arg_def_list:
    discard ? file.find_module(arg.arg_type)
    if $(arg.arg_name) in scope:
      let defined_arg = scope[$(arg.arg_name)]
      return err(fmt"{arg.location} {arg.arg_name} is already defined {defined_arg.location}")
    scope[$(arg.arg_name)] = arg

  for (index, step) in function.function_steps.pairs:
    let resolved_function_step = ? step.resolve_function_step(file, scope)
    resolved_function_steps.add(resolved_function_step)
    scope[$(resolved_function_step.destination)] = resolved_function_step.return_argument

  new_resolved_function(module, function, resolved_function_steps)

proc resolve_functions(file: blocks.File): Result[seq[ResolvedFunction], string] =
  var stack = @[new_external_function( ? file.find_start_function())]
  var visited_functions = init_hashset[ExternalFunction]()
  var resolved_functions: seq[ResolvedFunction]
  while stack.len > 0:
    let function = stack[^1]
    visited_functions.incl(function)
    stack.set_len(stack.len - 1)

    let resolved_function = ? resolve_function(function.module,
        function.function, file)
    resolved_functions.add(resolved_function)

    let new_functions = resolved_function.function_set.difference(visited_functions)
    stack.add(new_functions.to_seq)

  for function in file.functions:
    let ext_fn = new_external_function(function)
    if ext_fn notin visited_functions:
      echo fmt"Unused function: {function.location} {function.name}"
      discard ? resolve_function(none(Module), function, file)

  for module in file.user_modules:
    for function in ( ? module.functions):
      let ext_fn = new_external_function(module, function)
      if ext_fn notin visited_functions:
        echo fmt"Unused function: {function.location} {module.name}.{function.name}"
        discard ? resolve_function(some(module), function, file)
  ok(resolved_functions)

proc resolve_struct(struct: NamedStruct, scope: Table[string, NamedStruct],
    filename: string): Result[ResolvedStruct, string] =
  var field_map: Table[string, int]
  var field_offset: Table[string, uint]
  var offset: uint = 0

  for (index, field) in struct.fields.pairs:
    if $(field.arg_name) in field_map:
      let defined_field = struct.fields[field_map[$(field.arg_name)]]
      return err(fmt"{field.location} `{field.arg_name}` is already defined at {defined_field.location}")

    case $(field.arg_type):
    of "U8", "U16", "U32", "U64", "S8", "S16", "S32", "S64", "F32", "F64", "Pointer":
      discard
    else:
      if $(field.arg_type) notin scope:
        return err(fmt"{field.location} `{field.arg_type}` not defined in the {filename}")

    field_map[$(field.arg_name)] = index
    field_offset[$(field.arg_name)] = offset
    offset += field.byte_size()

  ok(new_resolved_struct(struct, offset, field_map, field_offset))

proc resolve_structs(file: blocks.File): Result[seq[ResolvedStruct], string] =
  var scope: Table[string, NamedStruct]
  var struct_list: seq[NamedStruct]
  for module in file.modules:
    let maybe_struct = module.named_struct()
    if maybe_struct.is_err: continue

    let struct = maybe_struct.get
    if $(struct.name) in scope:
      let defined_struct = scope[$(struct.name)]
      return err(fmt"{struct.location} `{struct.name}` is already defined at {defined_struct.location}")
    scope[$(struct.name)] = struct
    struct_list.add(struct)

  var resolved_structs: seq[ResolvedStruct]
  for struct in struct_list:
    resolved_structs.add( ? struct.resolve_struct(scope, file.name))
  return ok(resolved_structs)

proc resolve*(file: blocks.File): Result[ResolvedFile, string] =
  # TODO: Resolve modules
  let resolved_structs = ? file.resolve_structs()
  let resolved_functions = ? file.resolve_functions()
  ok(new_resolved_file(resolved_structs, resolved_functions))
