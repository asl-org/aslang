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

proc `$`*(module: UserModule): string =
  let prefix = " ".repeat(module.module_def.location.column - 1)
  let child_prefix = " ".repeat(module.module_def.location.column + 1)
  var lines = @[prefix & $(module.module_def)]
  for function in module.functions:
    lines.add(child_prefix & $(function))
  return lines.join("\n")

proc add_function*(module: UserModule, function: Function): void =
  module.functions.add(function)

proc add_struct*(module: UserModule, struct: Struct): void =
  module.struct = some(struct)

proc new_user_module*(module_def: ModuleDefinition): UserModule =
  UserModule(module_def: module_def)

proc to_named_struct*(module: UserModule): Result[NamedStruct, string] =
  if module.struct.is_none:
    return err(fmt"Module `{module.name}` is not a struct.")

  let struct = module.struct.get
  let struct_def = new_named_struct_definition(module.name, struct.location)
  let named_struct = new_named_struct(struct_def)
  for field in struct.fields: named_struct.add_field(field)

  ok(named_struct)
