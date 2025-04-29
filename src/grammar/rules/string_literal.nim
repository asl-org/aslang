import "../parser"

from common import is_not_double_quote, raw_value_transform, raw_parts_transform

let string_literal_rules* = @[
  # except_double_quote ::= [^"]
  dynamic_terminal_rule("except_double_quote", is_not_double_quote,
      raw_value_transform),
  # escaped_double_quote ::= backslash double_quote
  non_terminal_rule("escaped_double_quote", @["backslash double_quote"],
      raw_parts_transform),
  # string_content ::= except_double_quote | escaped_double_quote
  non_terminal_rule("string_content", @["escaped_double_quote",
      "except_double_quote"], raw_parts_transform),
  # string ::= double_quote string_content* double_quote
  non_terminal_rule("string", @["double_quote string_content* double_quote"],
      raw_parts_transform),
]
