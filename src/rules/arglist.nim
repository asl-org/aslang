import "../parser"

from reducer import leading_arg_reducer, arglist_reducer
import character
from identifier import identifier_rule

let leading_arg_rule* = non_terminal_rule("leading_arg", @[
  new_production(@[
    identifier_rule.exact_one,
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
    identifier_rule.exact_one,
    space.any,
    paren_close.exact_one
  ])
], arglist_reducer)
