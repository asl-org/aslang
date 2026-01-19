import results, strformat, tables, strutils, sets, algorithm, options, sequtils,
    hashes, parseutils

import resolver/file
export file

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
proc make_resolved_module_ref(file: parser.File, module_name: string): Result[
    ResolvedModuleRef, string] =
  let module_id = new_identifier(module_name)
  let module = ? file.find_module(module_id)
  case module.kind:
  of MK_NATIVE:
    let native_module = ? module.native_module
    ok(new_resolved_module_ref(native_module, Location()))
  of MK_USER:
    let user_module = ? module.user_module
    let user_module_ref = new_resolved_module_ref(user_module, Location())
    ok(user_module_ref.self)

# NOTE: This is a utility function to internally add some function definitions
# like `byte_size`, `read`, `write`
proc make_resolved_arg_def(file: parser.File, module_name: string,
    arg_name: string): Result[ResolvedArgumentDefinition, string] =
  let arg_module_ref = ? make_resolved_module_ref(file, module_name)
  let arg_name_id = new_identifier(arg_name)
  ok(new_resolved_argument_definition(arg_module_ref, arg_name_id))

# NOTE: This is a utility function to internally add some function definitions
# like `byte_size`, `read`, `write`
proc make_resolved_function_def(file: parser.File, name: string, args: seq[(
    string, string)], returns: string): Result[ResolvedUserFunctionDefinition, string] =
  let name_id = new_identifier(name)
  let returns_module_ref = ? make_resolved_module_ref(file, returns)
  var resolved_arg_defs: seq[ResolvedArgumentDefinition]
  for (arg_module, arg_name) in args:
    resolved_arg_defs.add( ? make_resolved_arg_def(file, arg_module, arg_name))
  ok(new_resolved_function_definition(name_id, resolved_arg_defs,
      returns_module_ref, Location()))

# Helper to create ResolvedModuleRef from a Module (handles kind dispatch)
proc resolved_module_ref_from_module(arg_module: parser.Module,
    children: seq[ResolvedModuleRef], location: Location): Result[
        ResolvedModuleRef, string] =
  case arg_module.kind:
  of MK_NATIVE:
    let native_module = ? arg_module.native_module
    ok(new_resolved_module_ref(native_module, children, location))
  of MK_USER:
    let user_module = ? arg_module.user_module
    ok(new_resolved_module_ref(user_module, children, location))

proc resolved_module_ref_from_module(arg_module: parser.Module,
    location: Location): Result[ResolvedModuleRef, string] =
  case arg_module.kind:
  of MK_NATIVE:
    let native_module = ? arg_module.native_module
    ok(new_resolved_module_ref(native_module, location))
  of MK_USER:
    let user_module = ? arg_module.user_module
    ok(new_resolved_module_ref(user_module, location))

# Main helpers using Module type
proc resolve(file: parser.File, module: parser.Module,
    module_name: Identifier): Result[ResolvedModuleRef, string] =
  let payload = module.payload
  let gm = payload.generics_map
  if module_name in gm:
    let generic = payload.generics[gm[module_name]]
    return ok(new_resolved_module_ref(generic, module_name.location))
  let arg_module = ? file.find_module(module_name)
  resolved_module_ref_from_module(arg_module, module_name.location)

# Forward declaration for no-module variant
proc resolve(file: parser.File, module_name: Identifier): Result[
    ResolvedModuleRef, string]

proc resolve(file: parser.File, module: parser.Module,
    module_ref: ModuleRef): Result[ResolvedModuleRef, string] =
  case module_ref.kind:
  of MRK_SIMPLE:
    resolve(file, module, module_ref.module)
  of MRK_NESTED:
    let arg_module = ? file.find_module(module_ref.module)
    var resolved_children: seq[ResolvedModuleRef]
    for child in module_ref.children:
      let resolved_child = ? resolve(file, module, child)
      resolved_children.add(resolved_child)
    resolved_module_ref_from_module(arg_module, resolved_children,
        module_ref.location)
proc resolve(file: parser.File, module_ref: ModuleRef): Result[
    ResolvedModuleRef, string] =
  case module_ref.kind:
  of MRK_SIMPLE:
    resolve(file, module_ref.module)
  of MRK_NESTED:
    let arg_module = ? file.find_module(module_ref.module)
    var resolved_children: seq[ResolvedModuleRef]
    for child in module_ref.children:
      let resolved_child = ? resolve(file, child)
      resolved_children.add(resolved_child)
    resolved_module_ref_from_module(arg_module, resolved_children,
        module_ref.location)

# No-module context for module name
proc resolve(file: parser.File, module_name: Identifier): Result[
    ResolvedModuleRef, string] =
  let arg_module = ? file.find_module(module_name)
  resolved_module_ref_from_module(arg_module, module_name.location)

# ArgumentDefinition - unified with optional module
proc resolve(file: parser.File, module: parser.Module, generic: Generic,
    arg: ArgumentDefinition): Result[ResolvedArgumentDefinition, string] =
  let resolved_arg = ? resolve(file, module, arg.module_ref)
  ok(new_resolved_argument_definition(resolved_arg, arg.name))

proc resolve(file: parser.File, module: parser.Module,
    arg: ArgumentDefinition): Result[ResolvedArgumentDefinition, string] =
  let resolved_arg = ? resolve(file, module, arg.module_ref)
  ok(new_resolved_argument_definition(resolved_arg, arg.name))

proc resolve(file: parser.File, arg: ArgumentDefinition): Result[
    ResolvedArgumentDefinition, string] =
  let resolved_arg = ? resolve(file, arg.module_ref)
  ok(new_resolved_argument_definition(resolved_arg, arg.name))

# FunctionDefinition - with generic and module
proc resolve(file: parser.File, module: parser.Module, generic: Generic,
    def: FunctionDefinition): Result[ResolvedUserFunctionDefinition, string] =
  var resolved_args: seq[ResolvedArgumentDefinition]
  for arg in def.args:
    resolved_args.add( ? resolve(file, module, generic, arg))
  let resolved_return = ? resolve(file, module, def.returns)
  ok(new_resolved_function_definition(def.name, resolved_args, resolved_return, def.location))

proc resolve(file: parser.File, module: parser.Module,
    def: FunctionDefinition): Result[ResolvedUserFunctionDefinition, string] =
  var resolved_args: seq[ResolvedArgumentDefinition]
  for arg in def.args:
    resolved_args.add( ? resolve(file, module, arg))
  let resolved_return = ? resolve(file, module, def.returns)
  ok(new_resolved_function_definition(def.name, resolved_args, resolved_return, def.location))

proc resolve(file: parser.File, def: FunctionDefinition): Result[
    ResolvedUserFunctionDefinition, string] =
  var resolved_args: seq[ResolvedArgumentDefinition]
  for arg in def.args:
    resolved_args.add( ? resolve(file, arg))
  let resolved_return = ? resolve(file, def.returns)
  ok(new_resolved_function_definition(def.name, resolved_args, resolved_return, def.location))

# LiteralInit
proc resolve(file: parser.File, module: parser.Module,
    init: LiteralInit): Result[ResolvedLiteralInit, string] =
  let module_ref = ? resolve(file, module, init.module)
  ok(new_resolved_literal_init(module_ref, init.literal))

proc resolve(file: parser.File, init: LiteralInit): Result[
    ResolvedLiteralInit, string] =
  let module_ref = ? resolve(file, init.module)
  ok(new_resolved_literal_init(module_ref, init.literal))

# StructRef
proc resolve(file: parser.File, module: parser.Module,
    struct_ref: StructRef): Result[ResolvedStructRef, string] =
  let module_ref = ? resolve(file, module, struct_ref.module)
  case struct_ref.kind:
  of SRK_DEFAULT: ok(new_resolved_struct_ref(module_ref))
  of SRK_NAMED: ok(new_resolved_struct_ref(module_ref, ? struct_ref.struct))

proc resolve(file: parser.File, struct_ref: StructRef): Result[
    ResolvedStructRef, string] =
  let module_ref = ? resolve(file, struct_ref.module)
  case struct_ref.kind:
  of SRK_DEFAULT: ok(new_resolved_struct_ref(module_ref))
  of SRK_NAMED: ok(new_resolved_struct_ref(module_ref, ? struct_ref.struct))

# StructInit
proc resolve(file: parser.File, module: parser.Module,
    init: StructInit): Result[ResolvedStructInit, string] =
  let struct_ref = ? resolve(file, module, init.struct_ref)
  ok(new_resolved_struct_init(struct_ref, init.args))

proc resolve(file: parser.File, init: StructInit): Result[
    ResolvedStructInit, string] =
  let struct_ref = ? resolve(file, init.struct_ref)
  ok(new_resolved_struct_init(struct_ref, init.args))

# Initializer
proc resolve(file: parser.File, module: parser.Module,
    init: Initializer): Result[ResolvedInitializer, string] =
  case init.kind:
  of IK_LITERAL:
    let literal_init = ? init.literal
    ok(new_resolved_initializer( ? resolve(file, module, literal_init)))
  of IK_STRUCT:
    let struct_init = ? init.struct
    ok(new_resolved_initializer( ? resolve(file, module, struct_init)))

proc resolve(file: parser.File, init: Initializer): Result[
    ResolvedInitializer, string] =
  case init.kind:
  of IK_LITERAL:
    let literal_init = ? init.literal
    ok(new_resolved_initializer( ? resolve(file, literal_init)))
  of IK_STRUCT:
    let struct_init = ? init.struct
    ok(new_resolved_initializer( ? resolve(file, struct_init)))

# FunctionRef
proc resolve(file: parser.File, module: parser.Module,
    fnref: FunctionRef, arity: uint): Result[ResolvedUserFunctionRef, string] =
  case fnref.kind:
  of FRK_LOCAL: ok(new_resolved_function_ref(fnref.name, arity))
  of FRK_MODULE:
    let module_ref = ? resolve(file, module, ? fnref.module)
    ok(new_resolved_function_ref(module_ref, fnref.name, arity))

proc resolve(file: parser.File, fnref: FunctionRef, arity: uint): Result[
    ResolvedUserFunctionRef, string] =
  case fnref.kind:
  of FRK_LOCAL: ok(new_resolved_function_ref(fnref.name, arity))
  of FRK_MODULE:
    let module_ref = ? resolve(file, ? fnref.module)
    ok(new_resolved_function_ref(module_ref, fnref.name, arity))

# FunctionCall
proc resolve(file: parser.File, module: parser.Module,
    fncall: FunctionCall): Result[ResolvedUserFunctionCall, string] =
  let fnref = ? resolve(file, module, fncall.fnref, fncall.args.len.uint)
  ok(new_resolved_function_call(fnref, fncall.args))

proc resolve(file: parser.File, fncall: FunctionCall): Result[
    ResolvedUserFunctionCall, string] =
  let fnref = ? resolve(file, fncall.fnref, fncall.args.len.uint)
  ok(new_resolved_function_call(fnref, fncall.args))

# Forward Declaration needed due to cyclic dependencies
proc resolve(file: parser.File, module: parser.Module,
    match: Match): Result[ResolvedMatch, string]

# Forward Declaration needed due to cyclic dependencies
proc resolve(file: parser.File, match: Match): Result[
    ResolvedMatch, string]

# Expression
proc resolve(file: parser.File, module: parser.Module,
    expression: Expression): Result[ResolvedExpression, string] =
  case expression.kind:
  of EK_MATCH:
    ok(new_resolved_expression( ? resolve(file, module, ?
        expression.match)))
  of EK_FNCALL:
    ok(new_resolved_expression( ? resolve(file, module, ?
        expression.fncall)))
  of EK_INIT:
    ok(new_resolved_expression( ? resolve(file, module, ? expression.init)))
  of EK_STRUCT_GET:
    let sg = ? expression.struct_get
    ok(new_resolved_expression(new_resolved_struct_get(sg.name, sg.field)))
  of EK_VARIABLE:
    ok(new_resolved_expression(new_resolved_variable( ? expression.variable)))

proc resolve(file: parser.File, expression: Expression): Result[
    ResolvedExpression, string] =
  case expression.kind:
  of EK_MATCH:
    ok(new_resolved_expression( ? resolve(file, ? expression.match)))
  of EK_FNCALL:
    ok(new_resolved_expression( ? resolve(file, ? expression.fncall)))
  of EK_INIT:
    ok(new_resolved_expression( ? resolve(file, ? expression.init)))
  of EK_STRUCT_GET:
    let sg = ? expression.struct_get
    ok(new_resolved_expression(new_resolved_struct_get(sg.name, sg.field)))
  of EK_VARIABLE:
    ok(new_resolved_expression(new_resolved_variable( ? expression.variable)))

# Main function accepting Module type
proc resolve(file: parser.File, module: parser.Module,
    statement: Statement): Result[ResolvedStatement, string] =
  let resolved_expression = ? resolve(file, module, statement.expression)
  ok(new_resolved_statement(statement.arg, resolved_expression))
proc resolve(file: parser.File, statement: Statement): Result[
    ResolvedStatement, string] =
  let resolved_expression = ? resolve(file, statement.expression)
  ok(new_resolved_statement(statement.arg, resolved_expression))

# Statements helper
proc resolve_statements(file: parser.File, module: parser.Module,
    statements: seq[Statement]): Result[seq[ResolvedStatement], string] =
  var resolved: seq[ResolvedStatement]
  for s in statements: resolved.add( ? resolve(file, module, s))
  ok(resolved)

proc resolve_statements(file: parser.File,
    statements: seq[Statement]): Result[seq[ResolvedStatement], string] =
  var resolved: seq[ResolvedStatement]
  for s in statements: resolved.add( ? resolve(file, s))
  ok(resolved)

# Case
proc resolve(file: parser.File, module: parser.Module,
    case_block: Case): Result[ResolvedCase, string] =
  let resolved_stmts = ? resolve_statements(file, module,
      case_block.statements)
  ok(new_resolved_case(case_block.def.pattern, resolved_stmts,
      case_block.def.location))

proc resolve(file: parser.File, case_block: Case): Result[ResolvedCase, string] =
  let resolved_stmts = ? resolve_statements(file, case_block.statements)
  ok(new_resolved_case(case_block.def.pattern, resolved_stmts,
      case_block.def.location))

# Else
proc resolve(file: parser.File, module: parser.Module,
    else_block: Else): Result[ResolvedElse, string] =
  let resolved_stmts = ? resolve_statements(file, module,
      else_block.statements)
  ok(new_resolved_else(resolved_stmts, else_block.location))

proc resolve(file: parser.File, else_block: Else): Result[ResolvedElse, string] =
  let resolved_stmts = ? resolve_statements(file, else_block.statements)
  ok(new_resolved_else(resolved_stmts, else_block.location))

# Match
proc resolve(file: parser.File, module: parser.Module,
    match: Match): Result[ResolvedMatch, string] =
  var resolved_cases: seq[ResolvedCase]
  for cb in match.case_blocks: resolved_cases.add( ? resolve(file, module, cb))
  case match.kind:
  of MK_CASE_ONLY:
    ok(new_resolved_match(match.def.operand, match.def.arg, resolved_cases,
        match.def.location))
  of MK_COMPLETE:
    let resolved_else = ? resolve(file, module, ? match.else_block)
    ok(new_resolved_match(match.def.operand, match.def.arg, resolved_cases,
        resolved_else, match.def.location))

proc resolve(file: parser.File, match: Match): Result[ResolvedMatch, string] =
  var resolved_cases: seq[ResolvedCase]
  for cb in match.case_blocks: resolved_cases.add( ? resolve(file, cb))
  case match.kind:
  of MK_CASE_ONLY:
    ok(new_resolved_match(match.def.operand, match.def.arg, resolved_cases,
        match.def.location))
  of MK_COMPLETE:
    let resolved_else = ? resolve(file, ? match.else_block)
    ok(new_resolved_match(match.def.operand, match.def.arg, resolved_cases,
        resolved_else, match.def.location))

# Function
proc resolve(file: parser.File, module: parser.Module,
    function: Function): Result[ResolvedFunction, string] =
  case function.kind:
  of FK_EXTERN:
    case module.kind:
    of parser.MK_NATIVE:
      let resolved_def = ? resolve(file, module, function.def)
      let native_function = new_resolved_native_function(
          function.extern_func.extern, resolved_def)
      ok(new_resolved_function(native_function))
    of parser.MK_USER:
      err("extern functions must belong to a native module")
  of FK_USER:
    let resolved_def = ? resolve(file, module, function.def)
    let resolved_steps = ? resolve_statements(file, module, function.steps)
    let user_function = new_resolved_user_function(resolved_def, resolved_steps)
    ok(new_resolved_function(user_function))

proc resolve(file: parser.File, function: Function): Result[
    ResolvedUserFunction, string] =
  let resolved_def = ? resolve(file, function.def)
  let resolved_steps = ? resolve_statements(file, function.steps)
  ok(new_resolved_user_function(resolved_def, resolved_steps))

# Generic
proc resolve(file: parser.File, module: parser.Module, generic: Generic,
    id: uint64): Result[ResolvedGeneric, string] =
  var resolved_defs: seq[ResolvedUserFunctionDefinition]
  for def in generic.defs: resolved_defs.add( ? resolve(file, module,
      generic, def))
  ok(new_resolved_generic(id, generic, resolved_defs, generic.location))

# Struct
proc resolve(file: parser.File, module: parser.Module, struct: Struct,
    id: uint64): Result[ResolvedStruct, string] =
  var resolved_fields: seq[ResolvedArgumentDefinition]
  for field in struct.fields: resolved_fields.add( ? resolve(file, module, field))
  case struct.def.kind:
  of SDK_DEFAULT: ok(new_resolved_struct(id, resolved_fields, struct.location))
  of SDK_NAMED:
    let maybe_struct_name = struct.name
    if maybe_struct_name.is_ok:
      let struct_name = maybe_struct_name.get
      ok(new_resolved_struct(id, struct_name, resolved_fields, struct.location))
    else:
      err($(maybe_struct_name.error))

# Module processing helpers
proc resolve_generics(file: parser.File, module: parser.Module): Result[
    seq[(Generic, ResolvedGeneric)], string] =
  var pairs: seq[(Generic, ResolvedGeneric)]
  for idx, g in module.payload.generics:
    pairs.add((g, ? resolve(file, module, g, idx.uint64)))
  ok(pairs)

proc resolve_structs(file: parser.File, module: parser.Module): Result[
    seq[ResolvedStruct], string] =
  var resolved: seq[ResolvedStruct]
  for idx, s in module.payload.structs:
    resolved.add( ? resolve(file, module, s, idx.uint64))
  ok(resolved)

proc resolve(file: parser.File, module: parser.Module): Result[
    (seq[(Generic, ResolvedGeneric)], seq[ResolvedStruct]), string] =
  ok(( ? resolve_generics(file, module), ? resolve_structs(file, module)))

# Module-based resolve for modules (returns ResolvedModule wrapper)
proc resolve(file: parser.File, module: parser.Module, id: uint64): Result[
    ResolvedModule, string] =
  # TODO: Eliminate un-necessary case block once the ExternFunction is evened out.
  let (resolved_generics, resolved_structs) = ? resolve(file, module)
  var resolved_functions: seq[ResolvedFunction]
  for function in module.functions:
    let resolved_function = ? resolve(file, module, function)
    resolved_functions.add(resolved_function)

  case module.kind:
  of parser.MK_USER:
    let resolved_user = new_resolved_user_module(id, module.name,
        resolved_generics, resolved_structs, resolved_functions,
        module.location)
    ok(new_resolved_module(resolved_user))
  of parser.MK_NATIVE:
    let resolved_native = new_resolved_native_module(id, module.name,
        resolved_generics, resolved_structs, resolved_functions)
    ok(new_resolved_module(resolved_native))

proc validate(module: ResolvedNativeModule,
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

proc validate(module: ResolvedNativeModule,
    float_literal: FloatLiteral): Result[void, string] =
  case module.name.asl:
  of "F32": safe_parse[float32](float_literal.asl)
  of "F64": safe_parse[float64](float_literal.asl)
  else: err("{float_literal.location} float can not be converted to module `{module.name.asl}`")

proc validate(module: ResolvedNativeModule,
    string_literal: StringLiteral): Result[void, string] =
  case module.name.asl:
  of "String": ok()
  else: err("{string_literal.location} string can not be converted to module `{module.name.asl}`")

proc validate*(module: ResolvedNativeModule, literal: Literal): Result[void, string] =
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

proc resolve*(file: parser.File): Result[ResolvedFile, string] =
  var native_modules: seq[(NativeModule, ResolvedModule)]
  for index, module in file.native_modules:
    let resolved_module = ? resolve(file, parser.new_module(module),
        index.uint64)
    native_modules.add((module, resolved_module))

  var module_graph: Table[UserModule, HashSet[UserModule]]
  var modules_map: Table[UserModule, ResolvedModule]
  let offset = file.native_modules.len
  for index, module in file.user_modules:
    let resolved_module = ? resolve(file, parser.new_module(module),
        (offset + index).uint64)
    let module_deps = resolved_module.module_deps
    module_graph[module] = module_deps
    modules_map[module] = resolved_module

  # NOTE: Cycle detection and Topologically sort based on module dependencies.
  let maybe_module_order = detect_cycle(module_graph)
  if maybe_module_order.is_err:
    let cycle = maybe_module_order.get
    var message = @["CYCLIC DEPENDENCIES ENCOUNTERED"]
    for module in cycle:
      message.add(fmt"{module.location} {module.name.asl}")
    return err(message.join("\n"))

  let module_resolution_order = maybe_module_order.get
  var resolved_modules: seq[ResolvedModule]
  for module in module_resolution_order:
    resolved_modules.add(modules_map[module])

  var maybe_start_def: Option[ResolvedUserFunctionDefinition]
  let start_def = ? make_resolved_function_def(file, "start", @[(
      "U8", "seed")], "U8")

  var resolved_functions: seq[ResolvedUserFunction]
  for function in file.functions:
    let resolved_function = ? resolve(file, function)
    resolved_functions.add(resolved_function)
    if resolved_function.def == start_def:
      maybe_start_def = some(resolved_function.def)

  if maybe_start_def.is_none:
    return err(fmt"{file.path} failed to find `start` function")

  ok(new_resolved_file(file.path, file.indent, maybe_start_def,
      native_modules, resolved_modules, modules_map, resolved_functions))
