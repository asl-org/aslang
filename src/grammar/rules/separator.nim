import "../parser"
from common import raw_parts_transform

let separator_rules* = @[
  # colon_separated ::= space* colon space*
  non_terminal_rule("colon_separated", @["space* colon space*"],
      raw_parts_transform),
  # comma_separated ::= space* comma space*
  non_terminal_rule("comma_separated", @["space* comma space*"],
      raw_parts_transform),
  # equal_separated ::= space* equal space*
  non_terminal_rule("equal_separated", @["space* equal space*"],
      raw_parts_transform),
]
