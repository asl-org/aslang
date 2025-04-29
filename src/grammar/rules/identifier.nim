import "../parser"
import "../transformer"

import "../location"
import "../common/identifier"

proc extract_raw_value(parts: seq[seq[seq[ParseResult]]]): string =
  var value: string
  for prod in parts:
    for symbol in prod:
      for item in symbol:
        value.add($(item))
  return value

proc raw_value_transform(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  var value: string
  for prod in parts:
    for symbol in prod:
      for item in symbol:
        value.add($(item))
  parts.extract_raw_value.new_raw_value_parse_result(location)

proc identifier_transform(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  parts.extract_raw_value.new_identifier(location).new_identifier_parse_result()

let identifier_rules* = @[
  # identifier_head ::= word | underscore
  non_terminal_rule("identifier_head", @["word", "underscore"],
      raw_value_transform),
  # identifier_tail ::= word | underscore | integer
  non_terminal_rule("identifier_tail", @["word", "underscore", "integer"],
      raw_value_transform),
  # identifier ::= identifier_head identifier_tail*
  non_terminal_rule("identifier", @["identifier_head identifier_tail*"],
      identifier_transform),
]
