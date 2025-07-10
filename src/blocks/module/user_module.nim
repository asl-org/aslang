import strutils, options, results, strformat

import "../token"
import "../function"
import "../struct"

import module_def

type UserModule* = ref object of RootObj
  module_def*: ModuleDefinition
  functions*: seq[Function]
  struct*: Option[Struct]

proc location*(module: UserModule): Location = module.module_def.location
proc name*(module: UserModule): Token = module.module_def.name
proc is_struct*(module: UserModule): bool = module.struct.is_some

proc find_function*(module: UserModule, func_def: FunctionDefinition): Result[
    Function, string] =
  for function in module.functions:
    if function.definition == func_def:
      return ok(function)
  return err(fmt"Function `{func_def.name}` is not defined in the module `{module.name}`")

proc `$`*(module: UserModule): string =
  let prefix = " ".repeat(module.module_def.location.column - 1)
  let child_prefix = " ".repeat(module.module_def.location.column + 1)
  var lines = @[prefix & $(module.module_def)]
  for function in module.functions:
    lines.add(child_prefix & $(function))
  return lines.join("\n")

proc add_function*(module: UserModule, function: Function): Result[void, string] =
  let maybe_found = module.find_function(function.definition)
  if maybe_found.is_ok:
    let predefined_location = maybe_found.get.location
    return err(fmt"{function.location} Function `{function.name}` is already defined in module `{module.name}` at {predefined_location}")

  module.functions.add(function)
  ok()

proc add_struct*(module: UserModule, struct: Struct): Result[void, string] =
  if module.struct.is_some:
    let predefined_location = module.struct.get.location
    return err(fmt"{struct.location} Module `{module.name}` already contains a struct block at {predefined_location}")

  module.struct = some(struct)
  ok()

proc new_user_module*(module_def: ModuleDefinition): UserModule =
  UserModule(module_def: module_def)
