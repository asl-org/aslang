import "../parser"

from identifier import identifier_rule
from value import value_rule
from reducer import assignment_reducer
import character

let assignment_rule* = non_terminal_rule("assignment", @[
  new_production(@[
    identifier_rule.exact_one,
    space.any,
    equal.exact_one,
    space.any,
    value_rule.exact_one,
  ])
], assignment_reducer)
