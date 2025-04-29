import strutils

import "../parser"

from common import is_visible, raw_value_transform, raw_parts_transform

let word_rules* = @[
  # visible_characters ::= [^\n]
  dynamic_terminal_rule("visible_characters", is_visible,
      raw_value_transform),
  # lowercase_alphabet ::= [a-z]
  dynamic_terminal_rule("lowercase_alphabet", is_lower_ascii,
      raw_value_transform),
  # uppercase_alphabet ::= [A-Z]
  dynamic_terminal_rule("uppercase_alphabet", is_upper_ascii,
      raw_value_transform),
  # alphabet ::= lowercase_alphabet | uppercase_alphabet
  non_terminal_rule("alphabet", @["lowercase_alphabet", "uppercase_alphabet"],
      raw_parts_transform),
  # word ::= alphabet+
  non_terminal_rule("word", @["alphabet+"], raw_parts_transform),
  # comment ::= space* hashtag visible_characters+ new_line?
  non_terminal_rule("comment", @["space* hashtag visible_characters+ new_line?"],
      raw_parts_transform),
  # empty_space ::= space* new_line | space+
  non_terminal_rule("empty_space", @["space* new_line", "space+"],
      raw_parts_transform),
]
