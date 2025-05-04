import "../parser"

from assignment import assignment_rule
from macro_call import macro_call_rule
from reducer import statement_reducer

let statement_rule* = non_terminal_rule("statement", @[
  new_production(@[assignment_rule.exact_one]),
  new_production(@[macro_call_rule.exact_one]),
], statement_reducer)
