import "../parser"

import base
from reducer import init_reducer

let init_rule* = non_terminal_rule("init", @[
  new_production(@[
    identifier.exact_one,
    space.any,
    integer.exact_one
  ])
], init_reducer)
