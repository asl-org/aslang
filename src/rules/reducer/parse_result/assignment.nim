import strformat

import location
import value
import identifier

type Assignment* = ref object of RootObj
  dest: Identifier
  value: Value
  location: Location

proc new_assignment*(dest: Identifier, value: Value,
    location: Location): Assignment =
  Assignment(dest: dest, value: value, location: location)

proc `$`*(assignment: Assignment): string =
  fmt"{assignment.dest} = {assignment.value}"
