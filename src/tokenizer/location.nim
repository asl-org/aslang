import strformat, hashes

type Location* = object
  filepath: string
  line: int
  col: int

proc newLocation(filepath: string, line, col: int): Location =
  Location(filepath: filepath, line: line, col: col)
proc newLocation*(filepath: string): Location = newLocation(filepath, 1, 1)
proc newLocation*(): Location = newLocation("", 1, 1)

proc advance*(loc: Location, line: bool = false): Location =
  var location = loc
  if line:
    location.line += 1
    location.col = 1
  else:
    location.col += 1
  return location

proc `$`*(loc: Location): string = fmt"{loc.line}:{loc.col}"
proc hash*(a: Location): Hash = a.filepath.hash !& a.line.hash !& a.col.hash
proc `==`*(a, b: Location): bool = a.hash == b.hash
proc `<`*(a, b: Location): bool =
  if a.line == b.line: a.col < b.col
  else: a.line < b.line