import strformat

type Location* = object
  file: string
  line*: int = 1
  col*: int = 1

proc `$`*(location: Location): string =
  fmt"{location.file}({location.line},{location.col})"

proc new_location*(file: string): Location =
  Location(file: file)
