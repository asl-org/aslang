import base

proc line_transform(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  if parts[0].len > 0:
    return new_statement_line(parts[0][0][0].statement).new_line_parse_result()
  elif parts[1].len > 0:
    return new_macro_header_line(parts[1][0][
        0].macro_header).new_line_parse_result()
  else:
    return new_ignorable_line().new_line_parse_result()

let line_rules* = @[
  # line ::= statement | comment | empty_space
  non_terminal_rule("line", @["statement", "macro", "comment", "empty_space"],
      line_transform),
]
