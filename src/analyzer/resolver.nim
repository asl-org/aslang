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
  let module_ref = new_resolved_module_ref(module, @[], Location())
  ok(module_ref.self)

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
    string, string)], returns: string): Result[ResolvedFunctionDefinition, string] =
  let name_id = new_identifier(name)
  let returns_module_ref = ? make_resolved_module_ref(file, returns)
  var resolved_arg_defs: seq[ResolvedArgumentDefinition]
  for (arg_module, arg_name) in args:
    resolved_arg_defs.add( ? make_resolved_arg_def(file, arg_module, arg_name))
  ok(new_resolved_function_definition(name_id, resolved_arg_defs,
      returns_module_ref, Location()))

proc validate(module: ResolvedModule,
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

proc validate(module: ResolvedModule,
    float_literal: FloatLiteral): Result[void, string] =
  case module.name.asl:
  of "F32": safe_parse[float32](float_literal.asl)
  of "F64": safe_parse[float64](float_literal.asl)
  else: err("{float_literal.location} float can not be converted to module `{module.name.asl}`")

proc validate(module: ResolvedModule,
    string_literal: StringLiteral): Result[void, string] =
  case module.name.asl:
  of "String": ok()
  else: err("{string_literal.location} string can not be converted to module `{module.name.asl}`")

proc validate*(module: ResolvedModule, literal: Literal): Result[void, string] =
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
  var module_graph: Table[Module, HashSet[Module]]
  var modules_map: Table[Module, ResolvedModule]
  for id, module in file.modules:
    let resolved_module = ? resolve(file, module, id.uint64)
    let module_deps = resolved_module.module_deps
    module_graph[module] = module_deps
    modules_map[module] = resolved_module

  # NOTE: Cycle detection and Topologically sort based on module dependencies.
  let maybe_module_order = detect_cycle(module_graph)
  if maybe_module_order.is_err:
    let cycle = maybe_module_order.error
    var message = @["CYCLIC DEPENDENCIES ENCOUNTERED"]
    for module in cycle:
      message.add(fmt"{module.location} {module.name.asl}")
    return err(message.join("\n"))

  let resolved_modules = maybe_module_order.get.map_it(modules_map[it])
  var maybe_start_def: Option[ResolvedFunctionDefinition]
  let start_def = ? make_resolved_function_def(file, "start", @[(
      "U8", "seed")], "U8")

  var resolved_functions: seq[ResolvedFunction]
  for function in file.functions:
    let resolved_function = ? resolve(file, none(parser.Module), function)
    resolved_functions.add(new_resolved_function(resolved_function))
    if resolved_function.def == start_def:
      maybe_start_def = some(resolved_function.def)

  if maybe_start_def.is_none:
    return err(fmt"{file.path} failed to find `start` function")
  ok(new_resolved_file(file.path, file.indent, maybe_start_def,
      resolved_modules, modules_map, resolved_functions))
