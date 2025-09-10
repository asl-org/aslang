import sequtils, strutils, results, strformat, tables, hashes

import token, function, module, arg_def

type File* = ref object of RootObj
  location*: Location
  module_map*: Table[string, int]
  modules*: seq[Module]
  function_map*: Table[Hash, int]
  functions*: seq[Function]

proc new_file*(filename: string): File =
  var module_map: Table[string, int]
  var modules: seq[Module]
  for (index, builtin_mod) in builtins().pairs:
    module_map[$(builtin_mod.name)] = index
    modules.add(new_module(builtin_mod))

  File(module_map: module_map, modules: modules, location: new_file_location(filename))

proc name*(file: File): string =
  file.location.filename

proc `$`*(file: File): string =
  # TODO: Fix content indentation
  @[
    file.functions.map_it($(it)).join("\n\n"),
    file.modules.map_it($(it)).join("\n\n"),
  ].join("\n\n")

proc user_modules*(file: File): seq[UserModule] =
  file.modules.filter_it(it.kind == MK_USER).map_it(it.user_module)

proc find_module*(file: File, arg_type: ArgumentType): Result[Module, string] =
  if $(arg_type.parent) notin file.module_map:
    return err(fmt"{arg_type.parent.location} Module `{arg_type.parent}` does not exist in the scope")
  let module = file.modules[file.module_map[$(arg_type.parent)]]
  ok(module)

proc find_function*(file: File, func_def: FunctionDefinition): Result[Function, string] =
  if func_def.hash notin file.function_map:
    return err(fmt"{file.name}: Failed to find matching function `{func_def.name}`")
  ok(file.functions[file.function_map[func_def.hash]])

proc add_module*(file: File, user_module: UserModule): Result[void, string] =
  # echo "find_module: 12"
  let maybe_found = file.find_module(new_argument_type(user_module.name))
  if maybe_found.is_ok:
    let predefined_module = maybe_found.get
    case predefined_module.kind:
    of MK_BUILTIN:
      err(fmt"{user_module.location} Module `{user_module.name}` conflicts with a builtin module named `{predefined_module.name}`")
    of MK_USER:
      err(fmt"{user_module.location} Module `{user_module.name}` is already defined in {predefined_module.location}")
  else:
    file.module_map[$(user_module.name)] = file.modules.len
    file.modules.add(new_module(user_module))
    ok()

proc add_function*(file: File, function: Function): Result[void, string] =
  let maybe_found = file.find_function(function.definition)
  if maybe_found.is_ok:
    let predefined_location = maybe_found.get.location
    return err(fmt"{function.location} Function `{function.name}` is already defined in {predefined_location}")
  file.function_map[function.definition.hash] = file.functions.len
  file.functions.add(function)
  ok()

proc close*(file: File): Result[void, string] =
  if file.functions.len == 0 and file.user_modules.len == 0:
    return err(fmt"File must contain at least one module or function")
  ok()
