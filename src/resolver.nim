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
import resolved/union; export union
import resolved/file; export file

proc safe_parse*[T](input: string): Result[T, string] =
  when T is SomeSignedInt:
    var temp: BiggestInt
    let code = parseBiggestInt(input, temp)
    if code == 0 or code != input.len:
      return err("Failed to parse signed int from: " & input)
    if temp < T.low.BiggestInt or temp > T.high.BiggestInt:
      return err("Overflow: Value out of range for type " & $T)
    ok(T(temp))
  elif T is SomeUnsignedInt:
    var temp: BiggestUInt
    let code = parseBiggestUInt(input, temp)
    if code == 0 or code != input.len:
      return err("Failed to parse unsigned int from: " & input)
    if temp < T.low.BiggestUInt or temp > T.high.BiggestUInt:
      return err("Overflow: Value out of range for type " & $T)
    ok(T(temp))
  elif T is SomeFloat:
    var temp: BiggestFloat
    let code = parseBiggestFloat(input, temp)
    if code == 0 or code != input.len:
      return err("Failed to parse float from: " & input)
    let casted = T(temp)
    if BiggestFloat(casted) != temp:
      return err("Precision loss when converting to " & $T)
    ok(T(temp))
  else:
    err("safe_parse only supports signed/unsigned integers and floating-point types")

proc resolve_integer_literal(module: BuiltinModule, value: Token): Result[
    ResolvedLiteral, string] =
  case $(module.name):
  of "U8": discard ? safe_parse[uint8]($(value))
  of "U16": discard ? safe_parse[uint16]($(value))
  of "U32": discard ? safe_parse[uint32]($(value))
  of "U64": discard ? safe_parse[uint64]($(value))
  of "S8": discard ? safe_parse[int8]($(value))
  of "S16": discard ? safe_parse[int16]($(value))
  of "S32": discard ? safe_parse[int32]($(value))
  of "S64": discard ? safe_parse[int64]($(value))
  else: return err(fmt"{value.location} arguments with builtin types can be passed as integer")
  ok(new_resolved_integer_literal(module, value))

proc resolve_float_literal(module: BuiltinModule, value: Token): Result[
    ResolvedLiteral, string] =
  case $(module.name):
  of "F32": discard ? safe_parse[float32]($(value))
  of "F64": discard ? safe_parse[float64]($(value))
  else: return err(fmt"{value.location} arguments with builtin types can be passed as float")
  ok(new_resolved_float_literal(module, value))

proc resolve_literal(module: BuiltinModule,
    value: Token): Result[ResolvedLiteral, string] =
  case value.kind:
  of TK_INTEGER: module.resolve_integer_literal(value)
  of TK_FLOAT: module.resolve_float_literal(value)
  else: err(fmt"{value.location} {value} is not a literal")

proc resolve_variable(scope: Table[string, ArgumentDefinition],
    name: Token): Result[ResolvedVariable, string] =
  if $(name) notin scope:
    return err(fmt"{name.location} {name} is not defined in the scope")
  ok(new_resolved_variable(scope[$(name)]))

proc resolve_argument(file: blocks.File, scope: Table[string,
    ArgumentDefinition], arg_type: Token, arg_value: Token): Result[
    ResolvedArgument, string] =
  let module = ? file.find_module(arg_type)
  case arg_value.kind:
  of TK_ID:
    let resolved_variable = ? scope.resolve_variable(arg_value)
    if $(module.name) == $(arg_type): ok(new_resolved_argument(resolved_variable))
    else: err(fmt"{arg_value.location} expected {arg_type} but found {resolved_variable.typ}")
  else:
    case module.kind:
    of MK_BUILTIN:
      let resolved_literal = ? module.builtin_module.resolve_literal(arg_value)
      ok(new_resolved_argument(resolved_literal))
    of MK_USER:
      err(fmt"{arg_type.location} Module `{arg_type}` is a user module and therefore does not support literals")

proc resolve_struct_init(file: blocks.File, scope: Table[string,
    ArgumentDefinition], struct_init: StructInit): Result[ResolvedStructInit, string] =
  let module = ? file.find_module(struct_init.struct)
  case module.kind:
  of MK_USER:
    case module.user_module.kind:
    of UMK_STRUCT:
      let struct = module.user_module.struct
      var field_name_table: Table[string, ResolvedArgument]
      for (field_name, field_value) in struct_init.fields:
        if $(field_name) in field_name_table:
          return err(fmt"{field_name.location} {field_name} is already present in the initializer")
        let field = ? struct.find_field(field_name)
        field_name_table[$(field_name)] = ? file.resolve_argument(scope,
            field.typ, field_value)

      let resolved_fields = struct.fields.values.to_seq.map_it(field_name_table[
          $(it.name)])
      let resolved_struct_init = new_resolved_struct_init(module.user_module, resolved_fields)
      ok(resolved_struct_init)
    else: err(fmt"Builtin module `{module.name}` is can not be a struct")
  of MK_BUILTIN: err(fmt"Builtin module `{module.name}` is can not be a struct")

proc resolve_union_init(file: blocks.File, scope: Table[string,
    ArgumentDefinition], union_init: UnionInit): Result[ResolvedUnionInit, string] =
  let module = ? file.find_module(union_init.name)
  case module.kind:
  of MK_USER:
    case module.user_module.kind:
    of UMK_UNION:
      let union_field = ? module.user_module.union.find_field(
          union_init.field_name)
      var field_name_table: Table[string, ResolvedArgument]
      for (field_name, field_value) in union_init.union_fields:
        if $(field_name) in field_name_table:
          return err(fmt"{field_name.location} {field_name} is already present in the initializer")
        let field = ? union_field.find_field(field_name)
        field_name_table[$(field_name)] = ? file.resolve_argument(scope,
            field.typ, field_value)

      let resolved_fields = union_field.fields.values.to_seq.map_it(
          field_name_table[$(it.name)])
      let resolved_union_init = new_resolved_union_init(module.user_module,
          union_field, resolved_fields)
      ok(resolved_union_init)
    else: err(fmt"Builtin module `{module.name}` is can not be a struct")
  of MK_BUILTIN: err(fmt"Builtin module `{module.name}` is can not be a struct")

proc resolve_struct_getter(file: blocks.File, scope: Table[string,
    ArgumentDefinition], struct_getter: StructGetter): Result[
    ResolvedStructGetter, string] =
  let struct_var = struct_getter.struct

  if $(struct_var) notin scope:
    return err(fmt"{struct_var.location} {struct_var} is not defined in the scope")

  let module = ? file.find_module(scope[$(struct_var)].typ)
  case module.kind:
  of MK_BUILTIN: err(fmt"Builtin module `{module.name}` is can not be a struct")
  of MK_USER:
    let field = ? module.user_module.struct.find_field(struct_getter.field)
    ok(new_resolved_struct_getter(module.user_module, field, struct_var))

# matches individual function with function call
proc resolve_function_call_args(file: blocks.File, scope: Table[string,
    ArgumentDefinition], function_call: FunctionCall,
    function_def: FunctionDefinition): Result[seq[ResolvedArgument], string] =
  if $(function_def.name) != $(function_call.name):
    return err(fmt"{function_call.location} expected function with name {function_call.name} but found {function_def.name}")
  if function_def.arg_def_list.len != function_call.arg_list.len:
    return err(fmt"{function_call.location} expected {function_def.arg_def_list.len} but found {function_call.arg_list.len}")

  var resolved_args: seq[ResolvedArgument]
  for (arg_def, arg_value) in zip(function_def.arg_def_list,
      function_call.arg_list):
    let resolved_arg = ? file.resolve_argument(scope, arg_def.typ, arg_value)
    resolved_args.add(resolved_arg)
  ok(resolved_args)

proc resolve_function_call_args(file: blocks.File, scope: Table[string,
    ArgumentDefinition], function_call: FunctionCall, function_defs: seq[
    FunctionDefinition]): Result[(FunctionDefinition, seq[ResolvedArgument]), string] =
  for function_def in function_defs:
    let maybe_resolved_args = file.resolve_function_call_args(scope,
        function_call, function_def)
    if maybe_resolved_args.is_ok:
      return ok((function_def, maybe_resolved_args.get))

  return err(fmt"{function_call.location} Failed to find match function for function call {function_call.func_ref}")

proc resolve_builtin_function_call(file: blocks.File, scope: Table[string,
    ArgumentDefinition], module: BuiltinModule,
        function_call: FunctionCall): Result[ResolvedFunctionCall, string] =
  let (func_def, resolved_args) = ? file.resolve_function_call_args(scope,
      function_call, module.functions)
  ok(new_resolved_function_call(module, func_def, resolved_args))

proc resolve_user_function_call(file: blocks.File, scope: Table[string,
    ArgumentDefinition], module: UserModule, function_call: FunctionCall,
    ): Result[ResolvedFunctionCall, string] =
  let function_defs = module.functions.values.to_seq.map_it(it.definition)
  let (func_def, resolved_args) = ? file.resolve_function_call_args(scope,
      function_call, function_defs)
  ok(new_resolved_function_call(module, func_def, resolved_args))

proc resolve_module_function_call(file: blocks.File, scope: Table[string,
    ArgumentDefinition], function_call: FunctionCall): Result[
    ResolvedFunctionCall, string] =
  let module = ? file.find_module(function_call.func_ref.module)
  case module.kind:
  of MK_BUILTIN:
    file.resolve_builtin_function_call(scope, module.builtin_module, function_call)
  of MK_USER:
    file.resolve_user_function_call(scope, module.user_module, function_call)

proc resolve_local_function_call(file: blocks.File, scope: Table[string,
    ArgumentDefinition], function_call: FunctionCall): Result[
    ResolvedFunctionCall, string] =
  let function_defs = file.functions.values.to_seq.map_it(it.definition)
  let (func_def, resolved_args) = ? file.resolve_function_call_args(
      scope, function_call, function_defs)
  ok(new_resolved_function_call(func_def, resolved_args))

proc resolve_function_call(file: blocks.File, scope: Table[string,
    ArgumentDefinition], function_call: FunctionCall): Result[
    ResolvedFunctionCall, string] =
  case function_call.func_ref.kind:
  of FRK_MODULE: file.resolve_module_function_call(scope, function_call)
  of FRK_LOCAL: file.resolve_local_function_call(scope, function_call)

proc resolved_expression(file: blocks.File, scope: Table[string,
    ArgumentDefinition], expression: Expression): Result[ResolvedExpression, string] =
  case expression.kind:
  of EK_VARIABLE:
    ok(new_resolved_expression( ? scope.resolve_variable(expression.variable)))
  of EK_STRUCT_INIT:
    let resolved_struct_init = ? file.resolve_struct_init(
        scope, expression.struct_init)
    ok(new_resolved_expression(resolved_struct_init))
  of EK_STRUCT_GETTER:
    let resolved_struct_getter = ? file.resolve_struct_getter(scope,
        expression.struct_getter)
    ok(new_resolved_expression(resolved_struct_getter))
  of EK_FUNCTION_CALL:
    let resolved_function_call = ? file.resolve_function_call(scope,
        expression.function_call)
    ok(new_resolved_expression(resolved_function_call))
  of EK_LITERAL_INIT:
    let module = ? file.find_module(expression.literal_init.arg_type)
    case module.kind:
    of MK_BUILTIN:
      let resolved_literal = ? module.builtin_module.resolve_literal(
          expression.literal_init.arg_value)
      ok(new_resolved_expression(resolved_literal))
    of MK_USER:
      err(fmt"{expression.literal_init.arg_type.location} Module `{expression.literal_init.arg_type}` is a user module and therefore does not support literals")
  of EK_UNION_INIT:
    let resolved_union_init = ? file.resolve_union_init(scope,
        expression.union_init)
    ok(new_resolved_expression(resolved_union_init))

proc resolve_statement(file: blocks.File, scope: Table[string,
    ArgumentDefinition], temp_var_count: var uint,
    statement: Statement): Result[ResolvedStatement, string] =
  case statement.kind:
  of SK_ASSIGNMENT:
    if $(statement.destination) in scope:
      let defined_arg = scope[$(statement.destination)]
      return err(fmt"{statement.destination.location} {statement.destination} is already defined {defined_arg.location}")

    let resolved_expression = ? file.resolved_expression(scope,
        statement.expression)
    ok(new_resolved_statement(statement.destination, resolved_expression))
  of SK_EXPRESSION:
    # assign the expresssion value to a temporary variable injected by the compiler
    let assignment = statement.set_destination(fmt"__asl_temp_var_{temp_var_count}__")
    temp_var_count += 1
    let resolved_expression = ? file.resolved_expression(scope,
        assignment.expression)
    ok(new_resolved_statement(assignment.destination, resolved_expression))

proc resolve_union_pattern(file: blocks.File, scope: Table[string,
    ArgumentDefinition], module: UserModule, union: Union,
    pattern: Pattern): Result[ResolvedPattern, string] =
  let union_field_id = ? union.find_field_id(pattern.union.name)
  let union_field = union.fields[union_field_id]

  var field_name_table: Table[string, Token]
  var field_value_table: Table[string, Token]

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

    let arg = new_argument_definition(field_type.typ, field_value)
    args.add((arg, field_name))

  ok(new_resolved_pattern(module.name, pattern.union.name, union_field_id, args))

proc resolve_case_pattern(file: blocks.File, scope: var Table[string,
    ArgumentDefinition], arg_type: Token, pattern: Pattern): Result[
    ResolvedPattern, string] =
  let module = ? file.find_module(arg_type)
  case pattern.kind:
  of PK_LITERAL:
    case module.kind:
    of MK_BUILTIN:
      let literal = ? module.builtin_module.resolve_literal(pattern.literal)
      ok(new_resolved_pattern(literal))
    of MK_USER:
      err(fmt"{arg_type.location} Module `{arg_type}` is a user module and therefore does not support literals")
  of PK_UNION:
    case module.kind:
    of MK_USER:
      case module.user_module.kind:
      of UMK_UNION: file.resolve_union_pattern(scope, module.user_module,
          module.user_module.union, pattern)
      else: err(fmt"{module.location} Module `{module.name}` is not a union")
    of MK_BUILTIN: err(fmt"Builtin module `{module.name}` is can not be a struct")

proc resolve_case_block(file: blocks.File, parent_scope: Table[string,
    ArgumentDefinition], operand: ArgumentDefinition, temp_var_count: var uint,
    case_block: Case): Result[ResolvedCase, string] =
  var resolved_statements: seq[ResolvedStatement]
  # copy current function scope to the case scope to avoid non local argument name conflicts
  var scope = parent_scope
  let resolved_pattern = ? file.resolve_case_pattern(scope, operand.typ,
      case_block.pattern)
  for arg in resolved_pattern.args:
    scope[$(arg.name)] = arg
  for (index, statement) in case_block.statements.pairs:
    let resolved_statement = ? file.resolve_statement(scope, temp_var_count, statement)
    resolved_statements.add(resolved_statement)
    scope[$(resolved_statement.destination)] = resolved_statement.return_argument

  return ok(new_resolved_case(resolved_pattern, operand.name,
      resolved_statements))

proc resolve_else_block(file: blocks.File, parent_scope: Table[string,
    ArgumentDefinition], temp_var_count: var uint, else_block: Else): Result[
    ResolvedElse, string] =
  var resolved_statements: seq[ResolvedStatement]
  # copy current function scope to the else scope to avoid non local argument name conflicts
  var scope = parent_scope
  for (index, statement) in else_block.statements.pairs:
    let resolved_statement = ? file.resolve_statement(scope, temp_var_count, statement)
    resolved_statements.add(resolved_statement)
    scope[$(resolved_statement.destination)] = resolved_statement.return_argument

  return ok(new_resolved_else(resolved_statements))

proc resolve_match_operand(file: blocks.File, scope: Table[string,
    ArgumentDefinition], operand: Token): Result[void, string] =
  if $(operand) notin scope:
    return err(fmt"{operand.location} `{operand}` is not defined in the scope")

  let operand_type = scope[$(operand)].typ
  let module = ? file.find_module(operand_type)
  case module.kind:
  of MK_BUILTIN:
    case $(operand_type):
    of "S8", "S16", "S32", "S64", "U8", "U16", "U32", "U64": ok()
    else: err(fmt"{operand.location} `match` does not support floating point value `{operand}`")
  of MK_USER:
    case module.user_module.kind:
    of UMK_UNION: ok()
    of UMK_STRUCT: err(fmt"{operand.location} `match` does not support structs `{operand}`")
    of UMK_DEFAULT: err(fmt"{operand.location} `match` does not support modules `{operand}`")

proc resolve_match(file: blocks.File, scope: Table[string,
    ArgumentDefinition], temp_var_count: var uint, match: Match): Result[
        ResolvedMatch, string] =
  # TODO: Detect unreachable case blocks by analyzing the case patterns.
  var resolved_case_blocks: seq[ResolvedCase]
  var resolved_else_blocks: seq[ResolvedElse]
  if $(match.destination) in scope:
    let defined_arg = scope[$(match.destination)]
    return err(fmt"{match.destination.location} {match.destination} is already defined {defined_arg.location}")

  ? file.resolve_match_operand(scope, match.operand)

  let match_operand_def = scope[$(match.operand)]
  for case_block in match.case_blocks:
    let resolved_case_block = ? file.resolve_case_block(scope,
        match_operand_def, temp_var_count, case_block)
    resolved_case_blocks.add(resolved_case_block)

  # Note: Even though this is a for loop but there can only be at most 1 else block.
  for else_block in match.else_blocks:
    let resolved_else_block = ? file.resolve_else_block(scope, temp_var_count, else_block)
    resolved_else_blocks.add(resolved_else_block)

  let return_type = resolved_case_blocks[0].return_argument.typ
  let case_return_args = resolved_case_blocks.map_it(it.return_argument)
  let else_return_args = resolved_else_blocks.map_it(it.return_argument)
  for return_arg in (case_return_args & else_return_args):
    if $(return_type) != $(return_arg.typ):
      return err(fmt"{return_arg.location} block is expected to return {return_type} but found {return_arg.typ}")

  let return_argument = new_argument_definition(return_type, match.destination)
  ok(new_resolved_match(match, match.destination, match_operand_def,
      resolved_case_blocks, resolved_else_blocks, return_argument))

proc resolve_match_new(file: blocks.File, scope: Table[string,
    ArgumentDefinition], temp_var_count: var uint, match: Match): Result[void, string] =
  if $(match.operand) notin scope:
    return err(fmt"{match.operand.location} variable `{match.operand}` is not defined in scope")

  let operand_def = scope[$(match.operand)]
  let operand_module = ? file.find_module(operand_def.typ)

  case operand_module.kind:
  of MK_USER:
    case operand_module.user_module.kind:
    of UMK_UNION: ok()
    of UMK_STRUCT: err(fmt"{match.operand.location} `match` does not support struct value `{match.operand}`")
    of UMK_DEFAULT: err("MATCH RESOLUTION: UNREACHABLE")
  of MK_BUILTIN:
    case $(operand_module.builtin_module):
    of "S8", "S16", "S32", "S64":
      # 1. There must always be an else block
      if match.else_blocks.len == 0:
        return err(fmt"{match.operand.location} matching integer literal requires the `else` block")

      var intset: Table[int64, Token]
      for case_block in match.case_blocks:
        # 2. All the case block patterns can be cast to the respective integer module
        case case_block.pattern.kind:
        of PK_LITERAL:
          discard ? operand_module.builtin_module.resolve_integer_literal(
              case_block.pattern.literal)
          # 3. All case pattern contain unique values
          let intval = ? safe_parse[int64]($(case_block.pattern.literal))
          if intval in intset:
            let predefined_location = intset[intval].location
            return err(fmt"{case_block.pattern.location} is unreachable due to predefined duplicate case block `{predefined_location}`")
          intset[intval] = case_block.pattern.literal
        else:
          return err(fmt"{case_block.pattern.location} expected an integer literal of type `{operand_module.builtin_module.name}`")
      ok()
    of "U8", "U16", "U32", "U64":
      # 1. There must always be an else block
      if match.else_blocks.len == 0:
        return err(fmt"{match.operand.location} matching integer literal requires the `else` block")

      var uintset: Table[uint64, Token]
      for case_block in match.case_blocks:
        # 2. All the case block patterns can be cast to the respective integer module
        case case_block.pattern.kind:
        of PK_LITERAL:
          discard ? operand_module.builtin_module.resolve_integer_literal(
              case_block.pattern.literal)
          # 3. All case pattern contain unique values
          let uintval = ? safe_parse[uint64]($(case_block.pattern.literal))
          if uintval in uintset:
            let predefined_location = uintset[uintval].location
            return err(fmt"{case_block.pattern.location} is unreachable due to predefined duplicate case block `{predefined_location}`")
          uintset[uintval] = case_block.pattern.literal
        else:
          return err(fmt"{case_block.pattern.location} expected an integer literal of type `{operand_module.builtin_module.name}`")
      ok()
    of "F32", "F64": err(fmt"{match.operand.location} `match` does not support floating point value `{match.operand}`")
    else: err("MATCH RESOLUTION: UNREACHABLE")

proc resolve_function_step(file: blocks.File, scope: Table[
    string, ArgumentDefinition], temp_var_count: var uint,
        step: FunctionStep): Result[
    ResolvedFunctionStep, string] =
  case step.kind:
  of FSK_STATEMENT:
    let resolved_statement = ? file.resolve_statement(scope, temp_var_count,
        step.statement)
    ok(new_resolved_function_step(resolved_statement))
  of FSK_MATCH:
    let resolved_match = ? file.resolve_match(scope, temp_var_count, step.match)
    ? file.resolve_match_new(scope, temp_var_count, step.match)
    ok(new_resolved_function_step(resolved_match))

proc resolve_function(file: blocks.File,
    function_ref: ResolvedFunctionRef): Result[ResolvedFunction, string] =
  let function =
    case function_ref.kind:
    of RFRK_MODULE:
      let module = ? file.find_module(function_ref.module_name)
      case module.kind:
      of MK_BUILTIN:
        return err(fmt"Builtin module `{module.name}` does not require resolution.")
      of MK_USER:
        ? module.user_module.find_function(function_ref.function_def)
    of RFRK_FUNCTION:
      ? file.find_function(function_ref.function_def)

  var
    temp_var_count: uint = 0
    scope: Table[string, ArgumentDefinition]
    resolved_function_steps: seq[ResolvedFunctionStep]

  discard ? file.find_module(function.definition.return_type)
  for arg in function.arg_def_list:
    discard ? file.find_module(arg.typ)
    if $(arg.name) in scope:
      let defined_arg = scope[$(arg.name)]
      return err(fmt"{arg.location} {arg.name} is already defined {defined_arg.location}")
    scope[$(arg.name)] = arg

  for (index, step) in function.function_steps.pairs:
    let resolved_function_step = ? file.resolve_function_step(scope,
        temp_var_count, step)
    resolved_function_steps.add(resolved_function_step)
    scope[$(resolved_function_step.destination)] = resolved_function_step.return_argument

  new_resolved_function(function_ref, function, resolved_function_steps)

proc resolve_unused_functions(file: blocks.File, visited_functions: HashSet[
    ResolvedFunctionRef]): Result[void, string] =
  for function in file.functions.values:
    let func_ref = new_resolved_function_ref(function.definition)
    if func_ref notin visited_functions:
      echo fmt"Unused function: {function.location} {function.name}"
      discard ? file.resolve_function(func_ref)

  for module in file.user_modules:
    for function in module.functions.values:
      let func_ref = new_resolved_function_ref(module,
          function.definition)
      if func_ref notin visited_functions:
        echo fmt"Unused function: {function.location} {module.name}.{function.name}"
        discard ? file.resolve_function(func_ref)
  ok()

proc resolve_functions(file: blocks.File): Result[seq[ResolvedFunction], string] =
  let start_fn_def = new_function_definition("start", @[("U8", "argc")], "U8")
  let start_function = ? file.find_function(start_fn_def)

  var
    stack = @[new_resolved_function_ref(start_function.definition)]
    visited_function_refs = init_hashset[ResolvedFunctionRef]()
    resolved_functions: seq[ResolvedFunction]

  while stack.len > 0:
    let function_ref = stack[^1]
    visited_function_refs.incl(function_ref)
    stack.set_len(stack.len - 1)

    let resolved_function = ? file.resolve_function(function_ref)
    let new_functions = resolved_function.function_refs.difference(visited_function_refs)

    resolved_functions.add(resolved_function)
    stack.add(new_functions.to_seq)

  ? file.resolve_unused_functions(visited_function_refs)
  ok(resolved_functions)

proc resolve_user_module_struct(file: blocks.File, module_name: Token,
    struct: Struct): Result[ResolvedStruct, string] =
  for (name, field) in struct.fields.pairs:
    discard ? file.find_module(field.typ)
  ok(new_resolved_struct(module_name, struct))

proc resolve_user_module_union(file: blocks.File, module_name: Token,
    union: Union): Result[ResolvedUnion, string] =
  for (_, struct) in union.fields.pairs:
    for (_, field) in struct.fields.pairs:
      discard ? file.find_module(field.typ)
  ok(new_resolved_union(module_name, union))

proc resolve_user_module(file: blocks.File, module: UserModule): Result[
    ResolvedUserModule, string] =
  case module.kind:
  of UMK_DEFAULT: err(fmt"{module.location} Module `{module.name}` is neither a struct nor union")
  of UMK_STRUCT:
    let struct = ? file.resolve_user_module_struct(module.name, module.struct)
    ok(new_resolved_user_module(struct))
  of UMK_UNION:
    let union = ? file.resolve_user_module_union(module.name, module.union)
    ok(new_resolved_user_module(union))

proc resolve_user_modules(file: blocks.File): Result[seq[ResolvedUserModule], string] =
  var resolved_user_modules: seq[ResolvedUserModule]
  for module in file.user_modules:
    let maybe_resolved = file.resolve_user_module(module)
    if maybe_resolved.is_ok: resolved_user_modules.add(maybe_resolved.get)
  return ok(resolved_user_modules)

proc resolve*(file: blocks.File): Result[ResolvedFile, string] =
  let resolved_user_modules = ? file.resolve_user_modules()
  let resolved_functions = ? file.resolve_functions()
  ok(new_resolved_file(resolved_user_modules, resolved_functions))
