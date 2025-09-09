import results, tables, strformat, sequtils, parseutils, sets, options, strutils

import blocks/arg; export arg
import blocks/function_ref; export function_ref
import blocks/function_call; export function_call
import blocks/struct_init; export struct_init
import blocks/struct_getter; export struct_getter
import blocks/statement; export statement
import blocks/case_block; export case_block
import blocks/else_block; export else_block
import blocks/match; export match
import blocks/function_step; export function_step
import blocks/function; export function
import blocks/struct; export struct
import blocks/union; export union
import blocks/file; export file

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

# module function call arg resolution
proc resolve_argument(file: blocks.File, module: Module, scope: Table[string,
    ArgumentDefinition], arg_type: ArgumentType, arg_value: Token): Result[
    ResolvedArgument, string] =
  let maybe_arg_module = file.find_module(arg_type)
  if maybe_arg_module.is_ok:
    let arg_module = maybe_arg_module.get
    case arg_value.kind:
    of TK_ID:
      let resolved_variable = ? scope.resolve_variable(arg_value)
      if $(arg_module.name) == $(arg_type.parent): ok(new_resolved_argument(resolved_variable))
      else: err(fmt"1 {arg_value.location} expected {arg_type} but found {resolved_variable.typ}")
    else:
      case arg_module.kind:
      of MK_BUILTIN:
        let resolved_literal = ? arg_module.builtin_module.resolve_literal(arg_value)
        ok(new_resolved_argument(resolved_literal))
      of MK_USER:
        err(fmt"{arg_type.location} Module `{arg_type}` is a user module and therefore does not support literals")
  else:
    case module.kind:
    of MK_BUILTIN: err("1 UNREACHABLE")
    of MK_USER:
      let module = module.user_module
      let generic = ? module.find_generic(arg_type)
      case arg_value.kind:
      of TK_ID:
        let resolved_variable = ? scope.resolve_variable(arg_value)
        var argval_module_func_refs: HashSet[ResolvedFunctionRef]
        case generic.kind:
        of GDK_DEFAULT: discard
        of GDK_EXTENDED:
          let argval_module = ? file.find_module(resolved_variable.typ)
          for func_def in generic.constraints(argval_module.name):
            discard ? argval_module.find_function(func_def)
            case argval_module.kind:
            of MK_BUILTIN: discard
            of MK_USER:
              argval_module_func_refs.incl(new_resolved_function_ref(
                  argval_module.user_module, func_def))
        let generic_resolved_variable = new_resolved_variable(resolved_variable,
            generic.name, argval_module_func_refs)
        ok(new_resolved_argument(generic_resolved_variable))
      else:
        err(fmt"{arg_value.location} generic fields only support identifier as values")

# local function call arg resolution
proc resolve_argument(file: blocks.File, scope: Table[string,
    ArgumentDefinition], arg_type: ArgumentType, arg_value: Token): Result[
    ResolvedArgument, string] =
  let arg_module = ? file.find_module(arg_type)
  case arg_value.kind:
  of TK_ID:
    let resolved_variable = ? scope.resolve_variable(arg_value)
    if $(arg_module.name) == $(arg_type): ok(new_resolved_argument(resolved_variable))
    else: err(fmt"2 {arg_value.location} expected {arg_type} but found {resolved_variable.typ}")
  else:
    case arg_module.kind:
    of MK_BUILTIN:
      let resolved_literal = ? arg_module.builtin_module.resolve_literal(arg_value)
      ok(new_resolved_argument(resolved_literal))
    of MK_USER:
      err(fmt"{arg_type.location} Module `{arg_type}` is a user module and therefore does not support literals")

proc resolve_union_argument(file: blocks.File, scope: Table[string,
    ArgumentDefinition], arg_type: ArgumentType, arg_value: Token,
    module: UserModule): Result[ResolvedArgument, string] =
  # echo fmt"find_module: 1 {arg_type} {arg_value}"
  let maybe_module = file.find_module(arg_type)
  if maybe_module.is_ok:
    let module = maybe_module.get
    case arg_value.kind:
    of TK_ID:
      let resolved_variable = ? scope.resolve_variable(arg_value)
      if $(module.name) == $(arg_type): ok(new_resolved_argument(resolved_variable))
      else: err(fmt"3 {arg_value.location} expected {arg_type} but found {resolved_variable.typ}")
    else:
      case module.kind:
      of MK_BUILTIN:
        let resolved_literal = ? module.builtin_module.resolve_literal(arg_value)
        ok(new_resolved_argument(resolved_literal))
      of MK_USER:
        err(fmt"{arg_type.location} Module `{arg_type}` is a user module and therefore does not support literals")
  else:
    let generic = ? module.find_generic(arg_type)
    case arg_value.kind:
    of TK_ID:
      let resolved_variable = ? scope.resolve_variable(arg_value)
      var argval_module_func_refs: HashSet[ResolvedFunctionRef]
      case generic.kind:
      of GDK_DEFAULT:
        discard
      of GDK_EXTENDED:
        let argval_module = ? file.find_module(resolved_variable.typ)
        for func_def in generic.constraints(argval_module.name):
          discard ? argval_module.find_function(func_def)
          case argval_module.kind:
          of MK_BUILTIN: discard
          of MK_USER:
            argval_module_func_refs.incl(new_resolved_function_ref(
                argval_module.user_module, func_def))
      let generic_resolved_variable = new_resolved_variable(resolved_variable,
          generic.name, argval_module_func_refs)
      ok(new_resolved_argument(generic_resolved_variable))
    else:
      return err(fmt"{arg_value.location} generic fields only support identifier as values")

proc resolve_struct_init(file: blocks.File, scope: Table[string,
    ArgumentDefinition], struct_init: StructInit): Result[ResolvedStructInit, string] =
  # echo "find_module: 2"
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
        # echo "resolve_argument: 1"
        field_name_table[$(field_name)] = ? file.resolve_argument(module, scope,
            field.typ, field_value)

      let resolved_fields = struct.fields.map_it(field_name_table[
          $(it.name)])
      let resolved_struct_init = new_resolved_struct_init(module.user_module, resolved_fields)
      ok(resolved_struct_init)
    else: err(fmt"Builtin module `{module.name}` is can not be a struct")
  of MK_BUILTIN: err(fmt"Builtin module `{module.name}` is can not be a struct")

proc resolve_union_init(file: blocks.File, scope: Table[string,
    ArgumentDefinition], union_init: UnionInit,
    temp_var_count: var uint): Result[ResolvedUnionInit, string] =
  # echo "find_module: 3"
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
        # echo "resolve_argument: 2"
        field_name_table[$(field_name)] = ? file.resolve_union_argument(scope,
            field.typ, field_value, module.user_module)

      let resolved_fields = union_field.fields.to_seq.map_it(
          field_name_table[$(it.name)])

      let temp_var_start = temp_var_count
      for field in resolved_fields:
        case field.kind:
        of RAK_VARIABLE:
          case field.variable.kind:
          of RVK_GENERIC: temp_var_count += 1
          of RVK_DEFAULT: discard
        of RAK_LITERAL: discard
      let resolved_union_init = new_resolved_union_init(module.user_module,
          union_field, resolved_fields, temp_var_start)
      ok(resolved_union_init)
    else: err(fmt"Builtin module `{module.name}` is can not be a struct")
  of MK_BUILTIN: err(fmt"Builtin module `{module.name}` is can not be a struct")

proc resolve_struct_getter(file: blocks.File, scope: Table[string,
    ArgumentDefinition], struct_getter: StructGetter): Result[
    ResolvedStructGetter, string] =
  let struct_var = struct_getter.struct

  if $(struct_var) notin scope:
    return err(fmt"{struct_var.location} {struct_var} is not defined in the scope")

  # echo "find_module: 4"
  let module = ? file.find_module(scope[$(struct_var)].typ)
  case module.kind:
  of MK_BUILTIN: err(fmt"Builtin module `{module.name}` is can not be a struct")
  of MK_USER:
    let field = ? module.user_module.struct.find_field(struct_getter.field)
    ok(new_resolved_struct_getter(module.user_module, field, struct_var))

# matches individual function with function call
proc resolve_function_call_args(file: blocks.File, module: Module,
    scope: Table[string, ArgumentDefinition], function_call: FunctionCall,
    function_def: FunctionDefinition): Result[seq[ResolvedArgument], string] =
  if $(function_def.name) != $(function_call.name):
    return err(fmt"{function_call.location} expected function with name {function_call.name} but found {function_def.name}")
  if function_def.arg_def_list.len != function_call.arg_list.len:
    return err(fmt"{function_call.location} expected {function_def.arg_def_list.len} but found {function_call.arg_list.len}")

  var resolved_args: seq[ResolvedArgument]
  for (arg_def, arg_value) in zip(function_def.arg_def_list,
      function_call.arg_list):
    let resolved_arg = ? file.resolve_argument(module, scope, arg_def.typ, arg_value)
    resolved_args.add(resolved_arg)
  ok(resolved_args)

# module
proc resolve_function_call_args(file: blocks.File, module: Module, scope: Table[
    string, ArgumentDefinition], function_call: FunctionCall,
    function_defs: seq[FunctionDefinition]): Result[(FunctionDefinition, seq[
    ResolvedArgument]), string] =
  for function_def in function_defs:
    let maybe_resolved_args = file.resolve_function_call_args(module, scope,
        function_call, function_def)
    if maybe_resolved_args.is_ok:
      return ok((function_def, maybe_resolved_args.get))

  return err(fmt"{function_call.location} Failed to find match function for function call {function_call.func_ref}")

# local
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

# local
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
    ArgumentDefinition], module: Module, function_call: FunctionCall): Result[
    ResolvedFunctionCall, string] =
  let (func_def, resolved_args) = ? file.resolve_function_call_args(module,
      scope, function_call, module.builtin_module.functions)
  ok(new_resolved_function_call(module.builtin_module, func_def, resolved_args))

proc resolve_user_function_call(file: blocks.File, scope: Table[string,
    ArgumentDefinition], module: Module, function_call: FunctionCall,
    ): Result[ResolvedFunctionCall, string] =
  let function_defs = module.user_module.functions.map_it(it.definition)
  let (func_def, resolved_args) = ? file.resolve_function_call_args(module,
      scope, function_call, function_defs)
  ok(new_resolved_function_call(module.user_module, func_def, resolved_args))

proc resolve_generic_function_call(file: blocks.File, module: UserModule,
    generic: Generic, scope: Table[string, ArgumentDefinition],
    function_call: FunctionCall): Result[ResolvedFunctionCall, string] =
  case generic.kind:
  of GDK_DEFAULT:
    err(fmt"{function_call.location} Generic `{generic.name}` does not have any constraint matching the function call at {generic.location}")
  of GDK_EXTENDED:
    var arg_type_list: seq[ArgumentType]
    var resolved_args: seq[ResolvedArgument]
    for arg in function_call.arg_list:
      case arg.kind:
      of TK_ID:
        if $(arg) notin scope:
          return err("{arg.location} argument is not defined in scope")
        resolved_args.add(new_resolved_argument(new_resolved_variable(scope[$(arg)])))
        arg_type_list.add(scope[$(arg)].typ)
      else:
        return err("{function_call.func_ref.module.location} Generic function calls do not support literal as arguments")

    for func_def in generic.constraints:
      if $(func_def.name) != $(function_call.func_ref.name): continue
      if func_def.arg_def_list.len != function_call.arg_list.len: continue

      var matched = true
      for (expected_arg_def, actual_arg_type) in zip(func_def.arg_def_list,
          arg_type_list):
        if $(expected_arg_def.typ) != $(actual_arg_type):
          matched = false
          break

      if matched:
        return ok(new_resolved_function_call(generic.name, module.name,
            func_def, resolved_args))
    err(fmt"{function_call.location} Generic `{generic.name}` does not have any constraint matching the function call at {generic.location}")

proc resolve_module_function_call(file: blocks.File, scope: Table[string,
    ArgumentDefinition], function_call: FunctionCall): Result[
    ResolvedFunctionCall, string] =
  let module = ? file.find_module(function_call.func_ref.module)
  case module.kind:
  of MK_BUILTIN:
    file.resolve_builtin_function_call(scope, module, function_call)
  of MK_USER:
    file.resolve_user_function_call(scope, module, function_call)

# module
proc resolve_module_function_call(file: blocks.File, module: UserModule,
    scope: Table[string, ArgumentDefinition],
    function_call: FunctionCall): Result[ResolvedFunctionCall, string] =
  let maybe_generic = module.find_generic(function_call.func_ref.module)
  if maybe_generic.is_ok:
    file.resolve_generic_function_call(module, maybe_generic.get, scope, function_call)
  else:
    file.resolve_module_function_call(scope, function_call)

# local
proc resolve_local_function_call(file: blocks.File, scope: Table[string,
    ArgumentDefinition], function_call: FunctionCall): Result[
    ResolvedFunctionCall, string] =
  let function_defs = file.functions.map_it(it.definition)
  let (func_def, resolved_args) = ? file.resolve_function_call_args(
      scope, function_call, function_defs)
  ok(new_resolved_function_call(func_def, resolved_args))

# module
proc resolve_function_call(file: blocks.File, func_module: UserModule,
    scope: Table[string, ArgumentDefinition],
    function_call: FunctionCall): Result[ResolvedFunctionCall, string] =
  case function_call.func_ref.kind:
  of FRK_MODULE: file.resolve_module_function_call(func_module, scope, function_call)
  of FRK_LOCAL: file.resolve_local_function_call(scope, function_call)

# local
proc resolve_function_call(file: blocks.File, scope: Table[string,
    ArgumentDefinition], function_call: FunctionCall): Result[
    ResolvedFunctionCall, string] =
  case function_call.func_ref.kind:
  of FRK_MODULE: file.resolve_module_function_call(scope, function_call)
  of FRK_LOCAL: file.resolve_local_function_call(scope, function_call)

# module
proc resolve_expression(file: blocks.File, func_module: UserModule,
    scope: Table[string, ArgumentDefinition], temp_var_count: var uint,
    expression: Expression): Result[ResolvedExpression, string] =
  case expression.kind:
  of EK_VARIABLE:
    let resolved_variable = ? scope.resolve_variable(expression.variable)
    let resolved_argument = new_resolved_argument(resolved_variable)
    ok(new_resolved_expression(resolved_argument))
  of EK_STRUCT_INIT:
    let resolved_struct_init = ? file.resolve_struct_init(
        scope, expression.struct_init)
    ok(new_resolved_expression(resolved_struct_init))
  of EK_STRUCT_GETTER:
    let resolved_struct_getter = ? file.resolve_struct_getter(scope,
        expression.struct_getter)
    ok(new_resolved_expression(resolved_struct_getter))
  of EK_FUNCTION_CALL:
    let resolved_function_call = ? file.resolve_function_call(func_module,
        scope, expression.function_call)
    ok(new_resolved_expression(resolved_function_call))
  of EK_LITERAL_INIT:
    # echo "find_module: 5"
    let module = ? file.find_module(new_argument_type(
        expression.literal_init.arg_type))
    case module.kind:
    of MK_BUILTIN:
      let resolved_literal = ? module.builtin_module.resolve_literal(
          expression.literal_init.arg_value)
      let resolved_argument = new_resolved_argument(resolved_literal)
      ok(new_resolved_expression(resolved_argument))
    of MK_USER:
      err(fmt"{expression.literal_init.arg_type.location} Module `{expression.literal_init.arg_type}` is a user module and therefore does not support literals")
  of EK_UNION_INIT:
    let resolved_union_init = ? file.resolve_union_init(scope,
        expression.union_init, temp_var_count)
    ok(new_resolved_expression(resolved_union_init))

# local
proc resolve_expression(file: blocks.File, scope: Table[string,
    ArgumentDefinition], temp_var_count: var uint,
    expression: Expression): Result[ResolvedExpression, string] =
  case expression.kind:
  of EK_VARIABLE:
    let resolved_variable = ? scope.resolve_variable(expression.variable)
    let resolved_argument = new_resolved_argument(resolved_variable)
    ok(new_resolved_expression(resolved_argument))
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
    let module = ? file.find_module(new_argument_type(
        expression.literal_init.arg_type))
    case module.kind:
    of MK_BUILTIN:
      let resolved_literal = ? module.builtin_module.resolve_literal(
          expression.literal_init.arg_value)
      let resolved_argument = new_resolved_argument(resolved_literal)
      ok(new_resolved_expression(resolved_argument))
    of MK_USER:
      err(fmt"{expression.literal_init.arg_type.location} Module `{expression.literal_init.arg_type}` is a user module and therefore does not support literals")
  of EK_UNION_INIT:
    let resolved_union_init = ? file.resolve_union_init(scope,
        expression.union_init, temp_var_count)
    ok(new_resolved_expression(resolved_union_init))

proc resolve_union_pattern_fields(scope: Table[string, ArgumentDefinition],
    union_def: UnionFieldDefinition, union_pattern: UnionPattern): Result[seq[(
        ArgumentDefinition, Token)], string] =
  # Union pattern can destructure all/subset of the defined union fields
  # must be unique for the destructured pattern.
  var union_def_field_name_set: Table[string, Token]
  var union_def_field_value_set: Table[string, Token]
  var pattern_fields: seq[(ArgumentDefinition, Token)]
  for (field_name, field_value) in union_pattern.fields:
    # field name checks
    if $(field_name) in union_def_field_name_set:
      let predefined_location = union_def_field_name_set[$(
          field_name)].location
      return err(fmt"{field_name.location} field `{field_name}` is already used in {predefined_location}")
    let field = ? union_def.find_field(field_name)
    union_def_field_name_set[$(field_name)] = field_name

    # field value checks
    if $(field_value) in union_def_field_value_set:
      let predefined_location = union_def_field_value_set[$(
          field_value)].location
      return err(fmt"{field_value.location} field `{field_value}` is already used in {predefined_location}")
    if $(field_value) in scope:
      let predefined_location = scope[$(field_value)].location
      return err(fmt"{field_value.location} field `{field_value}` is already defined at {predefined_location}")

    let arg = new_argument_definition(field.typ, field_value)
    pattern_fields.add((arg, field_name))
  ok(pattern_fields)

proc resolve_union_pattern(scope: Table[string, ArgumentDefinition],
    match: Match, module: UserModule): Result[seq[ResolvedPattern], string] =
  # All case pattern must be union patterns
  let first_non_union_pattern_index = match.case_blocks.map_it(
      it.pattern.kind == PK_UNION).find(false)
  if first_non_union_pattern_index != -1:
    let non_union_pattern_location = match.case_blocks[
        first_non_union_pattern_index].location
    return err(fmt"{non_union_pattern_location} expected a union pattern of type `{module.name}`")

  let union = module.union
  let union_patterns = match.case_blocks.map_it(it.pattern.union)
  var union_field_id_set: Table[int, UnionPattern]
  var resolved_patterns: seq[ResolvedPattern]

  for upat in union_patterns:
    # Union pattern must belong to the module's union field.
    let union_id = ? union.find_field_id(upat.name)
    if union_id in union_field_id_set:
      let predefined_location = union_field_id_set[union_id].location
      return err(fmt"{upat.location} is unreachable due to predefined duplicate case block `{predefined_location}`")

    union_field_id_set[union_id] = upat
    let pattern_fields = ? resolve_union_pattern_fields(scope, union.fields[
        union_id], upat)

    resolved_patterns.add(new_resolved_pattern(module.name, upat.name, union_id,
        pattern_fields))

  # if case blocks do not cover all the union branches,
  # then match block must always have an else block.
  if union_field_id_set.len < union.fields.len and match.else_blocks.len == 0:
    err(fmt"{match.operand.location} matching partial union pattern requires the `else` block")
  else:
    ok(resolved_patterns)

proc resolve_literal_pattern[IntType](match: Match, literal_patterns: seq[
    Token], module: BuiltinModule): Result[seq[ResolvedPattern], string] =
  var intset: Table[IntType, Token]
  var patterns: seq[ResolvedPattern]
  for lpat in literal_patterns:
    # All the case block patterns must be castable to the respective integer module
    patterns.add(new_resolved_pattern( ? module.resolve_integer_literal(lpat)))
    # All case pattern must contain unique values
    let intval = ? safe_parse[IntType]($(lpat))
    if intval in intset:
      let predefined_location = intset[intval].location
      return err(fmt"{lpat.location} is unreachable due to predefined duplicate case block `{predefined_location}`")
    intset[intval] = lpat

  # There must always be an else block, because it is not humanely
  # possible to have case block for every integer value
  if match.else_blocks.len == 0:
    err(fmt"{match.operand.location} matching integer literal requires the `else` block")
  else:
    ok(patterns)

proc resolve_literal_pattern(match: Match, module: BuiltinModule): Result[
    seq[ResolvedPattern], string] =
  # All case pattern must be integer literal patterns
  let first_non_literal_pattern_index = match.case_blocks.map_it(
        it.pattern.kind == PK_LITERAL).find(false)
  if first_non_literal_pattern_index != -1:
    let non_union_pattern_location = match.case_blocks[
        first_non_literal_pattern_index].location
    return err(fmt"{non_union_pattern_location} expected a integer literal of type `{module.name}`")

  let literal_patterns = match.case_blocks.map_it(it.pattern.literal)
  case $(module.name):
  of "S8", "S16", "S32", "S64":
    resolve_literal_pattern[int64](match, literal_patterns, module)
  of "U8", "U16", "U32", "U64":
    resolve_literal_pattern[uint64](match, literal_patterns, module)
  of "F32", "F64":
    err(fmt"{match.operand.location} `match` does not support floating point values `{match.operand}`")
  else:
    err("MATCH RESOLUTION: UNREACHABLE")

# module
proc resolve_statement(file: blocks.File, func_module: UserModule, scope: Table[
    string, ArgumentDefinition], temp_var_count: var uint,
        statement: Statement): Result[ResolvedStatement, string] =
  case statement.kind:
  of SK_ASSIGNMENT:
    if $(statement.destination) in scope:
      let defined_arg = scope[$(statement.destination)]
      return err(fmt"{statement.destination.location} {statement.destination} is already defined {defined_arg.location}")

    let resolved_expression = ? file.resolve_expression(func_module, scope,
        temp_var_count, statement.expression)
    ok(new_resolved_statement(statement.destination, resolved_expression))
  of SK_EXPRESSION:
    # assign the expresssion value to a temporary variable injected by the compiler
    let assignment = statement.set_destination(fmt"__asl_temp_var_{temp_var_count}__")
    temp_var_count += 1
    let resolved_expression = ? file.resolve_expression(func_module, scope,
        temp_var_count, assignment.expression)
    ok(new_resolved_statement(assignment.destination, resolved_expression))

# local
proc resolve_statement(file: blocks.File, scope: Table[string,
    ArgumentDefinition], temp_var_count: var uint,
    statement: Statement): Result[ResolvedStatement, string] =
  case statement.kind:
  of SK_ASSIGNMENT:
    if $(statement.destination) in scope:
      let defined_arg = scope[$(statement.destination)]
      return err(fmt"{statement.destination.location} {statement.destination} is already defined {defined_arg.location}")

    let resolved_expression = ? file.resolve_expression(scope, temp_var_count,
        statement.expression)
    ok(new_resolved_statement(statement.destination, resolved_expression))
  of SK_EXPRESSION:
    # assign the expresssion value to a temporary variable injected by the compiler
    let assignment = statement.set_destination(fmt"__asl_temp_var_{temp_var_count}__")
    temp_var_count += 1
    let resolved_expression = ? file.resolve_expression(scope, temp_var_count,
        assignment.expression)
    ok(new_resolved_statement(assignment.destination, resolved_expression))

# module
proc resolve_case_block(file: blocks.File, func_module: UserModule,
    parent_scope: Table[string, ArgumentDefinition],
    resolved_pattern: ResolvedPattern,
    temp_var_count: var uint, operand: ArgumentDefinition,
        case_block: Case): Result[ResolvedCase, string] =
  var resolved_statements: seq[ResolvedStatement]
  # copy current function scope to the case scope to avoid non local argument name conflicts
  var scope = parent_scope
  for arg in resolved_pattern.args:
    scope[$(arg.name)] = arg
  for (index, statement) in case_block.statements.pairs:
    let resolved_statement = ? file.resolve_statement(func_module, scope,
        temp_var_count, statement)
    resolved_statements.add(resolved_statement)
    scope[$(resolved_statement.destination)] = resolved_statement.return_argument

  return ok(new_resolved_case(resolved_pattern, operand.name,
      resolved_statements))

# local
proc resolve_case_block(file: blocks.File, parent_scope: Table[string,
    ArgumentDefinition], resolved_pattern: ResolvedPattern,
    temp_var_count: var uint, operand: ArgumentDefinition,
    case_block: Case): Result[ResolvedCase, string] =
  var resolved_statements: seq[ResolvedStatement]
  # copy current function scope to the case scope to avoid non local argument name conflicts
  var scope = parent_scope
  for arg in resolved_pattern.args:
    scope[$(arg.name)] = arg
  for (index, statement) in case_block.statements.pairs:
    let resolved_statement = ? file.resolve_statement(scope, temp_var_count, statement)
    resolved_statements.add(resolved_statement)
    scope[$(resolved_statement.destination)] = resolved_statement.return_argument

  return ok(new_resolved_case(resolved_pattern, operand.name,
      resolved_statements))

# module
proc resolve_else_block(file: blocks.File, func_module: UserModule,
    parent_scope: Table[string, ArgumentDefinition], temp_var_count: var uint,
        else_block: Else): Result[
    ResolvedElse, string] =
  var resolved_statements: seq[ResolvedStatement]
  # copy current function scope to the else scope to avoid non local argument name conflicts
  var scope = parent_scope
  for (index, statement) in else_block.statements.pairs:
    let resolved_statement = ? file.resolve_statement(func_module, scope,
        temp_var_count, statement)
    resolved_statements.add(resolved_statement)
    scope[$(resolved_statement.destination)] = resolved_statement.return_argument

  return ok(new_resolved_else(resolved_statements))

# local
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

# module
proc resolve_match(file: blocks.File, func_module: UserModule, scope: Table[
    string, ArgumentDefinition], temp_var_count: var uint,
    match: Match): Result[ResolvedMatch, string] =
  if $(match.operand) notin scope:
    return err(fmt"{match.operand.location} variable `{match.operand}` is not defined in scope")

  let operand_def = scope[$(match.operand)]
  let operand_module = ? file.find_module(operand_def.typ)

  var resolved_patterns: seq[ResolvedPattern]
  case operand_module.kind:
  of MK_BUILTIN:
    resolved_patterns = ? resolve_literal_pattern(match,
        operand_module.builtin_module)
  of MK_USER:
    let user_module = operand_module.user_module
    case user_module.kind:
    of UMK_UNION: resolved_patterns = ? scope.resolve_union_pattern(match, user_module)
    of UMK_STRUCT: return err(fmt"{match.operand.location} `match` does not support struct values `{match.operand}`")
    of UMK_DEFAULT: return err("MATCH RESOLUTION: UNREACHABLE")

  var resolved_case_blocks: seq[ResolvedCase]
  var resolved_else_blocks: seq[ResolvedElse]
  if $(match.destination) in scope:
    let defined_arg = scope[$(match.destination)]
    return err(fmt"{match.destination.location} {match.destination} is already defined {defined_arg.location}")

  for index, case_block in match.case_blocks.pairs:
    let resolved_case_block = ? file.resolve_case_block(func_module, scope,
        resolved_patterns[index], temp_var_count, operand_def, case_block)
    resolved_case_blocks.add(resolved_case_block)

  # Note: Even though this is a for loop but there can only be at most 1 else block.
  for else_block in match.else_blocks:
    let resolved_else_block = ? file.resolve_else_block(func_module, scope,
        temp_var_count, else_block)
    resolved_else_blocks.add(resolved_else_block)

  let return_type = resolved_case_blocks[0].return_argument.typ
  let case_return_args = resolved_case_blocks.map_it(it.return_argument)
  let else_return_args = resolved_else_blocks.map_it(it.return_argument)
  for return_arg in (case_return_args & else_return_args):
    if $(return_type) != $(return_arg.typ):
      return err(fmt"{return_arg.location} block is expected to return {return_type} but found {return_arg.typ}")

  let return_argument = new_argument_definition(return_type, match.destination)
  ok(new_resolved_match(match, match.destination, operand_def,
      resolved_case_blocks, resolved_else_blocks, return_argument))

# local
proc resolve_match(file: blocks.File, scope: Table[string, ArgumentDefinition],
    temp_var_count: var uint, match: Match): Result[ResolvedMatch, string] =
  if $(match.operand) notin scope:
    return err(fmt"{match.operand.location} variable `{match.operand}` is not defined in scope")

  let operand_def = scope[$(match.operand)]
  # echo "find_module: 6"
  let operand_module = ? file.find_module(operand_def.typ)

  var resolved_patterns: seq[ResolvedPattern]
  case operand_module.kind:
  of MK_BUILTIN:
    resolved_patterns = ? resolve_literal_pattern(match,
        operand_module.builtin_module)
  of MK_USER:
    let user_module = operand_module.user_module
    case user_module.kind:
    of UMK_UNION: resolved_patterns = ? scope.resolve_union_pattern(match, user_module)
    of UMK_STRUCT: return err(fmt"{match.operand.location} `match` does not support struct values `{match.operand}`")
    of UMK_DEFAULT: return err("MATCH RESOLUTION: UNREACHABLE")

  var resolved_case_blocks: seq[ResolvedCase]
  var resolved_else_blocks: seq[ResolvedElse]
  if $(match.destination) in scope:
    let defined_arg = scope[$(match.destination)]
    return err(fmt"{match.destination.location} {match.destination} is already defined {defined_arg.location}")

  for index, case_block in match.case_blocks.pairs:
    let resolved_case_block = ? file.resolve_case_block(scope,
        resolved_patterns[index], temp_var_count, operand_def, case_block)
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
  ok(new_resolved_match(match, match.destination, operand_def,
      resolved_case_blocks, resolved_else_blocks, return_argument))

# module
proc resolve_function_step(file: blocks.File, module: UserModule, scope: Table[
    string, ArgumentDefinition], temp_var_count: var uint,
    step: FunctionStep): Result[ResolvedFunctionStep, string] =
  case step.kind:
  of FSK_STATEMENT:
    let resolved_statement = ? file.resolve_statement(module, scope,
        temp_var_count, step.statement)
    ok(new_resolved_function_step(resolved_statement))
  of FSK_MATCH:
    let resolved_match = ? file.resolve_match(module, scope, temp_var_count, step.match)
    ok(new_resolved_function_step(resolved_match))

# local
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
    ok(new_resolved_function_step(resolved_match))

# module
proc resolve_argument_type(file: blocks.File, module: UserModule,
    arg_type: ArgumentType): Result[ResolvedArgumentType, string] =
  let maybe_module = file.find_module(arg_type)
  if maybe_module.is_ok:
    let arg_module = maybe_module.get
    var resolved_children_arg_types: seq[ResolvedArgumentType]
    for child_arg_type in arg_type.children:
      # TODO: Make sure `child_arg_type` also satisfies all the generic constraints
      let resolved_child_arg_type = ? file.resolve_argument_type(module, child_arg_type)
      resolved_children_arg_types.add(resolved_child_arg_type)
    ok(new_resolved_argument_type(arg_module, resolved_children_arg_types))
  else:
    let generic = ? module.find_generic(arg_type)
    let resolved_generic = new_resolved_generic(module, generic)
    ok(new_resolved_argument_type(resolved_generic))

# local
proc resolve_argument_type(file: blocks.File, arg_type: ArgumentType): Result[
    ResolvedArgumentType, string] =
  let module = ? file.find_module(arg_type)
  var resolved_children_arg_types: seq[ResolvedArgumentType]
  for child_arg_type in arg_type.children:
    # TODO: Make sure `child_arg_type` also satisfies all the generic constraints
    let resolved_child_arg_type = ? file.resolve_argument_type(child_arg_type)
    resolved_children_arg_types.add(resolved_child_arg_type)
  ok(new_resolved_argument_type(module, resolved_children_arg_types))

# module
proc resolve_argument_definition(file: blocks.File, module: UserModule,
    arg_def: ArgumentDefinition): Result[ResolvedArgumentDefinition, string] =
  let resolved_arg_type = ? file.resolve_argument_type(module, arg_def.typ)
  ok(new_resolved_argument_definition(arg_def.name, resolved_arg_type))

# local
proc resolve_argument_definition(file: blocks.File,
    arg_def: ArgumentDefinition): Result[ResolvedArgumentDefinition, string] =
  let resolved_arg_type = ? file.resolve_argument_type(arg_def.typ)
  ok(new_resolved_argument_definition(arg_def.name, resolved_arg_type))

# module
proc resolve_function_definition(file: blocks.File, module: UserModule,
    function_def: FunctionDefinition): Result[(ResolvedFunctionDefinition,
        Table[string, ArgumentDefinition]), string] =
  var scope: Table[string, ArgumentDefinition]
  var resolved_arg_defs: seq[ResolvedArgumentDefinition]
  for arg_def in function_def.arg_def_list:
    # arg_def.name uniqueness check
    if $(arg_def.name) in scope:
      let defined_arg = scope[$(arg_def.name)]
      return err(fmt"{arg_def.location} {arg_def.name} is already defined {defined_arg.location}")
    scope[$(arg_def.name)] = arg_def

    # resolution
    let resolved_arg_def = ? file.resolve_argument_definition(module, arg_def)
    resolved_arg_defs.add(resolved_arg_def)

  let return_module = ? file.find_module(function_def.return_type)
  let resolved_func_def = new_resolved_function_definition(function_def.name,
      resolved_arg_defs, return_module)
  ok((resolved_func_def, scope))

# local
proc resolve_function_definition(file: blocks.File,
    func_def: FunctionDefinition): Result[(ResolvedFunctionDefinition, Table[
    string, ArgumentDefinition]), string] =
  var scope: Table[string, ArgumentDefinition]
  var resolved_arg_defs: seq[ResolvedArgumentDefinition]

  for arg_def in func_def.arg_def_list:
    # arg_def.name uniqueness check
    if $(arg_def.name) in scope:
      let defined_arg = scope[$(arg_def.name)]
      return err(fmt"{arg_def.location} {arg_def.name} is already defined {defined_arg.location}")
    scope[$(arg_def.name)] = arg_def

    # resolution
    let resolved_arg_def = ? file.resolve_argument_definition(arg_def)
    resolved_arg_defs.add(resolved_arg_def)

  let return_module = ? file.find_module(func_def.return_type)
  ok((new_resolved_function_definition(func_def.name, resolved_arg_defs,
      return_module), scope))

# module
proc resolve_function(file: blocks.File, module: UserModule, function: Function,
    function_ref: ResolvedFunctionRef): Result[ResolvedFunction, string] =
  var temp_var_count: uint = 0
  var resolved_function_steps: seq[ResolvedFunctionStep]
  var (resolved_function_def, scope) = ? file.resolve_function_definition(
      module, function.definition)

  for (index, step) in function.function_steps.pairs:
    let resolved_function_step = ? file.resolve_function_step(module, scope,
        temp_var_count, step)
    resolved_function_steps.add(resolved_function_step)
    scope[$(resolved_function_step.destination)] = resolved_function_step.return_argument

  let expected_return_type = resolved_function_def.return_type
  let actual_return_type = resolved_function_steps[^1].return_argument.typ
  if $(expected_return_type.name) != $(actual_return_type):
    return err(fmt"{function.location} expected {function.name} to return {expected_return_type.name} but found {actual_return_type}")
  ok(new_resolved_function(function_ref, function, resolved_function_steps))

# local
proc resolve_function(file: blocks.File, function: Function,
    function_ref: ResolvedFunctionRef): Result[ResolvedFunction, string] =
  var
    temp_var_count: uint = 0
    resolved_function_steps: seq[ResolvedFunctionStep]

  var (resolved_function_definition, scope) = ?
    file.resolve_function_definition(function.definition)

  for (index, step) in function.function_steps.pairs:
    let resolved_function_step = ? file.resolve_function_step(scope,
        temp_var_count, step)
    resolved_function_steps.add(resolved_function_step)
    scope[$(resolved_function_step.destination)] = resolved_function_step.return_argument

  let expected_return_type = resolved_function_definition.return_type
  let actual_return_type = resolved_function_steps[^1].return_argument.typ
  if $(actual_return_type) != $(expected_return_type.name):
    return err(fmt"{function.location} Expected function to return `{expected_return_type.name}` but found {actual_return_type}")
  ok(new_resolved_function(function_ref, function, resolved_function_steps))

proc resolve_function_ref(file: blocks.File,
    function_ref: ResolvedFunctionRef): Result[ResolvedFunction, string] =
  case function_ref.kind:
  of RFRK_MODULE:
    let module = ? file.find_module(new_argument_type(function_ref.module_name))
    case module.kind:
    of MK_BUILTIN:
      err(fmt"Builtin module `{module.name}` does not require resolution.")
    of MK_USER:
      let function = ? module.user_module.find_function(
          function_ref.function_def)
      file.resolve_function(module.user_module, function, function_ref)
  of RFRK_FUNCTION:
    let function = ? file.find_function(function_ref.function_def)
    file.resolve_function(function, function_ref)

proc resolve_unused_functions(file: blocks.File, visited_functions: HashSet[
    ResolvedFunctionRef]): Result[void, string] =
  for function in file.functions:
    let func_ref = new_resolved_function_ref(function.definition)
    if func_ref notin visited_functions:
      echo fmt"Unused function: {function.location} {function.name}"
      discard ? file.resolve_function_ref(func_ref)

  for module in file.user_modules:
    for function in module.functions:
      let func_ref = new_resolved_function_ref(module,
          function.definition)
      if func_ref notin visited_functions:
        echo fmt"Unused function: {function.location} {module.name}.{function.name}"
        discard ? file.resolve_function_ref(func_ref)
  ok()

proc resolve_functions(file: blocks.File): Result[(seq[ResolvedFunction], Table[
    string, Table[string, HashSet[string]]]), string] =
  let start_fn_def = new_function_definition("start", @[("U8", "argc")], "U8")
  let start_function = ? file.find_function(start_fn_def)

  var
    stack = @[new_resolved_function_ref(start_function.definition)]
    visited_function_refs = init_hashset[ResolvedFunctionRef]()
    resolved_functions: seq[ResolvedFunction]
    generic_impls: Table[string, Table[string, HashSet[string]]]

  while stack.len > 0:
    let function_ref = stack[^1]
    visited_function_refs.incl(function_ref)
    stack.set_len(stack.len - 1)

    let resolved_function = ? file.resolve_function_ref(function_ref)
    let new_functions = resolved_function.function_refs.difference(visited_function_refs)
    for (module_name, impl_map) in resolved_function.generic_impls.pairs:
      if module_name notin generic_impls:
        generic_impls[module_name] = init_table[string, HashSet[string]]()
      for (generic, concrete) in impl_map.pairs:
        if generic notin generic_impls[module_name]:
          generic_impls[module_name][generic] = init_hashset[string]()
        generic_impls[module_name][generic].incl(concrete)

    resolved_functions.add(resolved_function)
    stack.add(new_functions.to_seq)

  ? file.resolve_unused_functions(visited_function_refs)
  ok((resolved_functions, generic_impls))

# TODO: Use generic impls in struct resolution
proc resolve_user_module_struct(file: blocks.File, module: UserModule,
    struct: Struct, generic_impls: Table[string, Table[string, HashSet[
        string]]]): Result[ResolvedStruct, string] =
  for (name, field) in struct.fields.pairs:
    # echo "find_module: 10"
    let maybe_module = file.find_module(field.typ)
    if maybe_module.is_ok:
      discard
    else:
      discard ? module.find_generic(field.typ)

  if $(module.name) in generic_impls:
    # NOTE: Generic types are nothing but unions implemented by the user
    # of the library, so internally compiler collects all the concrete types
    # turns them into a union therefore uses the limit of 256 union branches
    # That means if a generic has more than 256 (id field is of 1 byte)
    # implementations, just raise error for now.
    for (generic, concrete) in generic_impls[$(module.name)].pairs:
      if concrete.len > 256:
        return err(fmt"{module.location} Generic `{generic}` types can have at max 256 implementations but found {concrete.len}")
    ok(new_resolved_struct(module, struct, generic_impls[$(module.name)]))
  else:
    ok(new_resolved_struct(module, struct))

# TODO: Use generic impls in union resolution
proc resolve_user_module_union(file: blocks.File, module: UserModule,
    union: Union, generic_impls: Table[string, Table[string, HashSet[
        string]]]): Result[ResolvedUnion, string] =
  for (_, struct) in union.fields.pairs:
    for (_, field) in struct.fields.pairs:
      # echo "find_module: 11"
      let maybe_module = file.find_module(field.typ)
      if maybe_module.is_ok:
        discard
      else:
        discard ? module.find_generic(field.typ)

  if $(module.name) in generic_impls:
    # NOTE: Generic types are nothing but unions implemented by the user
    # of the library, so internally compiler collects all the concrete types
    # turns them into a union therefore uses the limit of 256 union branches
    # That means if a generic has more than 256 (id field is of 1 byte)
    # implementations, just raise error for now.
    for (generic, concrete) in generic_impls[$(module.name)].pairs:
      if concrete.len > 256:
        return err(fmt"{module.location} Generic `{generic}` types can have at max 256 implementations but found {concrete.len}")

    ok(new_resolved_union(module, union, generic_impls[$(module.name)]))
  else:
    ok(new_resolved_union(module, union))

proc resolve_user_module(file: blocks.File, module: UserModule,
    generic_impls: Table[string, Table[string, HashSet[string]]]): Result[
        ResolvedUserModule, string] =
  case module.kind:
  of UMK_DEFAULT:
    err(fmt"{module.location} Module `{module.name}` is neither a struct nor union")
  of UMK_STRUCT:
    let struct = ? file.resolve_user_module_struct(module, module.struct, generic_impls)
    ok(new_resolved_user_module(struct))
  of UMK_UNION:
    let union = ? file.resolve_user_module_union(module, module.union, generic_impls)
    ok(new_resolved_user_module(union))

proc resolve_user_modules(file: blocks.File, generic_impls: Table[string, Table[
    string, HashSet[string]]]): Result[seq[ResolvedUserModule], string] =
  var resolved_user_modules: seq[ResolvedUserModule]
  for module in file.user_modules:
    case module.kind:
    of UMK_DEFAULT: discard # Module without any struct or union
    else: resolved_user_modules.add( ? file.resolve_user_module(module,
        generic_impls))
  return ok(resolved_user_modules)

proc resolve*(file: blocks.File): Result[ResolvedFile, string] =
  let (resolved_functions, generic_impls) = ? file.resolve_functions()
  let resolved_user_modules = ? file.resolve_user_modules(generic_impls)
  ok(new_resolved_file(resolved_user_modules, resolved_functions))
