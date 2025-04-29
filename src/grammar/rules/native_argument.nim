import "../parser"
import "../transformer"

import "../location"
import "../common/native_literal"
import "../common/native_argument"

proc native_literal_transform(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  var native_literal: NativeLiteral
  if parts[0].len > 0:
    native_literal = new_native_float_literal(parts[0][0][0].raw_value, location)
  elif parts[1].len > 0:
    native_literal = new_native_int_literal(parts[1][0][0].raw_value, location)
  elif parts[2].len > 0:
    native_literal = new_native_str_literal(parts[2][0][0].raw_value, location)

  new_native_literal_parse_result(native_literal)

proc native_argument_transform(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  var native_arg: NativeArgument
  if parts[0].len > 0:
    native_arg = new_native_literal_argument(parts[0][0][0].native_literal, location)
  elif parts[1].len > 0:
    native_arg = new_native_identifier_argument(parts[1][0][0].identifier, location)

  new_native_arg_parse_result(native_arg)

let native_argument_rules* = @[
  # native_literal ::= number | identifier (order matters here)
  non_terminal_rule("native_literal", @["float", "integer", "string"],
      native_literal_transform),
  # native_argument ::= native_literal | identifier
  non_terminal_rule("native_argument", @["native_literal", "identifier"],
      native_argument_transform),
]
