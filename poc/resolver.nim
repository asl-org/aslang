import results, tables, strformat, sequtils, parseutils, sets, options

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

type ResolvedStructInit = ref object of RootObj
  struct: Struct
  fields: seq[ResolvedArgument]

proc new_resolved_struct_init(struct: Struct, fields: seq[
    ResolvedArgument]): ResolvedStructInit =
  ResolvedStructInit(struct: struct, fields: fields)

type ResolvedStructGetter = ref object of RootObj
  struct: Struct
  field: ArgumentDefinition
  arg: Token

proc new_resolved_struct_getter(struct: Struct,
    field: ArgumentDefinition, arg: Token): ResolvedStructGetter =
  ResolvedStructGetter(struct: struct, field: field, arg: arg)

type
  ResolvedStatementKind = enum
    RSK_STRUCT_INIT
    RSK_STRUCT_GETTER
    RSK_FUNCTION_CALL
  ResolvedStatement = ref object of RootObj
    function_set: Hashset[Function]
    expanded: Option[Statement]
    case kind: ResolvedStatementKind
    of RSK_STRUCT_INIT:
      struct_init: ResolvedStructInit
    of RSK_STRUCT_GETTER:
      struct_getter: ResolvedStructGetter
    of RSK_FUNCTION_CALL:
      function_call: ResolvedFunctionCall

proc new_resolved_statement(struct_init: ResolvedStructInit, expanded: Option[
    Statement]): ResolvedStatement =
  ResolvedStatement(kind: RSK_STRUCT_INIT, struct_init: struct_init,
      expanded: expanded)

proc new_resolved_statement(struct_init: ResolvedStructInit,
    expanded: Statement): ResolvedStatement =
  new_resolved_statement(struct_init, some(expanded))

proc new_resolved_statement(struct_getter: ResolvedStructGetter,
    expanded: Option[Statement]): ResolvedStatement =
  ResolvedStatement(kind: RSK_STRUCT_GETTER, struct_getter: struct_getter,
      expanded: expanded)

proc new_resolved_statement(struct_getter: ResolvedStructGetter,
    expanded: Statement): ResolvedStatement =
  new_resolved_statement(struct_getter, some(expanded))

proc new_resolved_statement(function_call: ResolvedFunctionCall,
    function_set: Hashset[Function]): ResolvedStatement =
  ResolvedStatement(kind: RSK_FUNCTION_CALL, function_call: function_call,
      function_set: function_set)

type ResolvedCase = ref object of RootObj
  statements: seq[ResolvedStatement]
  # external function deps
  function_set: Hashset[Function]
  return_arg: ArgumentDefinition

proc new_resolved_case(statements: seq[ResolvedStatement],
    function_set: Hashset[Function],
    return_arg: ArgumentDefinition): ResolvedCase =
  ResolvedCase(statements: statements, function_set: function_set,
      return_arg: return_arg)

type ResolvedElse = ref object of RootObj
  statements: seq[ResolvedStatement]
  # external function deps
  function_set: Hashset[Function]
  return_arg: ArgumentDefinition

proc new_resolved_else(statements: seq[ResolvedStatement],
    function_set: Hashset[Function],
    return_arg: ArgumentDefinition): ResolvedElse =
  ResolvedElse(statements: statements, function_set: function_set,
      return_arg: return_arg)

type ResolvedMatch = ref object of RootObj
  case_blocks: seq[ResolvedCase]
  # there can only be 1 else block
  else_blocks: seq[ResolvedElse]
  return_arg: ArgumentDefinition
  function_set: HashSet[Function]

proc new_resolved_match(case_blocks: seq[ResolvedCase], else_blocks: seq[
    ResolvedElse], return_arg: ArgumentDefinition, function_set: HashSet[
        Function]): ResolvedMatch =
  ResolvedMatch(case_blocks: case_blocks, else_blocks: else_blocks,
      return_arg: return_arg, function_set: function_set)

type
  ResolvedFunctionStepKind = enum
    RFSK_STATEMENT, RFSK_MATCH
  ResolvedFunctionStep = ref object of RootObj
    function_set: Hashset[Function]
    expanded: Option[FunctionStep]
    case kind: ResolvedFunctionStepKind
    of RFSK_STATEMENT:
      statement: ResolvedStatement
    of RFSK_MATCH:
      match: ResolvedMatch

proc new_resolved_function_step(statement: ResolvedStatement,
    function_set: HashSet[Function], expanded: Statement): ResolvedFunctionStep =
  ResolvedFunctionStep(kind: RFSK_STATEMENT, statement: statement,
      function_set: function_set, expanded: some(new_function_step(expanded)))

proc new_resolved_function_step(statement: ResolvedStatement,
    function_set: HashSet[Function]): ResolvedFunctionStep =
  ResolvedFunctionStep(kind: RFSK_STATEMENT, statement: statement,
      function_set: function_set, expanded: none(FunctionStep))

proc new_resolved_function_step(match: ResolvedMatch,
    function_set: HashSet[Function]): ResolvedFunctionStep =
  ResolvedFunctionStep(kind: RFSK_MATCH, match: match,
      function_set: function_set, expanded: none(FunctionStep))

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

# matches all functions with function call within a file
proc resolve_function_call(file: File, scope: Table[string,
    ArgumentDefinition], function_call: FunctionCall): Result[
        ResolvedFunctionCall, string] =
  for function in file.functions:
    let maybe_resolved_args = function_call.resolve_function_call_args(
        function.definition, scope)
    if maybe_resolved_args.is_ok:
      return ok(new_resolved_function_call(function, maybe_resolved_args.get))
  return err(fmt"{function_call.location} `{function_call.name}` failed to find matching user function in the file {file.name}")

proc resolve_builtin_function_call(file: File, scope: Table[string,
    ArgumentDefinition], function_call: FunctionCall): Result[
        ResolvedFunctionCall, string] =
  for function_def in file.builtins:
    let maybe_resolved_args = function_call.resolve_function_call_args(
        function_def, scope)
    if maybe_resolved_args.is_ok:
      return ok(new_resolved_function_call(function_def,
          maybe_resolved_args.get))
  return err(fmt"{function_call.location} `{function_call.name}` failed to find matching builtin function in the file {file.name}")

proc resolve_expanded_function_call(file: File, scope: Table[string,
    ArgumentDefinition], function_call: FunctionCall): Result[
    ResolvedFunctionCall, string] =
  for function in file.expanded:
    let maybe_resolved_args = function_call.resolve_function_call_args(
        function.definition, scope)
    if maybe_resolved_args.is_ok:
      return ok(new_resolved_function_call(function, maybe_resolved_args.get))
  return err(fmt"{function_call.location} `{function_call.name}` failed to find matching expanded function in the file {file.name}")

proc resolve_function_call_statement(statement: Statement, file: File,
    scope: var Table[string, ArgumentDefinition]): Result[ResolvedFunctionCall, string] =
  # try looking up builtins function call
  let maybe_resolved_builtin_function_call = file.resolve_builtin_function_call(
      scope, statement.function_call)
  if maybe_resolved_builtin_function_call.is_ok:
    scope[$(statement.destination)] = new_argument_definition(
        maybe_resolved_builtin_function_call.get.return_type,
        statement.destination)
    return ok(maybe_resolved_builtin_function_call.get)

  # try looking up expanded function call
  let maybe_resolved_function_call = file.resolve_expanded_function_call(scope,
      statement.function_call)
  if maybe_resolved_function_call.is_ok:
    scope[$(statement.destination)] = new_argument_definition(
        maybe_resolved_function_call.get.return_type, statement.destination)
    return ok(maybe_resolved_function_call.get)

  # try looking up user function call
  let resolved_function_call = ? file.resolve_function_call(scope,
      statement.function_call)
  scope[$(statement.destination)] = new_argument_definition(
      resolved_function_call.return_type, statement.destination)
  return ok(resolved_function_call)

proc resolve_struct_init_statement(statement: Statement, file: File,
    scope: Table[string, ArgumentDefinition]): Result[ResolvedStructInit, string] =
  let struct_var = statement.struct_init.struct
  let key_value_pairs = statement.struct_init.fields

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

proc resolve_struct_getter_statement(statement: Statement, file: File,
    scope: Table[string, ArgumentDefinition]): Result[ResolvedStructGetter, string] =
  let struct_var = statement.struct_getter.struct
  let field_name = statement.struct_getter.field

  if $(struct_var) notin scope:
    return err(fmt"{struct_var.location} {struct_var} is not defined in the scope")

  let struct = ? file.find_struct(scope[$(struct_var)].arg_type)
  let field = ? struct.find_field(field_name)
  let resolved_struct_getter = new_resolved_struct_getter(struct, field, struct_var)
  ok(resolved_struct_getter)

proc resolve_statement(statement: Statement, file: File, scope: var Table[
    string, ArgumentDefinition]): Result[ResolvedStatement, string] =
  # check if variable is already defined in the local(case) scope
  if $(statement.destination) in scope:
    let defined_arg = scope[$(statement.destination)]
    return err(fmt"{statement.destination.location} {statement.destination} is already defined {defined_arg.location}")

  var resolved_statement: ResolvedStatement
  case statement.kind:
  of SK_STRUCT_INIT:
    let resolved_struct_init = ? statement.resolve_struct_init_statement(file,
        scope)
    scope[$(statement.destination)] = new_argument_definition(
        resolved_struct_init.struct.name, statement.destination)
    # expansion and rewrite statement logic
    let init_arg_list = resolved_struct_init.fields.map_it(it.value)
    let struct_init_call = fmt"{resolved_struct_init.struct.name}_init".new_id_token().new_function_call(init_arg_list)
    let expanded = new_statement(statement.destination, struct_init_call)
    resolved_statement = new_resolved_statement(resolved_struct_init, expanded)
  of SK_STRUCT_GETTER:
    let resolved_struct_getter = ?
      statement.resolve_struct_getter_statement(
    file, scope)
    scope[$(statement.destination)] = new_argument_definition(
        resolved_struct_getter.field.arg_type, statement.destination)
    # expand struct getter into function call
    let struct_getter_call = fmt"{resolved_struct_getter.struct.name}_get_{resolved_struct_getter.field.arg_name}".new_id_token(
      ).new_function_call(@[resolved_struct_getter.arg])
    let expanded = new_statement(statement.destination, struct_getter_call)
    resolved_statement = new_resolved_statement(resolved_struct_getter, expanded)
  of SK_FUNCTION_CALL:
    let resolved_function_call = ? statement.resolve_function_call_statement(
        file, scope)
    var function_set: Hashset[Function]
    let maybe_ext_function = resolved_function_call.user_function
    if maybe_ext_function.is_some:
      function_set.incl(maybe_ext_function.get)
    resolved_statement = new_resolved_statement(resolved_function_call, function_set)

  return ok(resolved_statement)

proc resolve_case_block(case_block: Case, file: File,
    scope: Table[string, ArgumentDefinition]): Result[ResolvedCase, string] =
  var function_set: Hashset[Function]
  var resolved_statements: seq[ResolvedStatement]
  # copy current function scope to the case scope to avoid non local argument name conflicts
  case_block.scope = deep_copy(scope)
  for (index, statement) in case_block.statements.pairs:
    let resolved_statement = ? statement.resolve_statement(file,
        case_block.scope)
    resolved_statements.add(resolved_statement)

    if resolved_statement.expanded.is_some:
      case_block.statements[index] = resolved_statement.expanded.get

    for ext_function in resolved_statement.function_set:
      function_set.incl(ext_function)

  let return_argument = case_block.statements[^1].destination
  let return_arg_def = case_block.scope[$(return_argument)]

  return ok(new_resolved_case(resolved_statements, function_set,
      return_arg_def))

proc resolve_else_block(else_block: Else, file: File,
    scope: Table[string, ArgumentDefinition]): Result[ResolvedElse, string] =
  var function_set: Hashset[Function]
  var resolved_statements: seq[ResolvedStatement]
  # copy current function scope to the else scope to avoid non local argument name conflicts
  else_block.scope = deep_copy(scope)
  for (index, statement) in else_block.statements.pairs:
    let resolved_statement = ? statement.resolve_statement(file,
        else_block.scope)
    resolved_statements.add(resolved_statement)

    if resolved_statement.expanded.is_some:
      else_block.statements[index] = resolved_statement.expanded.get

    for ext_function in resolved_statement.function_set:
      function_set.incl(ext_function)

  let return_argument = else_block.statements[^1].destination
  let return_arg_def = else_block.scope[$(return_argument)]

  return ok(new_resolved_else(resolved_statements, function_set,
      return_arg_def))

proc resolve_match(match: Match, file: File, scope: var Table[string,
    ArgumentDefinition]): Result[ResolvedMatch, string] =
  var function_set: HashSet[Function]
  var resolved_case_blocks: seq[ResolvedCase]
  var resolved_else_blocks: seq[ResolvedElse]
  if $(match.destination) in scope:
    let defined_arg = scope[$(match.destination)]
    return err(fmt"{match.destination.location} {match.destination} is already defined {defined_arg.location}")

  if $(match.operand) notin scope:
    return err(fmt"{match.operand.location} {match.operand} is not defined in the scope")

  # Temporary hack to ensure that the variable that match block value is assigned to,
  # can not be used inside a case/block variable. This variable is updated after match
  # block resolution is complete. Look for `scope[$(match.destination)]`
  scope[$(match.destination)] = new_argument_definition(Token(
      kind: TK_ID, location: match.destination.location), Token(kind: TK_ID))

  for case_block in match.case_blocks:
    # TODO: Make sure that case_block pattern matches with value passed to match call
    let resolved_case_block = ? case_block.resolve_case_block(file,
        scope)
    resolved_case_blocks.add(resolved_case_block)
    for ext_function in resolved_case_block.function_set:
      if ext_function notin function_set:
        function_set.incl(ext_function)

    let return_arg = resolved_case_block.return_arg
    if match.return_type.is_none:
      match.return_type = some(return_arg.arg_type)
    elif $(match.return_type.get) != $(return_arg.arg_type):
      return err(fmt"{return_arg.location} `case` block is expected to return {match.return_type.get} but found {return_arg.arg_type}")

  # Note: Even though this is a for loop but there can only be at most 1 else block.
  for (index, else_block) in match.else_blocks.pairs:
    let resolved_else_block = ? else_block.resolve_else_block(file, scope)
    resolved_else_blocks.add(resolved_else_block)
    for ext_function in resolved_else_block.function_set:
      if ext_function notin function_set:
        function_set.incl(ext_function)

    let return_arg = resolved_else_block.return_arg
    if match.return_type.is_none:
      match.return_type = some(return_arg.arg_type)
    elif $(match.return_type.get) != $(return_arg.arg_type):
      return err(fmt"{return_arg.location} `else` block is expected to return {match.return_type.get} but found {return_arg.arg_type}")

  let return_arg = new_argument_definition(
      match.return_type.get, match.destination)
  scope[$(match.destination)] = return_arg

  ok(new_resolved_match(resolved_case_blocks, resolved_else_blocks, return_arg, function_set))

proc resolve_function_step(step: FunctionStep, file: File,
    scope: var Table[string, ArgumentDefinition]): Result[ResolvedFunctionStep, string] =
  var function_set: Hashset[Function]
  case step.kind:
  of FSK_STATEMENT:
    let resolved_statement = ? step.statement.resolve_statement(file, scope)

    for ext_function in resolved_statement.function_set:
      function_set.incl(ext_function)

    let resolved_function_step =
      if resolved_statement.expanded.is_some:
        new_resolved_function_step(resolved_statement, function_set,
        resolved_statement.expanded.get)
      else:
        new_resolved_function_step(resolved_statement, function_set)

    return ok(resolved_function_step)
  of FSK_MATCH:
    let resolved_match = ? step.match.resolve_match(file, scope)
    for ext_function in resolved_match.function_set:
      function_set.incl(ext_function)
    return ok(new_resolved_function_step(resolved_match, function_set))

proc resolve_function(function: Function, file: File): Result[HashSet[Function], string] =
  var function_set = init_hashset[Function]()

  ? file.find_module(function.definition.return_type)
  # add function definition args
  for arg in function.arg_def_list:
    ? file.find_module(arg.arg_type)
    if $(arg.arg_name) in function.scope:
      let defined_arg = function.scope[$(arg.arg_name)]
      return err(fmt"{arg.location} {arg.arg_name} is already defined {defined_arg.location}")
    function.scope[$(arg.arg_name)] = arg

  for (index, step) in function.function_steps.pairs:
    let resolved_function_step = ? step.resolve_function_step(file,
        function.scope)
    if resolved_function_step.expanded.is_some:
      function.function_steps[index] = resolved_function_step.expanded.get

    for ext_function in resolved_function_step.function_set:
      function_set.incl(ext_function)

  let last_step = function.function_steps[^1]
  let return_argument =
    case last_step.kind:
    of FSK_STATEMENT: last_step.statement.destination
    of FSK_MATCH: last_step.match.destination

  let actual_return_type = $(function.scope[$(return_argument)].arg_type)
  if function.return_type != actual_return_type:
    return err(fmt"{function.location} expected {function.name} to return {function.return_type} but found {actual_return_type}")

  return ok(function_set)

proc resolve*(file: File): Result[seq[Function], string] =
  # Trace function call flow from main function
  var stack = @[ ? file.find_start_function()]
  var visited_functions = init_hashset[Function]()
  while stack.len > 0:
    let function = stack[^1]
    stack.set_len(stack.len - 1)
    if function in visited_functions: continue

    let new_functions = ? function.resolve_function(file)
    visited_functions.incl(function)

    for new_function in new_functions:
      if new_function notin visited_functions:
        stack.add(new_function)

  # Resolve unused functions
  # TODO: Raise warnings for unused functions
  for function in file.functions:
    if function notin visited_functions:
      discard ? function.resolve_function(file)

  ok(visited_functions.to_seq)
