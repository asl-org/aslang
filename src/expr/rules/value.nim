import "../parser"

from init import init_rule
from fncall import fncall_rule

from reducer import value_reducer

let value_rule* = non_terminal_rule("value", @[
  new_production(@[init_rule.exact_one]),
  new_production(@[fncall_rule.exact_one])
], value_reducer)
