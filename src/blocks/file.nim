import sequtils, strutils, results, strformat

import token, function, struct, arg_def, module, builtin_module

type File* = ref object of RootObj
  location*: Location
  builtin_modules*: seq[BuiltinModule]
  modules*: seq[Module]
  functions*: seq[Function]
  structs*: seq[NamedStruct]

proc name*(file: File): string =
  file.location.filename

proc new_file*(filename: string): File =
  File(builtin_modules: builtins(), location: new_file_location(filename))

proc `$`*(file: File): string =
  @[
    file.structs.map_it($(it)).join("\n\n"),
    file.functions.map_it($(it)).join("\n\n")
  ].join("\n\n")

proc find_builtin_module*(file: File, module_name: Token): Result[BuiltinModule, string] =
  for module in file.builtin_modules:
    if $(module) == $(module_name):
      return ok(module)
  err(fmt"{module_name} does not exist in the scope")

proc find_struct*(file: File, struct_name: Token): Result[NamedStruct, string] =
  for struct in file.structs:
    if $(struct.name) == $(struct_name):
      return ok(struct)
  err(fmt"{struct_name} does not exist in the scope")

proc find_module*(file: File, module_name: Token): Result[void, string] =
  var maybe_found = file.find_builtin_module(module_name)
  if maybe_found.is_ok: return ok()

  discard ? file.find_struct(module_name)
  ok()

proc find_start_function*(file: File): Result[Function, string] =
  for function in file.functions:
    if function.is_start():
      return ok(function)
  err(fmt"{file.name} failed to find start function")

proc check_if_duplicate(file: File, fn: Function): Result[void, string] =
  for function in file.functions:
    if function.name != fn.name: continue
    if function.arity != fn.arity: continue

    var matched = true
    for (function_arg, fn_arg) in zip(function.arg_def_list, fn.arg_def_list):
      if $(function_arg.arg_type) != $(fn_arg.arg_type):
        matched = false
    if matched:
      return err(fmt"{fn.location} {fn.name} is already defined in {function.location}")
  ok()

proc check_if_duplicate(file: File, module: Module): Result[void, string] =
  for pre_defined_module in file.modules:
    if $(pre_defined_module.name) == $(module.name):
      return err(fmt"{module.location} {module.name} is already defined in {pre_defined_module.location}")
  ok()

proc check_if_duplicate(file: File, struct: NamedStruct): Result[void, string] =
  for pre_defined_struct in file.structs:
    if $(pre_defined_struct.name) == $(struct.name):
      return err(fmt"{struct.location} {struct.name} is already defined in {pre_defined_struct.location}")
  ok()

proc add_module*(file: File, module: Module): Result[void, string] =
  ? file.check_if_duplicate(module)
  file.modules.add(module)
  ok()

proc add_function*(file: File, function: Function): Result[void, string] =
  ? file.check_if_duplicate(function)
  file.functions.add(function)
  ok()

proc add_struct*(file: File, struct: NamedStruct): Result[void, string] =
  ? file.check_if_duplicate(struct)
  file.structs.add(struct)
  ok()
