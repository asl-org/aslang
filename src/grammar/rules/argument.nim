import base

proc numeric_literal_transform(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  var numeric_literal: NumericLiteral
  if parts[0].len > 0:
    numeric_literal = new_native_float_literal(parts[0][0][0].raw_value, location)
  elif parts[1].len > 0:
    numeric_literal = new_native_int_literal(parts[1][0][0].raw_value, location)

  new_numeric_literal_parse_result(numeric_literal)

proc argument_transform(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  var arg: Argument
  if parts[0].len > 0:
    arg = new_literal_argument(parts[0][0][0].numeric_literal, location)
  elif parts[1].len > 0:
    arg = new_identifier_argument(parts[1][0][0].identifier, location)

  new_argument_parse_result(arg)

let argument_rules* = @[
  # numeric_literal ::= float | integer (order matters here)
  non_terminal_rule("numeric_literal", @["float", "integer"],
      numeric_literal_transform),
  # argument ::= numeric_literal | identifier
  non_terminal_rule("argument", @["numeric_literal", "identifier"],
      argument_transform),
]
