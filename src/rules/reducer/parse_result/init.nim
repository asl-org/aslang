import strformat

import location
import identifier

type Initializer* = ref object of RootObj
  module_name: Identifier
  literal: Identifier
  location: Location

proc `$`*(init: Initializer): string =
  fmt"{init.module_name} {init.literal}"

proc new_init*(mod_name: Identifier, literal: Identifier,
    location: Location): Initializer =
  Initializer(module_name: mod_name, literal: literal, location: location)
