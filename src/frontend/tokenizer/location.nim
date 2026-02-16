import strformat, hashes

import cursor

type Location* = ref object of RootObj
  filename: string
  head: Cursor
  tail: Cursor

proc new_location*(filename: string, head: Cursor, tail: Cursor): Location =
  Location(filename: filename, head: head, tail: tail)

proc new_location*(filename: string): Location =
  Location(filename: filename)

proc tail*(location: Location): Cursor = location.tail

proc `$`*(location: Location): string =
  fmt"{location.filename}:{location.head}"

proc hash*(location: Location): Hash =
  hash((location.filename, location.head, location.tail))

proc `<`*(self: Location, other: Location): bool = self.head < other.head
proc `>`*(self: Location, other: Location): bool = self.head > other.head
proc `==`*(self: Location, other: Location): bool = self.head == other.head
