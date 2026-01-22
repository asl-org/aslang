import results, strformat, strutils, sequtils, re, tables, hashes

import core, module, function
export core, module, function

# =============================================================================
# File
# =============================================================================

type File* = ref object of RootObj
  path: string
  indent: int
  modules: seq[Module]
  modules_map: Table[Identifier, int]
  functions: seq[Function]

proc new_file*(path: string, indent: int, modules: seq[Module],
    functions: seq[Function]): Result[File, ParserError] =
  if functions.len + modules.len == 0:
    return err(err_parser_empty_file(path))

  # NOTE: Build index to enable module look by name
  var modules_map: Table[Identifier, int]

  for id, module in modules:
    if module.name in modules_map:
      let predefined_module_location = modules[modules_map[
          module.name]].location
      return err(err_parseR_module_already_defined(module.location,
          module.name.asl, predefined_module_location))
    modules_map[module.name] = id

  # NOTE: Build index to enable function look up by definition
  var function_defs_hash_map: Table[Hash, int]
  for index, function in functions:
    # NOTE: Validate module and function name collisions
    if function.name in modules_map:
      let module = modules[modules_map[function.name]]
      return err(err_parser_function_module_conflict(function.location,
          function.name.asl, module.location, module.name.asl))

    # NOTE: Validate function definition collisions
    let def_hash = function.def.hash
    if def_hash in function_defs_hash_map:
      let predefined_function_location = functions[function_defs_hash_map[
          def_hash]].location
      return err(err_parser_function_already_defined(function.location,
          function.name.asl, predefined_function_location))
    function_defs_hash_map[def_hash] = index

  ok(File(path: path, indent: indent, modules: modules,
      modules_map: modules_map, functions: functions))

proc modules*(file: File): seq[Module] = file.modules
proc modules_map*(file: File): Table[Identifier, int] = file.modules_map
proc path*(file: File): string = file.path
proc indent*(file: File): int = file.indent
proc functions*(file: File): seq[Function] = file.functions

proc asl*(file: File): string =
  var lines: seq[string]
  let indent = " ".repeat(file.indent)

  for module in file.modules:
    for line in module.asl(indent):
      lines.add(line)
    lines.add("\n")

  for function in file.functions:
    for line in function.asl(indent):
      lines.add(line)
    lines.add("\n")

  lines.map_it(it.strip(leading = false)).join("\n").replace(re"\n{3,}", "\n\n")

proc find_module*(file: File, module_name: Identifier): Result[Module, string] =
  # NOTE: Somehow `modules_map` table is not behaving as expected when using `in` operator.
  case module_name in file.modules_map
  of true:
    ok(file.modules[file.modules_map[module_name]])
  else:
    err(fmt"{module_name.location} [PE168] module `{module_name.asl}` is not defined in the file {file.path}")

proc file_spec*(parser: Parser, builtin_modules: seq[Module]): Result[File, ParserError] =
  var modules = builtin_modules
  var functions: seq[Function]
  while parser.can_parse():
    var errors: seq[ParserError]
    discard ? parser.expect(optional_empty_line_spec)

    let maybe_module = parser.expect(module_spec, 0)
    if maybe_module.is_ok: modules.add(maybe_module.get)
    else: errors.add(maybe_module.error)

    let maybe_function = parser.expect(function_spec, 0)
    if maybe_function.is_ok: functions.add(maybe_function.get)
    else: errors.add(maybe_function.error)

    # NOTE: Error out if the parser failed to parse both module and function
    if errors.len == 2: return err(errors.max())

  new_file(parser.path(), parser.indent(), modules, functions)
