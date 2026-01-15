import strformat, hashes

import constants

type Cursor* = object
  index: int = 0
  line: int = 1
  col: int = 1

proc index*(cursor: Cursor): int = cursor.index

proc `$`*(cursor: Cursor): string =
  fmt"{cursor.line}:{cursor.col}"

proc hash*(cursor: Cursor): Hash =
  hash((cursor.index, cursor.line, cursor.col))

proc update*(cursor: Cursor, value: string): Cursor =
  var updated = cursor
  for x in value:
    updated.index += 1
    if x == constants.NEW_LINE:
      updated.line += 1;
      updated.col = 1
    else:
      updated.col += 1
  return updated
