import strformat

type
  Location* = object
    filename*: string
    line*: int = 1
    column*: int = 1
    index*: int = 0

proc `$`*(location: Location): string =
  fmt"{location.filename}({location.line}, {location.column})"
