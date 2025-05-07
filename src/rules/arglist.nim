import "../parser"

import base
from reducer import leading_arg_reducer, arglist_reducer

let leading_arg_rule* = non_terminal_rule("leading_arg", @[
  new_production(@[
    identifier.exact_one,
    space.any,
    comma.exact_one,
    space.any
  ])
], leading_arg_reducer)

let arglist_rule* = non_terminal_rule("arglist", @[
  new_production(@[
    paren_open.exact_one,
    space.any,
    leading_arg_rule.any,
    identifier.exact_one,
    space.any,
    paren_close.exact_one
  ])
], arglist_reducer)
