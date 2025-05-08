import "../parser"
import character
import reducer

let integer* = non_terminal_rule("integer", @[
  new_production(@[digit.at_least_one])
], raw_parts_reducer)
