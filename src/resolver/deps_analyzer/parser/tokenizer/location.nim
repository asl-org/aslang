import strformat, hashes

import cursor

type Location* = ref object of RootObj
  filename: string
  head: Cursor
  tail: Cursor

proc new_location*(filename: string, head: Cursor, tail: Cursor): Location =
  Location(filename: filename, head: head)

proc `$`*(location: Location): string =
  fmt"{location.filename}:{location.head}"

proc hash*(location: Location): Hash =
  hash((location.filename, location.head, location.tail))
