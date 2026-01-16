import results, strformat, tables, strutils, sets, algorithm, options, sequtils,
    hashes, parseutils

import deps_analyzer/typed_file
export typed_file

# NOTE: Cycle detection algo
proc detect_cycle[T](graph: Table[T, HashSet[T]], node: T,
    visited: var OrderedSet[T], ancestors: var OrderedSet[T], stack: var seq[
    T]): Result[seq[T], OrderedSet[T]] =
  if node in ancestors: return err(ancestors)
  if node in visited: return ok(stack)
  visited.incl(node)
  ancestors.incl(node)
  stack.add(node)
  for child in graph[node]:
    # NOTE: Graph may have self cycles since a module can
    # depend on itself for recursive dependencies. Other
    # than that no circular dependencies are allowed.
    if child == node: continue
    stack = ? detect_cycle(graph, child, visited, ancestors, stack)
  ancestors.excl(node)
  ok(stack)

# NOTE: weird api
# "ok" returns topologicaly sorted nodes basically module resolution order
# "error" returns the cycle in order of nodes as they come up.
proc detect_cycle[T](graph: Table[T, HashSet[T]]): Result[seq[T], seq[T]] =
  var visited: OrderedSet[T]
  var ordered_nodes: seq[T]
  for node in graph.keys:
    if node notin visited:
      var ancestors: OrderedSet[T]
      var stack: seq[T]
      let maybe_dag = detect_cycle(graph, node, visited, ancestors, stack)
      if maybe_dag.is_err: return err(maybe_dag.error.to_seq)
      ordered_nodes.add(maybe_dag.get.reversed)
  ok(ordered_nodes)

# Numeric literal parser utility
proc safe_parse[T](input: string): Result[void, string] =
  when T is SomeSignedInt:
    var temp: BiggestInt
    let code = parse_biggest_int(input, temp)
    if code == 0 or code != input.len:
      return err("Failed to parse signed int from: " & input)
    if temp < T.low.BiggestInt or temp > T.high.BiggestInt:
      return err("Overflow: Value out of range for type " & $T)
    ok() # ok(T(temp))
  elif T is SomeUnsignedInt:
    var temp: BiggestUInt
    let code = parse_biggest_uint(input, temp)
    if code == 0 or code != input.len:
      return err("Failed to parse unsigned int from: " & input)
    if temp < T.low.BiggestUInt or temp > T.high.BiggestUInt:
      return err("Overflow: Value out of range for type " & $T)
    ok() # ok(T(temp))
  elif T is SomeFloat:
    var temp: BiggestFloat
    let code = parse_biggest_float(input, temp)
    if code == 0 or code != input.len:
      return err("Failed to parse float from: " & input)
    let casted = T(temp)
    if BiggestFloat(casted) != temp:
      return err("Precision loss when converting to " & $T)
    ok() # ok(T(temp))
  else:
    err("safe_parse only supports signed/unsigned integers and floating-point types")

# NOTE: This is a utility function to internally add some function definitions
# like `byte_size`, `read`, `write`
proc make_typed_module_ref(file: parser.File, module_name: string): Result[
    TypedModuleRef, string] =
  let module_id = new_identifier(module_name)
  let module = ? file.find_module(module_id)
  case module.kind:
  of MK_NATIVE:
    let native_module = ? module.native_module
    ok(new_typed_module_ref(native_module, Location()))
  of MK_USER:
    let user_module = ? module.user_module
    let user_module_ref = new_typed_module_ref(user_module, Location())
    ok(user_module_ref.self)

# NOTE: This is a utility function to internally add some function definitions
# like `byte_size`, `read`, `write`
proc make_typed_arg_def(file: parser.File, module_name: string,
    arg_name: string): Result[TypedArgumentDefinition, string] =
  let arg_module_ref = ? make_typed_module_ref(file, module_name)
  let arg_name_id = new_identifier(arg_name)
  ok(new_typed_argument_definition(arg_module_ref, arg_name_id))

# NOTE: This is a utility function to internally add some function definitions
# like `byte_size`, `read`, `write`
proc make_typed_function_def(file: parser.File, name: string, args: seq[(string,
    string)], returns: string): Result[TypedFunctionDefinition, string] =
  let name_id = new_identifier(name)
  let returns_module_ref = ? make_typed_module_ref(file, returns)
  var typed_arg_defs: seq[TypedArgumentDefinition]
  for (arg_module, arg_name) in args:
    typed_arg_defs.add( ? make_typed_arg_def(file, arg_module, arg_name))
  ok(new_typed_function_definition(name_id, typed_arg_defs, returns_module_ref,
      Location()))

# Helper to create TypedModuleRef from a Module (handles kind dispatch)
proc typed_module_ref_from_module(arg_module: parser.Module,
    children: seq[TypedModuleRef], location: Location): Result[TypedModuleRef, string] =
  case arg_module.kind:
  of MK_NATIVE:
    let native_module = ? arg_module.native_module
    ok(new_typed_module_ref(native_module, children, location))
  of MK_USER:
    let user_module = ? arg_module.user_module
    ok(new_typed_module_ref(user_module, children, location))

proc typed_module_ref_from_module(arg_module: parser.Module,
    location: Location): Result[TypedModuleRef, string] =
  case arg_module.kind:
  of MK_NATIVE:
    let native_module = ? arg_module.native_module
    ok(new_typed_module_ref(native_module, location))
  of MK_USER:
    let user_module = ? arg_module.user_module
    ok(new_typed_module_ref(user_module, location))

# Main helpers using Module type
proc assign_type(file: parser.File, module: parser.Module,
    module_name: Identifier): Result[TypedModuleRef, string] =
  let payload = module.payload
  let gm = payload.generics_map
  if module_name in gm:
    let generic = payload.generics[gm[module_name]]
    return ok(new_typed_module_ref(generic, module_name.location))
  let arg_module = ? file.find_module(module_name)
  typed_module_ref_from_module(arg_module, module_name.location)

# Forward declaration for no-module variant
proc assign_type(file: parser.File, module_name: Identifier): Result[
    TypedModuleRef, string]

proc assign_type(file: parser.File, module: parser.Module,
    module_ref: ModuleRef): Result[TypedModuleRef, string] =
  case module_ref.kind:
  of MRK_SIMPLE:
    assign_type(file, module, module_ref.module)
  of MRK_NESTED:
    let arg_module = ? file.find_module(module_ref.module)
    var typed_children: seq[TypedModuleRef]
    for child in module_ref.children:
      let typed_child = ? assign_type(file, module, child)
      typed_children.add(typed_child)
    typed_module_ref_from_module(arg_module, typed_children,
        module_ref.location)
proc assign_type(file: parser.File, module_ref: ModuleRef): Result[
    TypedModuleRef, string] =
  case module_ref.kind:
  of MRK_SIMPLE:
    assign_type(file, module_ref.module)
  of MRK_NESTED:
    let arg_module = ? file.find_module(module_ref.module)
    var typed_children: seq[TypedModuleRef]
    for child in module_ref.children:
      let typed_child = ? assign_type(file, child)
      typed_children.add(typed_child)
    typed_module_ref_from_module(arg_module, typed_children,
        module_ref.location)

# No-module context for module name
proc assign_type(file: parser.File, module_name: Identifier): Result[
    TypedModuleRef, string] =
  let arg_module = ? file.find_module(module_name)
  typed_module_ref_from_module(arg_module, module_name.location)

# ArgumentDefinition - unified with optional module
proc assign_type(file: parser.File, module: parser.Module, generic: Generic,
    arg: ArgumentDefinition): Result[TypedArgumentDefinition, string] =
  let typed_arg = ? assign_type(file, module, arg.module_ref)
  ok(new_typed_argument_definition(typed_arg, arg.name))

proc assign_type(file: parser.File, module: parser.Module,
    arg: ArgumentDefinition): Result[TypedArgumentDefinition, string] =
  let typed_arg = ? assign_type(file, module, arg.module_ref)
  ok(new_typed_argument_definition(typed_arg, arg.name))

proc assign_type(file: parser.File, arg: ArgumentDefinition): Result[
    TypedArgumentDefinition, string] =
  let typed_arg = ? assign_type(file, arg.module_ref)
  ok(new_typed_argument_definition(typed_arg, arg.name))

# FunctionDefinition - with generic and module
proc assign_type(file: parser.File, module: parser.Module, generic: Generic,
    def: FunctionDefinition): Result[TypedFunctionDefinition, string] =
  var typed_args: seq[TypedArgumentDefinition]
  for arg in def.args:
    typed_args.add( ? assign_type(file, module, generic, arg))
  let typed_return = ? assign_type(file, module, def.returns)
  ok(new_typed_function_definition(def.name, typed_args, typed_return, def.location))

proc assign_type(file: parser.File, module: parser.Module,
    def: FunctionDefinition): Result[TypedFunctionDefinition, string] =
  var typed_args: seq[TypedArgumentDefinition]
  for arg in def.args:
    typed_args.add( ? assign_type(file, module, arg))
  let typed_return = ? assign_type(file, module, def.returns)
  ok(new_typed_function_definition(def.name, typed_args, typed_return, def.location))

proc assign_type(file: parser.File, def: FunctionDefinition): Result[
    TypedFunctionDefinition, string] =
  var typed_args: seq[TypedArgumentDefinition]
  for arg in def.args:
    typed_args.add( ? assign_type(file, arg))
  let typed_return = ? assign_type(file, def.returns)
  ok(new_typed_function_definition(def.name, typed_args, typed_return, def.location))

# LiteralInit
proc assign_type(file: parser.File, module: parser.Module,
    init: LiteralInit): Result[TypedLiteralInit, string] =
  let module_ref = ? assign_type(file, module, init.module)
  ok(new_typed_literal_init(module_ref, init.literal))

proc assign_type(file: parser.File, init: LiteralInit): Result[
    TypedLiteralInit, string] =
  let module_ref = ? assign_type(file, init.module)
  ok(new_typed_literal_init(module_ref, init.literal))

# StructRef
proc assign_type(file: parser.File, module: parser.Module,
    struct_ref: StructRef): Result[TypedStructRef, string] =
  let module_ref = ? assign_type(file, module, struct_ref.module)
  case struct_ref.kind:
  of SRK_DEFAULT: ok(new_typed_struct_ref(module_ref))
  of SRK_NAMED: ok(new_typed_struct_ref(module_ref, ? struct_ref.struct))

proc assign_type(file: parser.File, struct_ref: StructRef): Result[
    TypedStructRef, string] =
  let module_ref = ? assign_type(file, struct_ref.module)
  case struct_ref.kind:
  of SRK_DEFAULT: ok(new_typed_struct_ref(module_ref))
  of SRK_NAMED: ok(new_typed_struct_ref(module_ref, ? struct_ref.struct))

# StructInit
proc assign_type(file: parser.File, module: parser.Module,
    init: StructInit): Result[TypedStructInit, string] =
  let struct_ref = ? assign_type(file, module, init.struct_ref)
  ok(new_typed_struct_init(struct_ref, init.args))

proc assign_type(file: parser.File, init: StructInit): Result[
    TypedStructInit, string] =
  let struct_ref = ? assign_type(file, init.struct_ref)
  ok(new_typed_struct_init(struct_ref, init.args))

# Initializer
proc assign_type(file: parser.File, module: parser.Module,
    init: Initializer): Result[TypedInitializer, string] =
  case init.kind:
  of IK_LITERAL:
    let literal_init = ? init.literal
    ok(new_typed_initializer( ? assign_type(file, module, literal_init)))
  of IK_STRUCT:
    let struct_init = ? init.struct
    ok(new_typed_initializer( ? assign_type(file, module, struct_init)))

proc assign_type(file: parser.File, init: Initializer): Result[
    TypedInitializer, string] =
  case init.kind:
  of IK_LITERAL:
    let literal_init = ? init.literal
    ok(new_typed_initializer( ? assign_type(file, literal_init)))
  of IK_STRUCT:
    let struct_init = ? init.struct
    ok(new_typed_initializer( ? assign_type(file, struct_init)))

# FunctionRef
proc assign_type(file: parser.File, module: parser.Module,
    fnref: FunctionRef, arity: uint): Result[TypedFunctionRef, string] =
  case fnref.kind:
  of FRK_LOCAL: ok(new_typed_function_ref(fnref.name, arity))
  of FRK_MODULE:
    let module_ref = ? assign_type(file, module, ? fnref.module)
    ok(new_typed_function_ref(module_ref, fnref.name, arity))

proc assign_type(file: parser.File, fnref: FunctionRef, arity: uint): Result[
    TypedFunctionRef, string] =
  case fnref.kind:
  of FRK_LOCAL: ok(new_typed_function_ref(fnref.name, arity))
  of FRK_MODULE:
    let module_ref = ? assign_type(file, ? fnref.module)
    ok(new_typed_function_ref(module_ref, fnref.name, arity))

# FunctionCall
proc assign_type(file: parser.File, module: parser.Module,
    fncall: FunctionCall): Result[TypedFunctionCall, string] =
  let fnref = ? assign_type(file, module, fncall.fnref, fncall.args.len.uint)
  ok(new_typed_function_call(fnref, fncall.args))

proc assign_type(file: parser.File, fncall: FunctionCall): Result[
    TypedFunctionCall, string] =
  let fnref = ? assign_type(file, fncall.fnref, fncall.args.len.uint)
  ok(new_typed_function_call(fnref, fncall.args))

# Forward Declaration needed due to cyclic dependencies
proc assign_type(file: parser.File, module: parser.Module,
    match: Match): Result[TypedMatch, string]

# Forward Declaration needed due to cyclic dependencies
proc assign_type(file: parser.File, match: Match): Result[
    TypedMatch, string]

# Expression
proc assign_type(file: parser.File, module: parser.Module,
    expression: Expression): Result[TypedExpression, string] =
  case expression.kind:
  of EK_MATCH:
    ok(new_typed_expression( ? assign_type(file, module, ? expression.match)))
  of EK_FNCALL:
    ok(new_typed_expression( ? assign_type(file, module, ? expression.fncall)))
  of EK_INIT:
    ok(new_typed_expression( ? assign_type(file, module, ? expression.init)))
  of EK_STRUCT_GET:
    let sg = ? expression.struct_get
    ok(new_typed_expression(new_typed_struct_get(sg.name, sg.field)))
  of EK_VARIABLE:
    ok(new_typed_expression(new_typed_variable( ? expression.variable)))

proc assign_type(file: parser.File, expression: Expression): Result[
    TypedExpression, string] =
  case expression.kind:
  of EK_MATCH:
    ok(new_typed_expression( ? assign_type(file, ? expression.match)))
  of EK_FNCALL:
    ok(new_typed_expression( ? assign_type(file, ? expression.fncall)))
  of EK_INIT:
    ok(new_typed_expression( ? assign_type(file, ? expression.init)))
  of EK_STRUCT_GET:
    let sg = ? expression.struct_get
    ok(new_typed_expression(new_typed_struct_get(sg.name, sg.field)))
  of EK_VARIABLE:
    ok(new_typed_expression(new_typed_variable( ? expression.variable)))

# Main function accepting Module type
proc assign_type(file: parser.File, module: parser.Module,
    statement: Statement): Result[TypedStatement, string] =
  let typed_expression = ? assign_type(file, module, statement.expression)
  ok(new_typed_statement(statement.arg, typed_expression))
proc assign_type(file: parser.File, statement: Statement): Result[
    TypedStatement, string] =
  let typed_expression = ? assign_type(file, statement.expression)
  ok(new_typed_statement(statement.arg, typed_expression))

# Statements helper
proc assign_type_statements(file: parser.File, module: parser.Module,
    statements: seq[Statement]): Result[seq[TypedStatement], string] =
  var typed: seq[TypedStatement]
  for s in statements: typed.add( ? assign_type(file, module, s))
  ok(typed)

proc assign_type_statements(file: parser.File,
    statements: seq[Statement]): Result[seq[TypedStatement], string] =
  var typed: seq[TypedStatement]
  for s in statements: typed.add( ? assign_type(file, s))
  ok(typed)

# Case
proc assign_type(file: parser.File, module: parser.Module,
    case_block: Case): Result[TypedCase, string] =
  let typed_stmts = ? assign_type_statements(file, module,
      case_block.statements)
  ok(new_typed_case(case_block.def.pattern, typed_stmts,
      case_block.def.location))

proc assign_type(file: parser.File, case_block: Case): Result[TypedCase, string] =
  let typed_stmts = ? assign_type_statements(file, case_block.statements)
  ok(new_typed_case(case_block.def.pattern, typed_stmts,
      case_block.def.location))

# Else
proc assign_type(file: parser.File, module: parser.Module,
    else_block: Else): Result[TypedElse, string] =
  let typed_stmts = ? assign_type_statements(file, module,
      else_block.statements)
  ok(new_typed_else(typed_stmts, else_block.location))

proc assign_type(file: parser.File, else_block: Else): Result[TypedElse, string] =
  let typed_stmts = ? assign_type_statements(file, else_block.statements)
  ok(new_typed_else(typed_stmts, else_block.location))

# Match
proc assign_type(file: parser.File, module: parser.Module,
    match: Match): Result[TypedMatch, string] =
  var typed_cases: seq[TypedCase]
  for cb in match.case_blocks: typed_cases.add( ? assign_type(file, module, cb))
  case match.kind:
  of MK_CASE_ONLY:
    ok(new_typed_match(match.def.operand, match.def.arg, typed_cases,
        match.def.location))
  of MK_COMPLETE:
    let typed_else = ? assign_type(file, module, ? match.else_block)
    ok(new_typed_match(match.def.operand, match.def.arg, typed_cases,
        typed_else, match.def.location))

proc assign_type(file: parser.File, match: Match): Result[TypedMatch, string] =
  var typed_cases: seq[TypedCase]
  for cb in match.case_blocks: typed_cases.add( ? assign_type(file, cb))
  case match.kind:
  of MK_CASE_ONLY:
    ok(new_typed_match(match.def.operand, match.def.arg, typed_cases,
        match.def.location))
  of MK_COMPLETE:
    let typed_else = ? assign_type(file, ? match.else_block)
    ok(new_typed_match(match.def.operand, match.def.arg, typed_cases,
        typed_else, match.def.location))

# Function
proc assign_type(file: parser.File, module: parser.Module,
    function: Function): Result[TypedFunction, string] =
  let typed_def = ? assign_type(file, module, function.def)
  let typed_steps = ? assign_type_statements(file, module, function.steps)
  ok(new_typed_function(typed_def, typed_steps))

proc assign_type(file: parser.File, function: Function): Result[
    TypedFunction, string] =
  let typed_def = ? assign_type(file, function.def)
  let typed_steps = ? assign_type_statements(file, function.steps)
  ok(new_typed_function(typed_def, typed_steps))

# Generic
proc assign_type(file: parser.File, module: parser.Module, generic: Generic,
    id: uint64): Result[TypedGeneric, string] =
  var typed_defs: seq[TypedFunctionDefinition]
  for def in generic.defs: typed_defs.add( ? assign_type(file, module, generic, def))
  ok(new_typed_generic(id, generic, typed_defs, generic.location))

# Struct
proc assign_type(file: parser.File, module: parser.Module, struct: Struct,
    id: uint64): Result[TypedStruct, string] =
  var typed_fields: seq[TypedArgumentDefinition]
  for field in struct.fields: typed_fields.add( ? assign_type(file, module, field))
  case struct.def.kind:
  of SDK_DEFAULT: ok(new_typed_struct(id, typed_fields, struct.location))
  of SDK_NAMED:
    let maybe_struct_name = struct.name
    if maybe_struct_name.is_ok:
      let struct_name = maybe_struct_name.get
      ok(new_typed_struct(id, struct_name, typed_fields, struct.location))
    else:
      err($(maybe_struct_name.error))

# Module processing helpers
proc assign_type_generics(file: parser.File, module: parser.Module): Result[
    seq[(Generic, TypedGeneric)], string] =
  var pairs: seq[(Generic, TypedGeneric)]
  for idx, g in module.payload.generics:
    pairs.add((g, ? assign_type(file, module, g, idx.uint64)))
  ok(pairs)

proc assign_type_structs(file: parser.File, module: parser.Module): Result[
    seq[TypedStruct], string] =
  var typed: seq[TypedStruct]
  for idx, s in module.payload.structs:
    typed.add( ? assign_type(file, module, s, idx.uint64))
  ok(typed)

proc assign_type_core(file: parser.File, module: parser.Module): Result[
    (seq[(Generic, TypedGeneric)], seq[TypedStruct]), string] =
  ok(( ? assign_type_generics(file, module), ? assign_type_structs(file, module)))

# Helper to create internal functions for UserModule
proc create_internal_functions(file: parser.File,
    module_name: Identifier): Result[seq[TypedFunctionDefinition], string] =
  var internal_functions: seq[TypedFunctionDefinition]
  internal_functions.add( ? make_typed_function_def(file, "byte_size", @[("U64",
      "items")], "U64"))
  internal_functions.add( ? make_typed_function_def(file, "read", @[(
      "Pointer", "ptr"), ("U64", "offset")], module_name.asl))
  internal_functions.add( ? make_typed_function_def(file, "write", @[(
      module_name.asl, "item"), ("Pointer", "ptr"), ("U64", "offset")], "Pointer"))
  ok(internal_functions)

proc assign_type(file: parser.File, module: UserModule, id: uint64): Result[
    TypedUserModule, string] =
  let mod_wrapper = parser.new_module(module)
  let (generic_pairs, typed_structs) = ? assign_type_core(file, mod_wrapper)

  var typed_functions: seq[TypedFunction]
  for function in module.functions:
    let typed_function = ? assign_type(file, mod_wrapper, function)
    typed_functions.add(typed_function)

  # NOTE: This internal functions are injected in every user defined module
  # since they are pointers under the hood and to make the array implementation
  # work every module needs to have `byte_size`, `read` and `write` functions
  # but adding them before codegen is hard in case of `read` and `write` because
  # there is no conversion utility between module and pointers.
  let internal_functions = ? create_internal_functions(file, module.name)

  ok(new_typed_user_module(id, module.name, generic_pairs, typed_structs,
      typed_functions, internal_functions, module.location))

# Module-based wrapper for user modules
proc assign_type_user_module*(file: parser.File, module: parser.Module,
    id: uint64): Result[TypedUserModule, string] =
  let user = ? module.user_module
  assign_type(file, user, id)


# Module-based assign for extern functions (expects native module)
proc assign_type(file: parser.File, module: parser.Module,
    function: ExternFunction): Result[TypedNativeFunction, string] =
  case module.kind:
  of parser.MK_NATIVE:
    let typed_def = ? assign_type(file, module, function.def)
    ok(new_typed_native_function(function.extern, typed_def))
  of parser.MK_USER:
    err("extern functions must belong to a native module")

proc assign_type(file: parser.File, module: NativeModule, id: uint64): Result[
    TypedNativeModule, string] =
  let mod_wrapper = parser.new_module(module)
  let (typed_generics, typed_structs) = ? assign_type_core(file, mod_wrapper)

  var typed_functions: seq[TypedNativeFunction]
  for function in module.functions:
    let typed_function = ? assign_type(file, mod_wrapper, function)
    typed_functions.add(typed_function)
  ok(new_typed_native_module(module.name, typed_generics, typed_structs,
      typed_functions, id))


# Module-based assign_type for modules (returns TypedModule wrapper)
proc assign_type(file: parser.File, module: parser.Module, id: uint64): Result[
    TypedModule, string] =
  case module.kind:
  of parser.MK_USER:
    let user = ? module.user_module
    let typed_user = ? assign_type(file, user, id)
    ok(new_typed_module(typed_user))
  of parser.MK_NATIVE:
    let native = ? module.native_module
    let typed_native = ? assign_type(file, native, id)
    ok(new_typed_module(typed_native))

# Module-based wrapper for native modules
proc assign_type_native_module*(file: parser.File, module: parser.Module,
    id: uint64): Result[TypedNativeModule, string] =
  let native = ? module.native_module
  assign_type(file, native, id)


proc validate(module: TypedNativeModule,
    integer_literal: IntegerLiteral): Result[void, string] =
  case module.name.asl:
  of "S8": safe_parse[int8](integer_literal.asl)
  of "S16": safe_parse[int16](integer_literal.asl)
  of "S32": safe_parse[int32](integer_literal.asl)
  of "S64": safe_parse[int64](integer_literal.asl)
  of "U8": safe_parse[uint8](integer_literal.asl)
  of "U16": safe_parse[uint16](integer_literal.asl)
  of "U32": safe_parse[uint32](integer_literal.asl)
  of "U64": safe_parse[uint64](integer_literal.asl)
  else: err("{integer_literal.location} integer can not be converted to module `{module.name.asl}`")

proc validate(module: TypedNativeModule, float_literal: FloatLiteral): Result[
    void, string] =
  case module.name.asl:
  of "F32": safe_parse[float32](float_literal.asl)
  of "F64": safe_parse[float64](float_literal.asl)
  else: err("{float_literal.location} float can not be converted to module `{module.name.asl}`")

proc validate(module: TypedNativeModule,
    string_literal: StringLiteral): Result[void, string] =
  case module.name.asl:
  of "String": ok()
  else: err("{string_literal.location} string can not be converted to module `{module.name.asl}`")

proc validate*(module: TypedNativeModule, literal: Literal): Result[void, string] =
  case literal.kind:
  of LK_INTEGER:
    let integer_literal = ? literal.integer_literal
    validate(module, integer_literal)
  of LK_FLOAT:
    let float_literal = ? literal.float_literal
    validate(module, float_literal)
  of LK_STRING:
    let string_literal = ? literal.string_literal
    validate(module, string_literal)

proc assign_type*(file: parser.File): Result[TypedFile, string] =
  var native_modules: seq[(NativeModule, TypedModule)]
  for index, module in file.native_modules:
    let typed_module = ? assign_type(file, parser.new_module(module),
        index.uint64)
    native_modules.add((module, typed_module))

  var module_graph: Table[UserModule, HashSet[UserModule]]
  var modules_map: Table[UserModule, TypedModule]
  let offset = file.native_modules.len
  for index, module in file.user_modules:
    let typed_module = ? assign_type(file, parser.new_module(module),
        (offset + index).uint64)
    let module_deps = typed_module.module_deps
    module_graph[module] = module_deps
    modules_map[module] = typed_module

  # NOTE: Cycle detection and Topologically sort based on module dependencies.
  let maybe_module_order = detect_cycle(module_graph)
  if maybe_module_order.is_err:
    let cycle = maybe_module_order.get
    var message = @["CYCLIC DEPENDENCIES ENCOUNTERED"]
    for module in cycle:
      message.add(fmt"{module.location} {module.name.asl}")
    return err(message.join("\n"))

  let module_resolution_order = maybe_module_order.get
  var typed_modules: seq[TypedModule]
  for module in module_resolution_order:
    typed_modules.add(modules_map[module])

  var maybe_start_def: Option[TypedFunctionDefinition]
  let start_def = ? make_typed_function_def(file, "start", @[(
      "U8", "seed")], "U8")

  var typed_functions: seq[TypedFunction]
  for function in file.functions:
    let typed_function = ? assign_type(file, function)
    typed_functions.add(typed_function)
    if typed_function.def == start_def:
      maybe_start_def = some(typed_function.def)

  if maybe_start_def.is_none:
    return err(fmt"{file.path} failed to find `start` function")

  ok(new_typed_file(file.path, file.indent, maybe_start_def,
      native_modules, typed_modules, modules_map, typed_functions))
