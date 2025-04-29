import "../transformer"
import "../location"

proc raw_value_transform*(value: string, location: Location): ParseResult =
  new_raw_value_parse_result(value, location)

proc raw_parts_transform*(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  var value: string
  for prod in parts:
    for symbol in prod:
      for item in symbol:
        value.add($(item))
  raw_value_transform(value, location)

proc is_visible*(x: char): bool =
  x.ord in 32..<127

proc is_not_double_quote*(x: char): bool =
  x.is_visible and x != '"'
