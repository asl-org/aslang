import strformat

import location

type
  StructKind = enum
    SK_RAW, SK_NON_TERMINAL

  Struct = ref object of RootObj
    location: Location
    case kind: StructKind
    of SK_RAW: value: string
    else: discard

proc `$`*(struct: Struct): string =
  fmt"{struct.location} {struct.kind} {struct.value}"

proc raw_terminal*(value: string, location: Location): Struct =
  Struct(kind: StructKind.SK_RAW, location: location, value: value)

proc raw_non_terminal*(parts: seq[seq[Struct]],
    location: Location): Struct =
  var value: string
  for group in parts:
    var collected: string
    for chunk in group:
      case chunk.kind:
      of StructKind.SK_RAW:
        collected.add(chunk.value)
      else: discard
    value.add(collected)
  Struct(kind: StructKind.SK_RAW, location: location, value: value)
