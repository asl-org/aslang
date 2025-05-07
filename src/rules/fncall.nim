import "../parser"
import base

from arglist import arglist_rule
from reducer import fncall_reducer

let fncall_rule* = non_terminal_rule("fncall", @[
  new_production(@[
    identifier.exact_one,
    period.exact_one,
    identifier.exact_one,
    arglist_rule.exact_one,
  ])
], fncall_reducer)
