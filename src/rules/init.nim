import "../parser"


from reducer import init_reducer
import character
import number
from identifier import identifier_rule

let init_rule* = non_terminal_rule("init", @[
  new_production(@[
    identifier_rule.exact_one,
    space.any,
    integer.exact_one
  ])
], init_reducer)
