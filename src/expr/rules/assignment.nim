import "../parser"

import base

from value import value_rule
from reducer import assignment_reducer

let assignment_rule* = non_terminal_rule("assignment", @[
  new_production(@[
    identifier.exact_one,
    space.any,
    equal.exact_one,
    space.any,
    value_rule.exact_one,
  ])
], assignment_reducer)
