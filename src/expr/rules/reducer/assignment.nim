import parse_result

proc assignment_reducer*(location: Location, parts: seq[seq[seq[
    ParserResult]]]): (Location, ParserResult) =
  let result_var_name = parts[0][0][0].content
  let value = parts[0][4][0].value
  let pr = new_assignment(result_var_name, value, location).to_parse_result()

  (location, pr)
