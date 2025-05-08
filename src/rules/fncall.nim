import "../parser"

from arglist import arglist_rule
from reducer import fncall_reducer
import character
from identifier import identifier_rule

let fncall_rule* = non_terminal_rule("fncall", @[
  new_production(@[
    identifier_rule.exact_one,
    period.exact_one,
    identifier_rule.exact_one,
    arglist_rule.exact_one,
  ])
], fncall_reducer)
