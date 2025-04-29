import "../parser"
import "../transformer"

import "../location"
import "../common/initializer"

proc initializer_transform(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  let dest = parts[0][0][0].identifier
  let module = parts[0][2][0].identifier
  let literal = parts[0][4][0].literal
  new_initializer(dest, module, literal, location).new_initializer_parse_result()

var initializer_rules* = @[
  # initializer ::= identifier equal_separated identifier space* literal empty_space
  non_terminal_rule("initializer", @["identifier equal_separated identifier space* literal empty_space"],
      initializer_transform),
]
