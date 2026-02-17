import strformat, hashes

import cursor
import ../../utils

struct Location:
  filename: string
  head: Cursor
  tail: Cursor

proc new_location*(filename: string, head: Cursor, tail: Cursor): Location =
  Location(filename: filename, head: head, tail: tail)

proc new_location*(filename: string): Location =
  Location(filename: filename)

proc `$`*(location: Location): string =
  fmt"{location.filename}:{location.head}"

proc hash*(location: Location): Hash =
  hash((location.filename, location.head, location.tail))

proc `<`*(self: Location, other: Location): bool = self.head < other.head
proc `>`*(self: Location, other: Location): bool = self.head > other.head
proc `==`*(self: Location, other: Location): bool = self.head == other.head
