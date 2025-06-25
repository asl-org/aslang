import results, tables, strformat, sequtils, parseutils, sets, options, strutils

import blocks

type File = blocks.File

type ResolvedArgument = ref object of RootObj
  kind: Token
  value: Token

proc new_resolved_argument(kind: Token, value: Token): ResolvedArgument =
  ResolvedArgument(kind: kind, value: value)

type ResolvedFunctionCallKind = enum
  RFCK_BUILTIN, RFCK_USER

type ResolvedFunctionCall = ref object of RootObj
  args: seq[ResolvedArgument]
  case kind: ResolvedFunctionCallKind
  of RFCK_BUILTIN:
    function_def: FunctionDefinition
  of RFCK_USER:
    function: Function

proc new_resolved_function_call(function_def: FunctionDefinition, args: seq[
    ResolvedArgument]): ResolvedFunctionCall =
  ResolvedFunctionCall(kind: RFCK_BUILTIN, function_def: function_def, args: args)

proc new_resolved_function_call(function: Function, args: seq[
    ResolvedArgument]): ResolvedFunctionCall =
  ResolvedFunctionCall(kind: RFCK_USER, function: function, args: args)

proc user_function(resolved_function_call: ResolvedFunctionCall): Option[Function] =
  case resolved_function_call.kind:
  of RFCK_BUILTIN: none(Function)
  of RFCK_USER: some(resolved_function_call.function)

proc return_type(resolved_function_call: ResolvedFunctionCall): Token =
  case resolved_function_call.kind:
  of RFCK_BUILTIN:
    resolved_function_call.function_def.return_type
  of RFCK_USER:
    resolved_function_call.function.definition.return_type

proc c(fncall: ResolvedFunctionCall): string =
  let args_str = fncall.args.map_it($(it.value)).join(", ")
  case fncall.kind:
  of RFCK_BUILTIN:
    fmt"{fncall.function_def.name}({args_str})"
  of RFCK_USER:
    fmt"{fncall.function.name}({args_str})"

type ResolvedStructInit = ref object of RootObj
  struct: Struct
  fields: seq[ResolvedArgument]

proc new_resolved_struct_init(struct: Struct, fields: seq[
    ResolvedArgument]): ResolvedStructInit =
  ResolvedStructInit(struct: struct, fields: fields)

proc c(init: ResolvedStructInit): string =
  let fields = init.fields.map_it($(it.value)).join(", ")
  fmt"{init.struct.name}_init({fields})"

type ResolvedStructGetter = ref object of RootObj
  struct: Struct
  field: ArgumentDefinition
  arg: Token

proc new_resolved_struct_getter(struct: Struct,
    field: ArgumentDefinition, arg: Token): ResolvedStructGetter =
  ResolvedStructGetter(struct: struct, field: field, arg: arg)

proc c(getter: ResolvedStructGetter): string =
  fmt"{getter.struct.name}_get_{getter.field.arg_name}({getter.arg})"

type
  ResolvedStatementKind = enum
    RSK_STRUCT_INIT
    RSK_STRUCT_GETTER
    RSK_FUNCTION_CALL
  ResolvedStatement = ref object of RootObj
    destination: Token
    case kind: ResolvedStatementKind
    of RSK_STRUCT_INIT:
      struct_init: ResolvedStructInit
    of RSK_STRUCT_GETTER:
      struct_getter: ResolvedStructGetter
    of RSK_FUNCTION_CALL:
      function_call: ResolvedFunctionCall

proc function_set(statement: ResolvedStatement): Hashset[Function] =
  case statement.kind:
  of RSK_FUNCTION_CALL:
    var function_set: Hashset[Function]
    let maybe_ext_function = statement.function_call.user_function
    if maybe_ext_function.is_some:
      function_set.incl(maybe_ext_function.get)
    function_set
  else:
    init_hashset[Function]()

proc return_argument(statement: ResolvedStatement): ArgumentDefinition =
  case statement.kind:
  of RSK_STRUCT_INIT:
    new_argument_definition(statement.struct_init.struct.name,
        statement.destination)
  of RSK_STRUCT_GETTER:
    new_argument_definition(statement.struct_getter.field.arg_type,
        statement.destination)
  of RSK_FUNCTION_CALL:
    new_argument_definition(statement.function_call.return_type,
        statement.destination)

proc c(statement: ResolvedStatement): string =
  let rhs =
    case statement.kind:
    of RSK_STRUCT_INIT: statement.struct_init.c
    of RSK_STRUCT_GETTER: statement.struct_getter.c
    of RSK_FUNCTION_CALL: statement.function_call.c

  fmt"{statement.return_argument.c} = {rhs};"

proc new_resolved_statement(struct_init: ResolvedStructInit,
    destination: Token): ResolvedStatement =
  ResolvedStatement(kind: RSK_STRUCT_INIT, struct_init: struct_init,
      destination: destination)

proc new_resolved_statement(struct_getter: ResolvedStructGetter,
    destination: Token): ResolvedStatement =
  ResolvedStatement(kind: RSK_STRUCT_GETTER, struct_getter: struct_getter,
      destination: destination)

proc new_resolved_statement(function_call: ResolvedFunctionCall,
    destination: Token): ResolvedStatement =
  ResolvedStatement(kind: RSK_FUNCTION_CALL, function_call: function_call,
      destination: destination)

type ResolvedCase = ref object of RootObj
  parsed_case_block: Case
  statements: seq[ResolvedStatement]

proc return_argument(case_block: ResolvedCase): ArgumentDefinition =
  case_block.statements[^1].return_argument

proc function_set(case_block: ResolvedCase): Hashset[Function] =
  var function_set: Hashset[Function]
  for statement in case_block.statements:
    function_set.incl(statement.function_set)
  function_set

proc c(resolved_case: ResolvedCase, result_var: Token): string =
  let case_block = resolved_case.parsed_case_block
  var lines = @[fmt"case {case_block.value}: " & "{"]
  for statement in resolved_case.statements:
    lines.add(statement.c)

  let return_arg = resolved_case.return_argument.arg_name
  lines.add(fmt"{result_var} = {return_arg};")
  lines.add("break;")
  lines.add("}")
  return lines.join("\n")

proc new_resolved_case(parsed_case_block: Case, statements: seq[
    ResolvedStatement]): ResolvedCase =
  ResolvedCase(parsed_case_block: parsed_case_block, statements: statements)

type ResolvedElse = ref object of RootObj
  parsed_else_block: Else
  statements: seq[ResolvedStatement]

proc return_argument(else_block: ResolvedElse): ArgumentDefinition =
  else_block.statements[^1].return_argument

proc function_set(else_block: ResolvedElse): Hashset[Function] =
  var function_set: Hashset[Function]
  for statement in else_block.statements:
    function_set.incl(statement.function_set)
  function_set

proc c(resolved_else_block: ResolvedElse, result_var: Token): string =
  var lines = @["default: {"]
  for statement in resolved_else_block.statements:
    lines.add(statement.c)

  let return_arg = resolved_else_block.return_argument.arg_name
  lines.add(fmt"{result_var} = {return_arg};")
  lines.add("break;")
  lines.add("}")
  return lines.join("\n")

proc new_resolved_else(parsed_else_block: Else, statements: seq[
    ResolvedStatement]): ResolvedElse =
  ResolvedElse(parsed_else_block: parsed_else_block, statements: statements)

type ResolvedMatch = ref object of RootObj
  parsed_match_block: Match
  destination: Token
  operand: Token
  case_blocks: seq[ResolvedCase]
  # there can only be 1 else block
  else_blocks: seq[ResolvedElse]
  return_argument: ArgumentDefinition

proc function_set(match: ResolvedMatch): HashSet[Function] =
  var function_set: Hashset[Function]
  for case_block in match.case_blocks:
    function_set.incl(case_block.function_set)
  for else_block in match.else_blocks:
    function_set.incl(else_block.function_set)
  return function_set

proc c*(resolved_match: ResolvedMatch): string =
  let match = resolved_match.parsed_match_block
  var lines = @[
    fmt"{resolved_match.return_argument};",
    fmt"switch({match.operand}) " & "{",
  ]
  for case_block in resolved_match.case_blocks:
    lines.add(case_block.c(match.destination))
  for else_block in resolved_match.else_blocks:
    lines.add(else_block.c(match.destination))
  lines.add("}")
  return lines.join("\n")

proc new_resolved_match(parsed_match_block: Match, destination: Token,
    operand: Token, case_blocks: seq[ResolvedCase], else_blocks: seq[
        ResolvedElse]): Result[ResolvedMatch, string] =
  let return_type = case_blocks[0].return_argument.arg_type
  let case_return_args = case_blocks.map_it(it.return_argument)
  let else_return_args = else_blocks.map_it(it.return_argument)
  for return_arg in (case_return_args & else_return_args):
    if $(return_type) != $(return_arg.arg_type):
      return err(fmt"{return_arg.location} block is expected to return {return_type} but found {return_arg.arg_type}")

  let return_argument = new_argument_definition(return_type, destination)
  ok(ResolvedMatch(parsed_match_block: parsed_match_block,
      destination: destination, operand: operand, case_blocks: case_blocks,
      else_blocks: else_blocks, return_argument: return_argument))

type
  ResolvedFunctionStepKind = enum
    RFSK_STATEMENT, RFSK_MATCH
  ResolvedFunctionStep = ref object of RootObj
    case kind: ResolvedFunctionStepKind
    of RFSK_STATEMENT:
      statement: ResolvedStatement
    of RFSK_MATCH:
      match: ResolvedMatch

proc function_set(function_step: ResolvedFunctionStep): Hashset[Function] =
  case function_step.kind:
  of RFSK_STATEMENT: function_step.statement.function_set
  of RFSK_MATCH: function_step.match.function_set

proc destination(function_step: ResolvedFunctionStep): Token =
  case function_step.kind:
  of RFSK_STATEMENT: function_step.statement.destination
  of RFSK_MATCH: function_step.match.destination

proc return_argument(function_step: ResolvedFunctionStep): ArgumentDefinition =
  case function_step.kind:
  of RFSK_STATEMENT: function_step.statement.return_argument
  of RFSK_MATCH: function_step.match.return_argument

proc c(function_step: ResolvedFunctionStep): string =
  case function_step.kind:
  of RFSK_STATEMENT: function_step.statement.c
  of RFSK_MATCH: function_step.match.c

proc new_resolved_function_step(statement: ResolvedStatement): ResolvedFunctionStep =
  ResolvedFunctionStep(kind: RFSK_STATEMENT, statement: statement)

proc new_resolved_function_step(match: ResolvedMatch): ResolvedFunctionStep =
  ResolvedFunctionStep(kind: RFSK_MATCH, match: match)

type ResolvedFunction* = ref object of RootObj
  function: Function
  steps: seq[ResolvedFunctionStep]

proc function_set(function: ResolvedFunction): Hashset[Function] =
  var function_set: Hashset[Function]
  for step in function.steps:
    function_set.incl(step.function_set)
  function_set

proc h*(resolved_function: ResolvedFunction): string =
  let function = resolved_function.function
  let args_def_str = function.definition.arg_def_list.map_it(it.c).join(", ")
  fmt"{function.native_return_type} {function.name}({args_def_str});"

proc c*(resolved_function: ResolvedFunction): string =
  let function = resolved_function.function
  let args_def_str = function.definition.arg_def_list.map_it(it.c).join(", ")
  let signature = fmt"{function.native_return_type} {function.name}({args_def_str})"

  var body = resolved_function.steps.map_it(it.c)
  let return_arg_name = resolved_function.steps[^1].return_argument.arg_name
  body.add(fmt"return {return_arg_name};")

  @[signature, "{", body.join("\n"), "}"].join("\n")

proc new_resolved_function(function: Function, steps: seq[
    ResolvedFunctionStep]): Result[ResolvedFunction, string] =
  let actual_return_type = steps[^1].return_argument.arg_type
  if $(function.return_type) != $(actual_return_type):
    return err(fmt"{function.location} expected {function.name} to return {function.return_type} but found {actual_return_type}")
  ok(ResolvedFunction(function: function, steps: steps))

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
    arg_def: ArgumentDefinition, arg_value: Token): Result[ResolvedArgument, string] =
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

  ok(new_resolved_argument(arg_def.arg_type, arg_value))

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
    resolved_args.add( ? scope.resolve_argument(arg_def, arg_value))
  ok(resolved_args)

proc resolve_builtin_function_call(function_call: FunctionCall, file: File,
    scope: Table[string, ArgumentDefinition]): Result[ResolvedFunctionCall, string] =
  for function_def in file.builtins:
    let maybe_resolved_args = function_call.resolve_function_call_args(
        function_def, scope)
    if maybe_resolved_args.is_ok:
      return ok(new_resolved_function_call(function_def,
          maybe_resolved_args.get))
  return err(fmt"{function_call.location} `{function_call.name}` failed to find matching builtin function in the file {file.name}")

# matches all functions with function call within a file
proc resolve_user_function_call(function_call: FunctionCall, file: File,
    scope: Table[string, ArgumentDefinition]): Result[ResolvedFunctionCall, string] =
  for function in file.functions:
    let maybe_resolved_args = function_call.resolve_function_call_args(
        function.definition, scope)
    if maybe_resolved_args.is_ok:
      return ok(new_resolved_function_call(function, maybe_resolved_args.get))
  return err(fmt"{function_call.location} `{function_call.name}` failed to find matching user function in the file {file.name}")

proc resolve_function_call(function_call: FunctionCall, file: File,
    scope: Table[string, ArgumentDefinition]): Result[ResolvedFunctionCall, string] =
  # try looking up builtins function call
  let maybe_resolved_builtin_function_call = function_call.resolve_builtin_function_call(
      file, scope)
  if maybe_resolved_builtin_function_call.is_ok:
    return ok(maybe_resolved_builtin_function_call.get)

  # try looking up user function call
  return function_call.resolve_user_function_call(file, scope)

proc resolve_struct_init(struct_init: StructInit, file: File,
    scope: Table[string, ArgumentDefinition]): Result[ResolvedStructInit, string] =
  let struct_var = struct_init.struct
  let key_value_pairs = struct_init.fields

  let struct = ? file.find_struct(struct_var)
  var field_name_table: Table[string, ResolvedArgument]
  for (field_name, field_value) in key_value_pairs:
    if $(field_name) in field_name_table:
      return err(fmt"{field_name.location} {field_name} is already present in the initializer")
    let field = ? struct.find_field(field_name)
    field_name_table[$(field_name)] = ? scope.resolve_argument(field, field_value)

  let resolved_fields = struct.fields.map_it(field_name_table[$(it.arg_name)])
  let resolved_struct_init = new_resolved_struct_init(struct, resolved_fields)
  ok(resolved_struct_init)

proc resolve_struct_getter(struct_getter: StructGetter, file: File,
    scope: Table[string, ArgumentDefinition]): Result[ResolvedStructGetter, string] =
  let struct_var = struct_getter.struct
  let field_name = struct_getter.field

  if $(struct_var) notin scope:
    return err(fmt"{struct_var.location} {struct_var} is not defined in the scope")

  let struct = ? file.find_struct(scope[$(struct_var)].arg_type)
  let field = ? struct.find_field(field_name)
  let resolved_struct_getter = new_resolved_struct_getter(struct, field, struct_var)
  ok(resolved_struct_getter)

proc resolve_statement(statement: Statement, file: File, scope: Table[string,
    ArgumentDefinition]): Result[ResolvedStatement, string] =
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

proc resolve_case_block(case_block: Case, file: File,
    scope: Table[string, ArgumentDefinition]): Result[ResolvedCase, string] =
  var resolved_statements: seq[ResolvedStatement]
  # copy current function scope to the case scope to avoid non local argument name conflicts
  var scope = deep_copy(scope)
  for (index, statement) in case_block.statements.pairs:
    let resolved_statement = ? statement.resolve_statement(file, scope)
    resolved_statements.add(resolved_statement)
    scope[$(statement.destination)] = resolved_statement.return_argument

  return ok(new_resolved_case(case_block, resolved_statements))

proc resolve_else_block(else_block: Else, file: File,
    scope: Table[string, ArgumentDefinition]): Result[ResolvedElse, string] =
  var resolved_statements: seq[ResolvedStatement]
  # copy current function scope to the else scope to avoid non local argument name conflicts
  var scope = deep_copy(scope)
  for (index, statement) in else_block.statements.pairs:
    let resolved_statement = ? statement.resolve_statement(file, scope)
    resolved_statements.add(resolved_statement)
    scope[$(statement.destination)] = resolved_statement.return_argument

  return ok(new_resolved_else(else_block, resolved_statements))

proc resolve_match(match: Match, file: File, scope: Table[string,
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
    discard ? scope.resolve_argument(match_operand_def, case_block.value)
    let resolved_case_block = ? case_block.resolve_case_block(file, scope)
    resolved_case_blocks.add(resolved_case_block)

  # Note: Even though this is a for loop but there can only be at most 1 else block.
  for (index, else_block) in match.else_blocks.pairs:
    let resolved_else_block = ? else_block.resolve_else_block(file, scope)
    resolved_else_blocks.add(resolved_else_block)

  new_resolved_match(match, match.destination, match.operand,
      resolved_case_blocks, resolved_else_blocks)

proc resolve_function_step(step: FunctionStep, file: File,
    scope: var Table[string, ArgumentDefinition]): Result[ResolvedFunctionStep, string] =
  case step.kind:
  of FSK_STATEMENT:
    let resolved_statement = ? step.statement.resolve_statement(file, scope)
    return ok(new_resolved_function_step(resolved_statement))
  of FSK_MATCH:
    let resolved_match = ? step.match.resolve_match(file, scope)
    return ok(new_resolved_function_step(resolved_match))

proc resolve_function(function: Function, file: File): Result[ResolvedFunction, string] =
  var
    scope: Table[string, ArgumentDefinition]
    resolved_function_steps: seq[ResolvedFunctionStep]

  ? file.find_module(function.definition.return_type)
  for arg in function.arg_def_list:
    ? file.find_module(arg.arg_type)
    if $(arg.arg_name) in scope:
      let defined_arg = scope[$(arg.arg_name)]
      return err(fmt"{arg.location} {arg.arg_name} is already defined {defined_arg.location}")
    scope[$(arg.arg_name)] = arg

  for (index, step) in function.function_steps.pairs:
    let resolved_function_step = ? step.resolve_function_step(file, scope)
    resolved_function_steps.add(resolved_function_step)
    scope[$(resolved_function_step.destination)] = resolved_function_step.return_argument

  new_resolved_function(function, resolved_function_steps)

proc resolve*(file: File): Result[seq[ResolvedFunction], string] =
  # TODO: Resolve structs/unions as well.
  # Trace function call flow from main function
  var stack = @[ ? file.find_start_function()]
  var visited_functions = init_hashset[Function]()
  var resolved_functions: seq[ResolvedFunction]
  while stack.len > 0:
    let function = stack[^1]
    visited_functions.incl(function)
    stack.set_len(stack.len - 1)

    let resolved_function = ? function.resolve_function(file)
    resolved_functions.add(resolved_function)

    let new_functions = resolved_function.function_set.difference(visited_functions)
    stack.add(new_functions.to_seq)

  # Resolve unused functions
  # TODO: Raise warnings for unused functions
  for function in file.functions:
    if function notin visited_functions:
      echo fmt"Unused function: {function.location} {function.name}"
      discard ? function.resolve_function(file)

  discard ? expand(file)

  ok(resolved_functions)
