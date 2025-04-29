import strutils

import "../parser"

from common import raw_value_transform, raw_parts_transform

let numeric_literal_rules* = @[
  # digit ::= [0-9]
  dynamic_terminal_rule("digit", is_digit, raw_value_transform),
  # integer ::= digit+
  non_terminal_rule("integer", @["digit+"], raw_parts_transform),
  # float ::= integer period integer
  non_terminal_rule("float", @["integer period integer"], raw_parts_transform),
]
