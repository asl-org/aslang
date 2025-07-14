import sequtils, strutils, results, strformat, tables

import token, function, module

type File* = ref object of RootObj
  location*: Location
  builtin_modules: Table[string, BuiltinModule]
  user_modules*: Table[string, UserModule]
  functions*: Table[string, Function]

proc new_file*(filename: string): File =
  var modules: Table[string, BuiltinModule]
  for builtin_mod in builtins(): modules[$(builtin_mod.name)] = builtin_mod
  File(builtin_modules: modules, location: new_file_location(filename))

proc name*(file: File): string =
  file.location.filename

proc struct_modules*(file: File): seq[UserModule] =
  file.user_modules.values.to_seq.filter_it(it.is_struct)

proc `$`*(file: File): string =
  file.functions.values.to_seq.map_it($(it)).join("\n\n")

proc find_builtin_module*(file: File, module_name: Token): Result[BuiltinModule, string] =
  if $(module_name) notin file.builtin_modules:
    return err(fmt"Builtin Module `{module_name}` does not exist in the scope")
  ok(file.builtin_modules[$(module_name)])

proc find_user_module*(file: File, module_name: Token): Result[UserModule, string] =
  if $(module_name) notin file.user_modules:
    return err(fmt"User Module `{module_name}` does not exist in the scope")
  ok(file.user_modules[$(module_name)])

proc find_module*(file: File, module_name: Token): Result[Location, string] =
  let maybe_builtin_module = file.find_builtin_module(module_name)
  if maybe_builtin_module.is_ok: return ok(maybe_builtin_module.get.location)

  let maybe_user_module = file.find_user_module(module_name)
  if maybe_user_module.is_ok: return ok(maybe_user_module.get.location)

  return err(fmt"Module `{module_name}` does not exist in the scope")

proc find_function*(file: File, func_def: FunctionDefinition): Result[Function, string] =
  if $(func_def.name) notin file.functions:
    return err(fmt"Function `{func_def.name}` is not defined in the scope")
  ok(file.functions[$(func_def.name)])

proc find_start_function*(file: File): Result[Function, string] =
  for function in file.functions.values:
    if function.is_start():
      return ok(function)
  err(fmt"{file.name} failed to find start function")

proc add_module*(file: File, module: UserModule): Result[void, string] =
  let maybe_found = file.find_module(module.name)
  if maybe_found.is_ok:
    let predefined_location = maybe_found.get
    return err(fmt"{module.location} Module `{module.name}` is already defined in {predefined_location}")
  file.user_modules[$(module.name)] = module
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
