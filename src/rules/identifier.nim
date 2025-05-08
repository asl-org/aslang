import "../parser"
import reducer

import character

# non terminal rule
let alphabet_rule* = non_terminal_rule("alphabet", @[
  new_production(@[lowercase_alphabet.exact_one]),
  new_production(@[uppercase_alphabet.exact_one])
], raw_parts_reducer)

let identifier_head_rule* = non_terminal_rule("identifier_head", @[
  new_production(@[underscore.exact_one]),
  new_production(@[alphabet_rule.exact_one])
], raw_parts_reducer)

let identifier_tail_rule* = non_terminal_rule("identifier_tail", @[
  new_production(@[identifier_head_rule.exact_one]),
  new_production(@[digit.exact_one])
], raw_parts_reducer)

let identifier_rule* = non_terminal_rule("identifier", @[
  new_production(@[identifier_head_rule.exact_one(), identifier_tail_rule.any()])
], identifier_reducer)
