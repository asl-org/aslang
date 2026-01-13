import strformat, hashes

import constants

type Location* = object
  filename: string
  line: int = 1
  col: int = 1

proc new_location*(filename: string): Location =
  Location(filename: filename)

proc update*(location: Location, value: string): Location =
  var new_location = location
  for x in value:
    if x == NEW_LINE:
      new_location.line += 1
      new_location.col = 1
    else:
      new_location.col += 1
  return new_location

proc `$`*(location: Location): string =
  fmt"{location.filename}:{location.line}:{location.col}"

proc hash*(location: Location): Hash =
  hash(location.filename) !& hash(location.line) !& hash(location.col)
