import strformat

import "../token"

type ModuleDefinition* = ref object of RootObj
  name*: Token
  location*: Location

proc new_module_definition*(name: Token, location: Location): ModuleDefinition =
  ModuleDefinition(name: name, location: location)

proc new_module_definition*(name: string): ModuleDefinition =
  ModuleDefinition(name: new_id_token(name))

proc `$`*(module_def: ModuleDefinition): string =
  fmt"module {module_def.name}:"
