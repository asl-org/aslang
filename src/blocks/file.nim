import sequtils, strutils, results, strformat, tables

import token, function, module

type File* = ref object of RootObj
  location*: Location
  modules*: Table[string, Module]
  functions*: Table[string, Function]

proc new_file*(filename: string): File =
  var modules: Table[string, Module]
  for builtin_mod in builtins():
    modules[$(builtin_mod.name)] = new_module(builtin_mod)

  File(modules: modules, location: new_file_location(filename))

proc name*(file: File): string =
  file.location.filename

proc `$`*(file: File): string =
  # TODO: Fix content indentation
  @[
    file.functions.values.to_seq.map_it($(it)).join("\n\n"),
    file.modules.values.to_seq.map_it($(it)).join("\n\n"),
  ].join("\n\n")

proc user_modules*(file: File): seq[UserModule] =
  file.modules.values.to_seq.filter_it(it.safe_user_module.is_ok).map_it(it.user_module)

proc find_module*(file: File, module_name: Token): Result[Module, string] =
  if $(module_name) notin file.modules:
    return err(fmt"Module `{module_name}` does not exist in the scope")
  let module = file.modules[$(module_name)]
  ok(module)

proc find_function*(file: File, func_def: FunctionDefinition): Result[Function, string] =
  if $(func_def.name) notin file.functions:
    return err(fmt"Function `{func_def.name}` is not defined in the scope")
  ok(file.functions[$(func_def.name)])

proc find_start_function*(file: File): Result[Function, string] =
  for function in file.functions.values:
    if function.is_start():
      return ok(function)
  err(fmt"{file.name} failed to find start function")

proc add_module*(file: File, user_module: UserModule): Result[void, string] =
  let maybe_found = file.find_module(user_module.name)
  if maybe_found.is_ok:
    let predefined_location = maybe_found.get.location
    return err(fmt"{user_module.location} Module `{user_module.name}` is already defined in {predefined_location}")
  file.modules[$(user_module.name)] = new_module(user_module)
  ok()

proc add_function*(file: File, function: Function): Result[void, string] =
  let maybe_found = file.find_function(function.definition)
  if maybe_found.is_ok:
    let predefined_location = maybe_found.get.location
    return err(fmt"{function.location} Function `{function.name}` is already defined in {predefined_location}")
  file.functions[$(function.name)] = function
  ok()

proc close*(file: File): Result[void, string] =
  if file.functions.len == 0 and file.user_modules.len == 0:
    return err(fmt"File must contain at least one module or function")
  ok()
