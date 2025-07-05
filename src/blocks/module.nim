import strformat, strutils, options

import token, function, struct

type ModuleDefinition* = ref object of RootObj
  name*: Token
  location*: Location

proc new_module_definition*(name: Token, location: Location): ModuleDefinition =
  ModuleDefinition(name: name, location: location)

proc `$`*(module_def: ModuleDefinition): string =
  fmt"module {module_def.name}:"

type Module* = ref object of RootObj
  module_def*: ModuleDefinition
  functions*: seq[Function]
  struct: Option[Struct]

proc location*(module: Module): Location =
  module.module_def.location

proc name*(module: Module): Token =
  module.module_def.name

proc `$`*(module: Module): string =
  let prefix = " ".repeat(module.module_def.location.column - 1)
  let child_prefix = " ".repeat(module.module_def.location.column + 1)
  var lines = @[prefix & $(module.module_def)]
  for function in module.functions:
    lines.add(child_prefix & $(function))
  return lines.join("\n")

proc add_function*(module: Module, function: Function): void =
  module.functions.add(function)

proc add_struct*(module: Module, struct: Struct): void =
  module.struct = some(struct)

proc new_module*(module_def: ModuleDefinition): Module =
  Module(module_def: module_def)
