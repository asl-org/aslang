import "../parser"
import "../transformer"

import "../location"
import "../common/statement"

proc statement_transform(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  var statement: Statement
  if parts[0].len > 0:
    statement = new_init_statement(parts[0][0].len, parts[0][1][0].init, location)
  elif parts[1].len > 0:
    statement = new_fncall_statement(parts[1][
        0].len, parts[1][1][0].fncall, location)

  new_statement_parse_result(statement)

var statement_rules* = @[
  # statement ::= space* initializer | space* function_call
  non_terminal_rule("statement", @["space* initializer",
      "space* function_call"], statement_transform),
]
