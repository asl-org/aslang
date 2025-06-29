import strformat

type Location* = object of RootObj
  filename*: string
  line: int = 1
  column*: int = 1

proc new_location*(filename: string): Location =
  Location(filename: filename)

proc new_file_location*(filename: string): Location =
  Location(filename: filename, line: 0, column: -1)

proc update*(location: Location, content: string): Location =
  var updated = location
  for x in content:
    if x == '\n':
      updated.line += 1
      updated.column = 1
    else:
      updated.column += 1
  return updated

proc `$`*(location: Location): string =
  fmt"{location.filename}:{location.line}:{location.column}"
