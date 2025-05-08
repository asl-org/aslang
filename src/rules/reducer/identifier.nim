import strutils, sequtils

import parse_result

proc identifier_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): (Location, ParseResult) =
  let head = parts[0][0][0].raw_string
  let tail = parts[0][1].map(proc(x: ParseResult): string = x.raw_string).join("")
  let identifier = new_identifier(head & tail, location)
  (location, identifier.to_parse_result())
