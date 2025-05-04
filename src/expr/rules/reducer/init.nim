import parse_result

proc init_reducer*(location: Location, parts: seq[seq[seq[
    ParserResult]]]): (Location, ParserResult) =
  let module_name = parts[0][0][0].content
  let literal = parts[0][2][0].content
  let pr = new_init(module_name, literal, location).to_parse_result()

  (location, pr)
