import parse_result

proc raw_string_reducer*(location: Location, value: string): (Location, ParseResult) =
  var updated = location
  for x in value:
    if x == '\n': updated.line += 1; updated.col = 1
    else: updated.col += 1
  (updated, to_parse_result(value))

proc raw_parts_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): (Location, ParseResult) =
  var value: string
  for prod in parts:
    for sym in prod:
      for item in sym:
        value.add($(item))
  (location, to_parse_result(value))
