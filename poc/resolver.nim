import results, tables, strformat, sequtils, parseutils, sets, options

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
    return err(fmt"{function_call.location} expected function with name {function_call.name} but found {function.name}")
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
  return err(fmt"{function_call.location} `{function_call.name}` failed to find matching user function in the file {file.name}")

proc resolve_builtin_function_call(file: File, scope: Table[string,
    ArgumentDefinition], function_call: FunctionCall): Result[
        FunctionDefinition, string] =
  for function_def in file.builtins:
    let maybe_resolved = scope.resolve_function_call(function_def, function_call)
    if maybe_resolved.is_ok:
      return ok(function_def)
  return err(fmt"{function_call.location} `{function_call.name}` failed to find matching builtin function in the file {file.name}")

proc resolve_expanded_function_call(file: File, scope: Table[string,
    ArgumentDefinition], function_call: FunctionCall): Result[
        Function, string] =
  for function in file.expanded:
    let maybe_resolved = scope.resolve_function_call(function.definition, function_call)
    if maybe_resolved.is_ok:
      return ok(function)
  return err(fmt"{function_call.location} `{function_call.name}` failed to find matching expanded function in the file {file.name}")

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

  var sindex = 0 # statement index
  var mindex = 0 # match block index
  for step in 0..<function.steps:
    # handle function call statements
    if sindex < function.statements.len and function.statements[sindex][0] == step:
      let (_, statement) = function.statements[sindex]
      if $(statement.destination) in function.scope:
        let defined_arg = function.scope[$(statement.destination)]
        return err(fmt"{statement.destination.location} {statement.destination} is already defined {defined_arg.location}")

      case statement.kind:
      of SK_STRUCT_INIT:
        let struct_var = statement.struct_init.struct
        let key_value_pairs = statement.struct_init.fields

        let struct = ? file.find_struct(struct_var)
        var field_name_table: Table[string, Token]
        for (field_name, field_value) in key_value_pairs:
          if $(field_name) in field_name_table:
            return err(fmt"{field_name.location} {field_name} is already present in the initializer")
          let field = ? struct.find_field(field_name)
          ? function.scope.resolve_argument(field, field_value)
          field_name_table[$(field_name)] = field_value

        let init_arg_list = struct.fields.map_it(field_name_table[$(it.arg_name)])
        let struct_getter_call = new_function_call(new_id_token(
            fmt"{struct.name}_init"), init_arg_list)
        function.statements[sindex][1] = new_statement(statement.destination, struct_getter_call)
        function.scope[$(statement.destination)] = new_argument_definition(
            struct.name, statement.destination)
        sindex += 1
      of SK_STRUCT_GETTER:
        let struct_var = statement.struct_getter.struct
        let field_name = statement.struct_getter.field

        if $(struct_var) notin function.scope:
          return err(fmt"{struct_var.location} {struct_var} is not defined in the scope")

        let struct = ? file.find_struct(function.scope[$(struct_var)].arg_type)
        let field = ? struct.find_field(field_name)
        # expand struct getter into function call
        let struct_getter_call = new_function_call(new_id_token(
            fmt"{struct.name}_get_{field.arg_name}"), @[struct_var])
        function.statements[sindex][1] = new_statement(statement.destination, struct_getter_call)
        function.scope[$(statement.destination)] = new_argument_definition(
            field.arg_type, statement.destination)
        sindex += 1
      of SK_FUNCTION_CALL:
        # try looking up builtins function call
        let maybe_builtin = file.resolve_builtin_function_call(function.scope,
            statement.function_call)
        if maybe_builtin.is_ok:
          function.scope[$(statement.destination)] = new_argument_definition(
              maybe_builtin.get.return_type, statement.destination)
          # increment statement index
          sindex += 1
          continue

        # try looking up expanded function call
        let maybe_expanded = file.resolve_expanded_function_call(function.scope,
            statement.function_call)
        if maybe_expanded.is_ok:
          function.scope[$(statement.destination)] = new_argument_definition(
              maybe_expanded.get.definition.return_type, statement.destination)
          # increment statement index
          sindex += 1
          continue

        # try looking up user function call
        let fn = ? file.resolve_function_call(function.scope,
            statement.function_call)
        function.scope[$(statement.destination)] = new_argument_definition(
            fn.definition.return_type, statement.destination)
        function_set.incl(fn)
        # increment statement index
        sindex += 1
    # handle match block statements
    else:
      let (_, match) = function.matches[mindex]
      if $(match.destination) in function.scope:
        let defined_arg = function.scope[$(match.destination)]
        return err(fmt"{match.destination.location} {match.destination} is already defined {defined_arg.location}")

      if $(match.operand) notin function.scope:
        return err(fmt"{match.operand.location} {match.operand} is not defined in the scope")

      # Temporary hack to ensure that the variable that match block value is assigned to,
      # can not be used inside a case/block variable. This variable is updated after match
      # block resolution is complete. Look for `function.scope[$(match.destination)]`
      function.scope[$(match.destination)] = new_argument_definition(Token(
          kind: TK_ID, location: match.destination.location), Token(kind: TK_ID))

      for case_block in match.case_blocks:
        # copy current function scope to the case scope to avoid non local argument name conflicts
        case_block.scope = deep_copy(function.scope)
        for (index, statement) in case_block.statements.pairs:
          # check if variable is already defined in the local(case) scope
          if $(statement.destination) in case_block.scope:
            let defined_arg = case_block.scope[$(statement.destination)]
            return err(fmt"{statement.destination.location} {statement.destination} is already defined {defined_arg.location}")

          case statement.kind:
          of SK_STRUCT_INIT:
            let struct_var = statement.struct_init.struct
            let key_value_pairs = statement.struct_init.fields

            let struct = ? file.find_struct(struct_var)
            var field_name_table: Table[string, Token]
            for (field_name, field_value) in key_value_pairs:
              if $(field_name) in field_name_table:
                return err(fmt"{field_name.location} {field_name} is already present in the initializer")
              let field = ? struct.find_field(field_name)
              ? case_block.scope.resolve_argument(field, field_value)
              field_name_table[$(field_name)] = field_value

            let init_arg_list = struct.fields.map_it(field_name_table[$(it.arg_name)])
            let struct_getter_call = new_function_call(new_id_token(
                fmt"{struct.name}_init"), init_arg_list)
            function.statements[sindex][1] = new_statement(
                statement.destination, struct_getter_call)
            case_block.scope[$(statement.destination)] = new_argument_definition(
                struct.name, statement.destination)
          of SK_STRUCT_GETTER:
            let struct_var = statement.struct_getter.struct
            let field_name = statement.struct_getter.field

            if $(struct_var) notin case_block.scope:
              return err(fmt"{struct_var.location} {struct_var} is not defined in the scope")

            let struct = ? file.find_struct(case_block.scope[$(
                struct_var)].arg_type)
            let field = ? struct.find_field(field_name)
            # expand struct getter into function call
            let struct_getter_call = new_function_call(new_id_token(
                fmt"{struct.name}_get_{field.arg_name}"), @[struct_var])
            case_block.statements[index] = new_statement(
                statement.destination, struct_getter_call)
            case_block.scope[$(statement.destination)] = new_argument_definition(
                field.arg_type, statement.destination)
          of SK_FUNCTION_CALL:
            # try looking up builtins function call
            let maybe_builtin = file.resolve_builtin_function_call(
                case_block.scope, statement.function_call)
            if maybe_builtin.is_ok:
              case_block.scope[$(statement.destination)] = new_argument_definition(
                  maybe_builtin.get.return_type, statement.destination)
              continue

            # try looking up expanded function call
            let maybe_expanded = file.resolve_expanded_function_call(
                case_block.scope, statement.function_call)
            if maybe_expanded.is_ok:
              case_block.scope[$(statement.destination)] = new_argument_definition(
                  maybe_expanded.get.definition.return_type,
                  statement.destination)
              continue

            # try looking up user function call
            let fn = ? file.resolve_function_call(case_block.scope,
                statement.function_call)
            case_block.scope[$(statement.destination)] = new_argument_definition(
                fn.definition.return_type, statement.destination)
            function_set.incl(fn)


        let return_argument = case_block.statements[^1].destination
        let actual_return_type = case_block.scope[$(return_argument)].arg_type
        if match.return_type.is_none:
          match.return_type = some(actual_return_type)
        elif $(match.return_type.get) != $(actual_return_type):
          return err(fmt"{return_argument.location} `case` block is expected to return {match.return_type.get} but found {actual_return_type}")

      for (index, else_block) in match.else_blocks.pairs:
        else_block.scope = deep_copy(function.scope)
        for statement in else_block.statements:
          # check if variable is already defined in the local(case) scope
          if $(statement.destination) in else_block.scope:
            let defined_arg = else_block.scope[$(statement.destination)]
            return err(fmt"{statement.destination.location} {statement.destination} is already defined {defined_arg.location}")

          case statement.kind:
          of SK_STRUCT_INIT:
            let struct_var = statement.struct_init.struct
            let key_value_pairs = statement.struct_init.fields

            let struct = ? file.find_struct(struct_var)
            var field_name_table: Table[string, Token]
            for (field_name, field_value) in key_value_pairs:
              if $(field_name) in field_name_table:
                return err(fmt"{field_name.location} {field_name} is already present in the initializer")
              let field = ? struct.find_field(field_name)
              ? else_block.scope.resolve_argument(field, field_value)
              field_name_table[$(field_name)] = field_value

            let init_arg_list = struct.fields.map_it(field_name_table[$(it.arg_name)])
            let struct_getter_call = new_function_call(new_id_token(
                fmt"{struct.name}_init"), init_arg_list)
            function.statements[sindex][1] = new_statement(
                statement.destination, struct_getter_call)
            else_block.scope[$(statement.destination)] = new_argument_definition(
                struct.name, statement.destination)
          of SK_STRUCT_GETTER:
            let struct_var = statement.struct_getter.struct
            let field_name = statement.struct_getter.field

            if $(struct_var) notin else_block.scope:
              return err(fmt"{struct_var.location} {struct_var} is not defined in the scope")

            let struct = ? file.find_struct(else_block.scope[$(
                struct_var)].arg_type)
            let field = ? struct.find_field(field_name)
            # expand struct getter into function call
            let struct_getter_call = new_function_call(new_id_token(
                fmt"{struct.name}_get_{field.arg_name}"), @[struct_var])
            else_block.statements[index] = new_statement(
                statement.destination, struct_getter_call)
            else_block.scope[$(statement.destination)] = new_argument_definition(
                field.arg_type, statement.destination)
          of SK_FUNCTION_CALL:
            # try looking up builtins function call
            let maybe_builtin = file.resolve_builtin_function_call(
                else_block.scope, statement.function_call)
            if maybe_builtin.is_ok:
              else_block.scope[$(statement.destination)] = new_argument_definition(
                  maybe_builtin.get.return_type, statement.destination)
              continue

            # try looking up expanded function call
            let maybe_expanded = file.resolve_expanded_function_call(
                else_block.scope, statement.function_call)
            if maybe_expanded.is_ok:
              else_block.scope[$(statement.destination)] = new_argument_definition(
                  maybe_expanded.get.definition.return_type,
                  statement.destination)
              continue

            # try looking up user function call
            let fn = ? file.resolve_function_call(else_block.scope,
                statement.function_call)
            else_block.scope[$(statement.destination)] = new_argument_definition(
                fn.definition.return_type, statement.destination)
            function_set.incl(fn)

        let return_argument = else_block.statements[^1].destination
        let actual_return_type = else_block.scope[$(return_argument)].arg_type
        if match.return_type.is_none:
          match.return_type = some(actual_return_type)
        elif $(match.return_type.get) != $(actual_return_type):
          return err(fmt"{return_argument.location} `else` block is expected to return {match.return_type.get} but found {actual_return_type}")

      function.scope[$(match.destination)] = new_argument_definition(
          match.return_type.get, match.destination)
      # increment match index
      mindex += 1

  var actual_return_type: string
  # handle only match block
  if function.statements.len == 0:
    let return_argument = function.matches[^1][1].destination
    actual_return_type = $(function.scope[$(return_argument)].arg_type)
  # handle statements only function
  elif function.matches.len == 0:
    let return_argument = function.statements[^1][1].destination
    actual_return_type = $(function.scope[$(return_argument)].arg_type)
  else: # function contains both statements and match blocks
    # handle last statement
    if function.statements[^1][0] > function.matches[^1][0]:
      let return_argument = function.statements[^1][1].destination
      actual_return_type = $(function.scope[$(return_argument)].arg_type)
    # handle last match block
    else:
      let return_argument = function.matches[^1][1].destination
      actual_return_type = $(function.scope[$(return_argument)].arg_type)

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
