import sequtils, strutils, results, strformat

import token, function, module

type File* = ref object of RootObj
  location*: Location
  modules*: seq[Module]
  functions*: seq[Function]

proc name*(file: File): string =
  file.location.filename

proc user_modules*(file: File): seq[Module] =
  file.modules.filter_it(it.kind == MK_USER)

proc struct_modules*(file: File): seq[Module] =
  file.user_modules.filter_it(it.is_struct)

proc new_file*(filename: string): File =
  let modules = builtins().map_it(new_module(it))
  File(modules: modules, location: new_file_location(filename))

proc `$`*(file: File): string = file.functions.map_it($(it)).join("\n\n")

proc find_module*(file: File, module_name: Token): Result[Module, string] =
  for module in file.modules:
    if $(module.name) == $(module_name):
      return ok(module)
  err(fmt"Module `{module_name}` does not exist in the scope")

proc find_start_function*(file: File): Result[Function, string] =
  for function in file.functions:
    if function.is_start():
      return ok(function)
  err(fmt"{file.name} failed to find start function")

proc find_function(file: File, func_def: FunctionDefinition): Result[Function, string] =
  for function in file.functions:
    if function.definition == func_def:
      return ok(function)
  err(fmt"Function `{func_def.name}` is not defined in the scope")

proc add_module*(file: File, module: Module): Result[void, string] =
  let maybe_found = file.find_module(module.name)
  if maybe_found.is_ok:
    let predefined_location = maybe_found.get.location
    return err(fmt"{module.location} Module `{module.name}` is already defined in {predefined_location}")
  file.modules.add(module)
  ok()

proc add_function*(file: File, function: Function): Result[void, string] =
  let maybe_found = file.find_function(function.definition)
  if maybe_found.is_ok:
    let predefined_location = maybe_found.get.location
    return err(fmt"{function.location} Function `{function.name}` is already defined in {predefined_location}")
  file.functions.add(function)
  ok()

proc close*(file: File): Result[void, string] =
  if file.functions.len == 0 and file.user_modules.len == 0:
    return err(fmt"File must contain at least one module or function")
  ok()
