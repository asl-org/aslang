import strformat

import location
import value

type Assignment* = ref object of RootObj
  dest_var_name: string
  value: Value
  location: Location

proc new_assignment*(dest: string, value: Value,
    location: Location): Assignment =
  Assignment(dest_var_name: dest, value: value, location: location)

proc `$`*(assign: Assignment): string =
  fmt"{assign.dest_var_name} = {assign.value}"
