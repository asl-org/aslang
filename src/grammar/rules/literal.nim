import base

import literal/numeric_literal
import literal/string_literal
import literal/struct_literal

proc literal_transform(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  var literal: Literal
  if parts[0].len > 0:
    literal = new_numeric_literal(parts[0][0][0].numeric_literal, location)
  if parts[1].len > 0:
    literal = new_string_literal(parts[1][0][0].string_literal, location)
  elif parts[2].len > 0:
    literal = new_struct_literal(parts[2][0][0].struct_literal, location)
  new_literal_parse_result(literal)

var literal_rules*: seq[Rule[ParseResult]]
literal_rules.add(numeric_literal_rules)
literal_rules.add(string_literal_rules)
literal_rules.add(struct_literal_rules)
literal_rules.add(@[
  # literal ::= native_literal | string_literal | struct_literal
  non_terminal_rule("literal", @["numeric_literal", "string_literal",
      "struct_literal"], literal_transform),
])
