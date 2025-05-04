import sequtils

import parse_result

proc leading_arg_reducer*(location: Location, parts: seq[seq[seq[
    ParserResult]]]): (Location, ParserResult) = (location, parts[0][0][0])

proc arglist_reducer*(location: Location, parts: seq[seq[seq[
    ParserResult]]]): (Location, ParserResult) =
  let args = parts[0][2] & parts[0][3]
  let arg_names = args.map(proc(x: ParserResult): string = x.content)
  let pr = new_arglist(arg_names, location).to_parse_result()

  (location, pr)
