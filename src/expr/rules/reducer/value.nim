import parse_result

proc value_reducer*(location: Location, parts: seq[seq[seq[
    ParserResult]]]): (Location, ParserResult) =
  var pr: ParserResult
  if parts[0].len > 0:
    pr = parts[0][0][0].init.new_value().to_parse_result()
  elif parts[1].len > 0:
    pr = parts[1][0][0].fncall.new_value().to_parse_result()

  (location, pr)
