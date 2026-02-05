import results, strformat, strutils, sequtils, re, tables, hashes

import core, module, function, identifier, defs

# =============================================================================
# File
# =============================================================================

type File* = ref object of RootObj
  path: string
  indent: int
  modules_repo: Repo[Module]
  functions_repo: Repo[Function]

proc new_file*(path: string, indent: int, modules: seq[Module],
    functions: seq[Function]): Result[File, core.Error] =
  if functions.len + modules.len == 0:
    return err(err_parser_empty_file(path))

  let maybe_modules_repo = new_repo(modules, @[new_index[Module]("name", name, true)])
  if maybe_modules_repo.is_err:
    let error = maybe_modules_repo.error
    let module = error.current
    let predefined_module_location = error.previous.location
    return err(err_parser_module_already_defined(module.location,
          module.name.asl, predefined_module_location))

  let maybe_functions_repo = new_repo(functions, @[new_index[Function]("def",
      proc(fn: Function): Hash = fn.def.hash, true)])
  if maybe_functions_repo.is_err:
    let error = maybe_functions_repo.error
    let function = error.current
    let predefined_function_location = error.previous.location
    return err(err_parser_function_already_defined(function.location,
          function.name.asl, predefined_function_location))

  let modules_repo = maybe_modules_repo.get
  let functions_repo = maybe_functions_repo.get

  for index, function in functions:
    # NOTE: Validate module and function name collisions
    let maybe_module = modules_repo.find("name", function.name)
    if maybe_module.is_ok:
      let module = maybe_module.get[0]
      return err(err_parser_function_module_conflict(function.location,
          function.name.asl, module.location, module.name.asl))

  ok(File(path: path, indent: indent, modules_repo: modules_repo,
      functions_repo: functions_repo))

proc path*(file: File): string = file.path
proc indent*(file: File): int = file.indent
proc modules*(file: File): seq[Module] = file.modules_repo.items
proc functions*(file: File): seq[Function] = file.functions_repo.items

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
  let maybe_module = file.modules_repo.find("name", module_name)
  if maybe_module.is_ok: ok(maybe_module.get[0])
  else: err(fmt"{module_name.location} [PE168] module `{module_name.asl}` is not defined in the file {file.path}")

proc file_spec*(parser: Parser, builtin_modules: seq[Module]): Result[File,
    core.Error] =
  var modules = builtin_modules
  var functions: seq[Function]
  while parser.can_parse():
    var errors: seq[core.Error]
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
