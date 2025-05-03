import base

proc identifier_transform(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  parts.raw_value.new_identifier(location).new_identifier_parse_result()

let identifier_rules* = @[
  # identifier_head ::= word | underscore
  non_terminal_rule("identifier_head", @["word", "underscore"],
      raw_parts_transform),
  # identifier_tail ::= word | underscore | integer
  non_terminal_rule("identifier_tail", @["word", "underscore", "integer"],
      raw_parts_transform),
  # identifier ::= identifier_head identifier_tail*
  non_terminal_rule("identifier", @["identifier_head identifier_tail*"],
      identifier_transform),
]
