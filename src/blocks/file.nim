import sequtils, strutils, results, strformat, options

import token, function, struct, arg_def, module

type File* = ref object of RootObj
  location*: Location
  modules*: seq[Module]
  functions*: seq[Function]

proc name*(file: File): string =
  file.location.filename

proc new_file*(filename: string): File =
  let modules = builtins().map_it(new_module(it))
  File(modules: modules, location: new_file_location(filename))

proc `$`*(file: File): string = file.functions.map_it($(it)).join("\n\n")

proc find_module*(file: File, module_name: Token): Result[Module, string] =
  for module in file.modules:
    if $(module.name) == $(module_name):
      return ok(module)
  err(fmt"Module `{module_name}` does not exist in the scope")

proc find_struct*(file: File, struct_name: Token): Result[NamedStruct, string] =
  for module in file.modules:
    let maybe_named_struct = module.named_struct()
    if maybe_named_struct.is_err: continue

    let named_struct = maybe_named_struct.get
    if $(named_struct.name) == $(struct_name): return ok(named_struct)
  err(fmt"Struct `{struct_name}` does not exist in the scope")

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

proc add_module*(file: File, module: Module): Result[void, string] =
  ? file.check_if_duplicate(module)
  file.modules.add(module)
  ok()

proc add_function*(file: File, function: Function): Result[void, string] =
  ? file.check_if_duplicate(function)
  file.functions.add(function)
  ok()
