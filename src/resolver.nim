import results, tables, strformat, sequtils, parseutils, sets, options, strutils

import blocks

import resolved/arg; export arg
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

proc resolve_integer_literal(arg_type: Token, arg_value: Token): Result[void, string] =
  case $(arg_type):
  of "U8": ? safe_parse[uint8]($(arg_value))
  of "U16": ? safe_parse[uint16]($(arg_value))
  of "U32": ? safe_parse[uint32]($(arg_value))
  of "U64": ? safe_parse[uint64]($(arg_value))
  of "S8": ? safe_parse[int8]($(arg_value))
  of "S16": ? safe_parse[int16]($(arg_value))
  of "S32": ? safe_parse[int32]($(arg_value))
  of "S64": ? safe_parse[int64]($(arg_value))
  else: return err(fmt"{arg_value.location} arguments with builtin types can be passed as integer")
  ok()

proc resolve_float_literal(arg_type: Token, arg_value: Token): Result[void, string] =
  case $(arg_type):
  of "F32": ? safe_parse[float32]($(arg_value))
  of "F64": ? safe_parse[float64]($(arg_value))
  else: return err(fmt"{arg_value.location} arguments with builtin types can be passed as float")
  ok()

proc resolve_literal(arg_type: Token, arg_value: Token): Result[void, string] =
  case arg_value.kind:
  of TK_INTEGER: ? arg_type.resolve_integer_literal(arg_value)
  of TK_FLOAT: ? arg_type.resolve_float_literal(arg_value)
  else: return err(fmt"{arg_value.location} {arg_value} is not a literal")
  ok()

proc resolve_variable(arg_type: Token, arg_value: Token, scope: Table[string,
    ArgumentDefinition]): Result[void, string] =
  if $(arg_value) notin scope:
    return err(fmt"{arg_value.location} {arg_value} is not defined in the scope")
  if $(scope[$(arg_value)].arg_type) != $(arg_type):
    return err(fmt"{arg_value.location} expected {arg_type} but found {scope[$(arg_value)].arg_type}")
  ok()

proc resolve_argument(scope: Table[string, ArgumentDefinition],
    arg_type: Token, arg_value: Token): Result[void, string] =
  case arg_value.kind:
  of TK_ID: ? arg_type.resolve_variable(arg_value, scope)
  else: ? arg_type.resolve_literal(arg_value)
  ok()

proc resolve_union_pattern(file: blocks.File, scope: var Table[string,
    ArgumentDefinition], module_name: Token, pattern: Pattern): Result[
        ResolvedPattern, string] =
  let module = ? file.find_user_module(module_name)
  if not module.is_union:
    return err(fmt"{module.location} Module `{module.name}` is not a union")

  let
    union = module.union.get
    union_field = ? union.find_field(pattern.union.name)
    union_field_id = ? union.find_field_id(pattern.union.name)
  var
    field_name_table: Table[string, Token]
    field_value_table: Table[string, Token]

  var args: seq[(ArgumentDefinition, Token)]
  for (field_name, field_value) in pattern.union.fields:
    # Redefinition check inside the destructured pattern
    if $(field_name) in field_name_table:
      let predefined_location = field_name_table[$(field_name)].location
      return err(fmt"{field_name.location} field `{field_name}` is already defined at {predefined_location}")

    # Redefinition check inside the destructured pattern
    if $(field_value) in field_value_table:
      let predefined_location = field_value_table[$(field_value)].location
      return err(fmt"{field_value.location} field `{field_value}` is already defined at {predefined_location}")

    let field_type = ? union_field.find_field(field_name)
    field_name_table[$(field_name)] = field_name
    field_value_table[$(field_value)] = field_value

    # Redefinition check in the scope
    if $(field_value) in scope:
      let predefined_location = scope[$(field_value)].location
      return err(fmt"{field_value.location} field `{field_value}` is already defined at {predefined_location}")

    scope[$(field_value)] = new_argument_definition(field_type.arg_type, field_value)
    args.add((scope[$(field_value)], field_name))

  ok(new_resolved_pattern(module.name, pattern.union.name, union_field_id, args))

proc resolve_case_pattern(scope: var Table[string, ArgumentDefinition],
    file: blocks.File, arg_type: Token, pattern: Pattern): Result[
        ResolvedPattern, string] =
  case pattern.kind:
  of PK_LITERAL:
    ? arg_type.resolve_literal(pattern.literal)
    ok(new_resolved_pattern(pattern))
  of PK_UNION:
    file.resolve_union_pattern(scope, arg_type, pattern)

# matches individual function with function call
proc resolve_function_call_args(function_call: FunctionCall,
    function_def: FunctionDefinition, scope: Table[string,
    ArgumentDefinition]): Result[seq[ResolvedArgument], string] =
  if $(function_def.name) != $(function_call.name):
    return err(fmt"{function_call.location} expected function with name {function_call.name} but found {function_def.name}")
  if function_def.arg_def_list.len != function_call.arg_list.len:
    return err(fmt"{function_call.location} expected {function_def.arg_def_list.len} but found {function_call.arg_list.len}")

  var resolved_args: seq[ResolvedArgument]
  for (arg_def, arg_value) in zip(function_def.arg_def_list,
      function_call.arg_list):
    ? scope.resolve_argument(arg_def.arg_type, arg_value)
    resolved_args.add(new_resolved_argument(arg_def.arg_type, arg_value))
  ok(resolved_args)

proc resolve_function_call_args(function_call: FunctionCall, function_defs: seq[
    FunctionDefinition], scope: Table[string, ArgumentDefinition]): Result[(
        FunctionDefinition, seq[
    ResolvedArgument]), string] =
  for function_def in function_defs:
    let maybe_resolved_args = function_call.resolve_function_call_args(
        function_def, scope)
    if maybe_resolved_args.is_ok:
      return ok((function_def, maybe_resolved_args.get))

  return err(fmt"{function_call.location} Failed to find match function for function call {function_call.func_ref}")

proc resolve_local_function_call(function_call: FunctionCall,
    file: blocks.File, scope: Table[string, ArgumentDefinition]): Result[
        ResolvedFunctionCall, string] =
  let function_defs = file.functions.values.to_seq.map_it(it.definition)
  let (func_def, resolved_args) = ? function_call.resolve_function_call_args(
      function_defs, scope)
  ok(new_resolved_function_call(func_def, resolved_args))

proc resolve_builtin_function_call(function_call: FunctionCall,
    file: blocks.File, scope: Table[string, ArgumentDefinition]): Result[
        ResolvedFunctionCall, string] =
  let module = ? file.find_builtin_module(function_call.func_ref.module)
  let (func_def, resolved_args) = ? function_call.resolve_function_call_args(
      module.functions, scope)
  ok(new_resolved_function_call(module, func_def, resolved_args))

proc resolve_user_function_call(function_call: FunctionCall,
    file: blocks.File, scope: Table[string, ArgumentDefinition]): Result[
        ResolvedFunctionCall, string] =
  let module = ? file.find_user_module(function_call.func_ref.module)
  let function_defs = module.functions.map_it(it.definition)
  let (func_def, resolved_args) = ? function_call.resolve_function_call_args(
      function_defs, scope)
  ok(new_resolved_user_function_call(module, func_def, resolved_args))

proc resolve_module_function_call(function_call: FunctionCall,
    file: blocks.File, scope: Table[string, ArgumentDefinition]): Result[
        ResolvedFunctionCall, string] =
  let maybe_builtin_function_call = function_call.resolve_builtin_function_call(
        file, scope)
  if maybe_builtin_function_call.is_ok: return maybe_builtin_function_call

  let maybe_user_function_call = function_call.resolve_user_function_call(
      file, scope)
  if maybe_user_function_call.is_ok: return maybe_user_function_call

  return err(fmt"{function_call.location} `{function_call.name}` failed to find matching module function in the file {file.name}")

proc resolve_function_call(function_call: FunctionCall, file: blocks.File,
    scope: Table[string, ArgumentDefinition]): Result[ResolvedFunctionCall, string] =
  case function_call.func_ref.kind:
  of FRK_LOCAL: function_call.resolve_local_function_call(file, scope)
  of FRK_MODULE: function_call.resolve_module_function_call(file, scope)

proc resolve_struct_init(struct_init: StructInit, file: blocks.File,
    scope: Table[string, ArgumentDefinition]): Result[ResolvedStructInit, string] =
  let module = ? file.find_user_module(struct_init.struct)
  if not module.is_struct:
    return err(fmt"{module.location} Module `{module.name}` is not a struct")

  let struct = module.struct.get
  var field_name_table: Table[string, ResolvedArgument]
  for (field_name, field_value) in struct_init.fields:
    if $(field_name) in field_name_table:
      return err(fmt"{field_name.location} {field_name} is already present in the initializer")
    let field = ? struct.find_field(field_name)
    ? scope.resolve_argument(field.arg_type, field_value)
    field_name_table[$(field_name)] = new_resolved_argument(field.arg_type, field_value)

  let resolved_fields = struct.fields.values.to_seq.map_it(field_name_table[$(it.arg_name)])
  let resolved_struct_init = new_resolved_struct_init(module, resolved_fields)
  ok(resolved_struct_init)

proc resolve_union_init(union_init: UnionInit, file: blocks.File,
    scope: Table[string, ArgumentDefinition]): Result[ResolvedUnionInit, string] =
  let module = ? file.find_user_module(union_init.name)
  if not module.is_union:
    return err(fmt"{module.location} Module `{module.name}` is not a union")

  let union = module.union.get
  let union_field = ? union.find_field(union_init.field_name)

  var field_name_table: Table[string, ResolvedArgument]
  for (field_name, field_value) in union_init.union_fields:
    if $(field_name) in field_name_table:
      return err(fmt"{field_name.location} {field_name} is already present in the initializer")
    let field = ? union_field.find_field(field_name)
    ? scope.resolve_argument(field.arg_type, field_value)
    field_name_table[$(field_name)] = new_resolved_argument(field.arg_type, field_value)

  let resolved_fields = union_field.fields.values.to_seq.map_it(
      field_name_table[$(it.arg_name)])
  let resolved_union_init = new_resolved_union_init(module, union_field, resolved_fields)
  ok(resolved_union_init)

proc resolve_struct_getter(struct_getter: StructGetter, file: blocks.File,
    scope: Table[string, ArgumentDefinition]): Result[ResolvedStructGetter, string] =
  let struct_var = struct_getter.struct

  if $(struct_var) notin scope:
    return err(fmt"{struct_var.location} {struct_var} is not defined in the scope")

  let module = ? file.find_user_module(scope[$(struct_var)].arg_type)
  if not module.is_struct:
    return err(fmt"{module.location} Module `{module.name}` is not a struct")

  let struct = module.struct.get
  let field = ? struct.find_field(struct_getter.field)
  let resolved_struct_getter = new_resolved_struct_getter(module, field, struct_var)
  ok(resolved_struct_getter)

proc resolved_expression(expression: Expression, file: blocks.File,
    scope: Table[string, ArgumentDefinition]): Result[ResolvedExpression, string] =
  case expression.kind:
  of EK_VARIABLE:
    if $(expression.variable) notin scope:
      return err(fmt"{expression.variable.location} {expression.variable} is not defined in the scope")
    ok(new_resolved_expression(scope[$(expression.variable)]))
  of EK_STRUCT_INIT:
    let resolved_struct_init = ? expression.struct_init.resolve_struct_init(
        file, scope)
    ok(new_resolved_expression(resolved_struct_init))
  of EK_STRUCT_GETTER:
    let resolved_struct_getter = ? expression.struct_getter.resolve_struct_getter(
        file, scope)
    ok(new_resolved_expression(resolved_struct_getter))
  of EK_FUNCTION_CALL:
    let resolved_function_call = ? expression.function_call.resolve_function_call(
        file, scope)
    ok(new_resolved_expression(resolved_function_call))
  of EK_LITERAL_INIT:
    ? expression.literal_init.arg_type.resolve_literal(
        expression.literal_init.arg_value)
    ok(new_resolved_expression(expression.literal_init))
  of EK_UNION_INIT:
    let resolved_union_init = ? expression.union_init.resolve_union_init(file, scope)
    ok(new_resolved_expression(resolved_union_init))

proc resolve_statement(statement: Statement, file: blocks.File, scope: Table[
    string, ArgumentDefinition], temp_var_count: var uint): Result[
        ResolvedStatement, string] =
  case statement.kind:
  of SK_ASSIGNMENT:
    if $(statement.destination) in scope:
      let defined_arg = scope[$(statement.destination)]
      return err(fmt"{statement.destination.location} {statement.destination} is already defined {defined_arg.location}")

    let resolved_expression = ? statement.expression.resolved_expression(file, scope)
    ok(new_resolved_statement(statement.destination, resolved_expression))
  of SK_EXPRESSION:
    # assign the expresssion value to a temporary variable injected by the compiler
    let assignment = statement.set_destination(fmt"__asl_temp_var_{temp_var_count}__")
    temp_var_count += 1
    let resolved_expression = ? assignment.expression.resolved_expression(file, scope)
    ok(new_resolved_statement(assignment.destination, resolved_expression))

proc resolve_case_block(case_block: Case, file: blocks.File,
    parent_scope: Table[string, ArgumentDefinition],
        operand: ArgumentDefinition,
    temp_var_count: var uint): Result[ResolvedCase, string] =
  var resolved_statements: seq[ResolvedStatement]
  # copy current function scope to the case scope to avoid non local argument name conflicts
  var scope = parent_scope
  let resolved_pattern = ? scope.resolve_case_pattern(file, operand.arg_type,
      case_block.pattern)
  for (index, statement) in case_block.statements.pairs:
    let resolved_statement = ? statement.resolve_statement(file, scope, temp_var_count)
    resolved_statements.add(resolved_statement)
    scope[$(resolved_statement.destination)] = resolved_statement.return_argument

  return ok(new_resolved_case(resolved_pattern, operand.arg_name,
      resolved_statements))

proc resolve_else_block(else_block: Else, file: blocks.File,
    parent_scope: Table[string, ArgumentDefinition],
        temp_var_count: var uint): Result[ResolvedElse, string] =
  var resolved_statements: seq[ResolvedStatement]
  # copy current function scope to the else scope to avoid non local argument name conflicts
  var scope = parent_scope
  for (index, statement) in else_block.statements.pairs:
    let resolved_statement = ? statement.resolve_statement(file, scope, temp_var_count)
    resolved_statements.add(resolved_statement)
    scope[$(resolved_statement.destination)] = resolved_statement.return_argument

  return ok(new_resolved_else(resolved_statements))

proc resolve_match(match: Match, file: blocks.File, scope: var Table[string,
    ArgumentDefinition], temp_var_count: var uint): Result[ResolvedMatch, string] =
  var resolved_case_blocks: seq[ResolvedCase]
  var resolved_else_blocks: seq[ResolvedElse]
  if $(match.destination) in scope:
    let defined_arg = scope[$(match.destination)]
    return err(fmt"{match.destination.location} {match.destination} is already defined {defined_arg.location}")

  if $(match.operand) notin scope:
    return err(fmt"{match.operand.location} {match.operand} is not defined in the scope")

  let match_operand_def = scope[$(match.operand)]

  case $(match_operand_def.arg_type):
  of "S8", "S16", "S32", "S64", "U8", "U16", "U32", "U64": discard
  of "F32", "F64":
    return err(fmt"{match.operand.location} `match` does not support floating point value `{match.operand}`")
  else:
    let module = ? file.find_user_module(match_operand_def.arg_type)
    if not module.is_union:
      return err(fmt"{match.operand.location} `match` only supports integers/union values `{match.operand}`")

  for case_block in match.case_blocks:
    let resolved_case_block = ? case_block.resolve_case_block(file, scope,
        match_operand_def, temp_var_count)
    resolved_case_blocks.add(resolved_case_block)

  # Note: Even though this is a for loop but there can only be at most 1 else block.
  for (index, else_block) in match.else_blocks.pairs:
    let resolved_else_block = ? else_block.resolve_else_block(file, scope, temp_var_count)
    resolved_else_blocks.add(resolved_else_block)

  let return_type = resolved_case_blocks[0].return_argument.arg_type
  let case_return_args = resolved_case_blocks.map_it(it.return_argument)
  let else_return_args = resolved_else_blocks.map_it(it.return_argument)
  for return_arg in (case_return_args & else_return_args):
    if $(return_type) != $(return_arg.arg_type):
      return err(fmt"{return_arg.location} block is expected to return {return_type} but found {return_arg.arg_type}")

  let return_argument = new_argument_definition(return_type, match.destination)
  ok(new_resolved_match(match, match.destination, match_operand_def,
      resolved_case_blocks, resolved_else_blocks, return_argument))

proc resolve_function_step(step: FunctionStep, file: blocks.File,
    scope: var Table[string, ArgumentDefinition],
        temp_var_count: var uint): Result[ResolvedFunctionStep, string] =
  case step.kind:
  of FSK_STATEMENT:
    let resolved_statement = ? step.statement.resolve_statement(file, scope, temp_var_count)
    ok(new_resolved_function_step(resolved_statement))
  of FSK_MATCH:
    let resolved_match = ? step.match.resolve_match(file, scope, temp_var_count)
    ok(new_resolved_function_step(resolved_match))

proc resolve_function(function_ref: ResolvedFunctionRef,
    file: blocks.File): Result[ResolvedFunction, string] =
  let function =
    case function_ref.kind:
    of RFRK_MODULE:
      let module = ? file.find_user_module(function_ref.module_name)
      ? module.find_function(function_ref.function_def)
    of RFRK_FUNCTION:
      ? file.find_function(function_ref.function_def)

  var
    temp_var_count: uint = 0
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
    let resolved_function_step = ? step.resolve_function_step(file, scope, temp_var_count)
    resolved_function_steps.add(resolved_function_step)
    scope[$(resolved_function_step.destination)] = resolved_function_step.return_argument

  new_resolved_function(function_ref, function, resolved_function_steps)

proc resolve_functions(file: blocks.File): Result[seq[ResolvedFunction], string] =
  let main_function = ? file.find_start_function()
  var stack = @[new_resolved_function_ref(main_function.definition)]
  var visited_functions = init_hashset[ResolvedFunctionRef]()
  var resolved_functions: seq[ResolvedFunction]
  while stack.len > 0:
    let function = stack[^1]
    visited_functions.incl(function)
    stack.set_len(stack.len - 1)

    let resolved_function = ? resolve_function(function, file)
    resolved_functions.add(resolved_function)

    let new_functions = resolved_function.function_refs.difference(visited_functions)
    stack.add(new_functions.to_seq)

  for function in file.functions.values:
    let func_ref = new_resolved_function_ref(function.definition)
    if func_ref notin visited_functions:
      echo fmt"Unused function: {function.location} {function.name}"
      discard ? resolve_function(func_ref, file)

  for module in file.user_modules.values:
    for function in module.functions:
      let func_ref = new_resolved_function_ref(module,
          function.definition)
      if func_ref notin visited_functions:
        echo fmt"Unused function: {function.location} {module.name}.{function.name}"
        discard ? resolve_function(func_ref, file)
  ok(resolved_functions)

proc resolve_struct(module: UserModule, scope: Table[string,
    UserModule], filename: string): Result[ResolvedStruct, string] =
  var field_offset: Table[string, uint]
  var offset: uint = 0

  for field in module.struct.get.fields.values:
    case $(field.arg_type):
    of "U8", "U16", "U32", "U64", "S8", "S16", "S32", "S64", "F32", "F64", "Pointer":
      discard
    else:
      if $(field.arg_type) notin scope:
        return err(fmt"{field.location} `{field.arg_type}` not defined in the {filename}")
    field_offset[$(field.arg_name)] = offset
    offset += field.byte_size()

  ok(new_resolved_struct(module, offset, field_offset))

proc resolve_structs(file: blocks.File, scope: Table[string,
    UserModule]): Result[seq[ResolvedStruct], string] =
  var resolved_structs: seq[ResolvedStruct]
  for module in file.user_modules.values:
    if module.is_struct:
      resolved_structs.add( ? module.resolve_struct(scope, file.name))
  return ok(resolved_structs)

proc resolve_union(module: UserModule, scope: Table[string,
    UserModule], filename: string): Result[ResolvedUnion, string] =
  ok(new_resolved_union(module))

proc resolve_unions(file: blocks.File, scope: Table[string,
    UserModule]): Result[seq[ResolvedUnion], string] =
  var resolved_unions: seq[ResolvedUnion]
  for module in file.user_modules.values:
    if module.is_union:
      resolved_unions.add( ? module.resolve_union(scope, file.name))
  return ok(resolved_unions)

proc resolve*(file: blocks.File): Result[ResolvedFile, string] =
  var scope: Table[string, UserModule]
  for module in file.user_modules.values:
    if module.is_struct or module.is_union:
      if $(module.name) in scope:
        let defined_struct = scope[$(module.name)]
        return err(fmt"{module.location} `{module.name}` is already defined at {defined_struct.location}")
      scope[$(module.name)] = module

  let resolved_structs = ? file.resolve_structs(scope)
  let resolved_unions = ? file.resolve_unions(scope)
  let resolved_functions = ? file.resolve_functions()
  ok(new_resolved_file(resolved_structs, resolved_unions, resolved_functions))
