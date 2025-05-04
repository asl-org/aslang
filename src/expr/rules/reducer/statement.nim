import parse_result

proc statement_reducer*(location: Location, parts: seq[seq[seq[
    ParserResult]]]): (Location, ParserResult) =
  var statement: Statement
  if parts[0].len > 0:
    statement = new_statement(parts[0][0][0].assign)
  elif parts[1].len > 0:
    statement = new_statement(parts[1][0][0].macro_call)

  (location, to_parse_result(statement))
