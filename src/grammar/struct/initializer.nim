import strformat

import "../location"
import identifier, literal

type Initializer* = ref object of RootObj
  result_var: Identifier
  module: Identifier
  literal: Literal
  location: Location

proc result_var*(init: Initializer): Identifier = init.result_var
proc module*(init: Initializer): Identifier = init.module
proc literal*(init: Initializer): Literal = init.literal

proc `$`*(init: Initializer): string =
  fmt"{init.result_var} = {init.module} {init.literal}"

proc new_initializer*(dest: Identifier, module: Identifier,
    literal: Literal, location: Location): Initializer =
  Initializer(result_var: dest, module: module, literal: literal,
      location: location)
