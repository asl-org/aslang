import "../base"

proc is_not_double_quote(x: char): bool = x.is_visible and x != '"'

proc escaped_double_quote_transform(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  raw_value_transform("\"", location)

proc string_transform(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  let value = parts.raw_value
  new_string_literal($(value[0..<(^1)]),
      location).new_string_literal_parse_result()

let string_literal_rules* = @[
  # except_double_quote ::= [^"]
  dynamic_terminal_rule("except_double_quote", is_not_double_quote,
      raw_value_transform),
  # escaped_double_quote ::= backslash double_quote
  non_terminal_rule("escaped_double_quote", @["backslash double_quote"],
      escaped_double_quote_transform),
  # string_content ::= except_double_quote | escaped_double_quote
  non_terminal_rule("string_content", @["escaped_double_quote",
      "except_double_quote"], raw_parts_transform),
  # string ::= double_quote string_content* double_quote
  non_terminal_rule("string_literal", @[
      "double_quote string_content* double_quote"], string_transform),
]
