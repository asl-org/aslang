import "../parser"

import character
import statement
import reducer

let comment_rule* = non_terminal_rule("comment", @[
  new_production(@[
    hashtag.exact_one,
    visible_character.at_least_one,
  ])
], comment_reducer)

let line_rule* = non_terminal_rule("line", @[
  new_production(@[space.any, statement_rule.exact_one, space.any]),
  new_production(@[space.any, comment_rule.exact_one, space.any]),
  new_production(@[space.any]),
], line_reducer)

let leading_line_rule* = non_terminal_rule("leading_line", @[
  new_production(@[line_rule.exact_one, newline.exact_one]),
], leading_line_reducer)

let program_rule* = non_terminal_rule("program", @[
  new_production(@[
    leading_line_rule.any,
    line_rule.exact_one,
    newline.at_most_one
  ])
], program_reducer)
