import parse_result

proc fncall_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): (Location, ParseResult) =
  let module_name = parts[0][0][0].identifier
  let fn_name = parts[0][2][0].identifier
  let arglist = parts[0][3][0].arglist
  let pr = new_fncall(module_name, fn_name, arglist).to_parse_result()

  (location, pr)
