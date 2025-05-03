import base

import statement/initializer
import statement/function_call

proc statement_transform(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  var statement: Statement
  if parts[0].len > 0:
    statement = new_init_statement(parts[0][0][0].init, location)
  elif parts[1].len > 0:
    statement = new_fncall_statement(parts[1][
        0][0].fncall, location)

  new_statement_parse_result(statement)

var statement_rules*: seq[Rule[ParseResult]]
statement_rules.add(initializer_rules)
statement_rules.add(function_call_rules)
statement_rules.add(@[
  # statement ::= initializer | function_call
  non_terminal_rule("statement", @["initializer", "function_call"],
      statement_transform),
])
