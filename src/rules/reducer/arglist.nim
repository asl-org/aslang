import sequtils

import parse_result

proc leading_arg_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): (Location, ParseResult) = (location, parts[0][0][0])

proc arglist_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): (Location, ParseResult) =
  let args = (parts[0][2] & parts[0][3]).map(proc(
      x: ParseResult): Identifier = x.identifier)
  let pr = new_arglist(args, location).to_parse_result()
  (location, pr)
