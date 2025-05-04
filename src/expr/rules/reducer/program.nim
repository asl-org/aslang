import sequtils

import parse_result

proc comment_reducer*(location: Location, parts: seq[seq[seq[ParserResult]]]): (
    Location, ParserResult) =
  var comment: string
  for x in parts[0][1]: comment.add(x.content)
  let pr = new_comment(comment).to_parse_result()
  (location, pr)

proc line_reducer*(location: Location, parts: seq[seq[seq[
    ParserResult]]]): (Location, ParserResult) =
  var pr: ParserResult
  if parts[0].len > 0:
    let spaces = parts[0][0].len
    pr = parts[0][1][0].statement.new_line(spaces).to_parse_result()
  elif parts[1].len > 0:
    let spaces = parts[1][0].len
    pr = parts[1][1][0].comment.new_line(spaces).to_parse_result()
  else:
    let spaces = parts[2][0].len
    pr = new_empty_line(spaces).to_parse_result()
  (location, pr)

proc leading_line_reducer*(location: Location, parts: seq[seq[seq[
    ParserResult]]]): (Location, ParserResult) = (location, parts[0][0][0])

proc program_reducer*(location: Location, parts: seq[seq[seq[ParserResult]]]): (
    Location, ParserResult) =
  let lines = parts[0][0] & parts[0][1]
  let program = lines.map(proc(x: ParserResult): Line = x.line).new_program()
  let pr = program.to_parse_result()
  (location, pr)
