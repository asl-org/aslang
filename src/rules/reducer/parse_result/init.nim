import strformat

import location

type Initializer* = ref object of RootObj
  module_name: string
  literal: string
  location: Location

proc `$`*(init: Initializer): string =
  fmt"{init.module_name} {init.literal}"

proc new_init*(mod_name: string, literal: string,
    location: Location): Initializer =
  Initializer(module_name: mod_name, literal: literal, location: location)
