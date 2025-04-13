import results, strutils

import parser

let grammar = new_grammar(
  "program",
  @[
  # new_line ::= "\n"
  static_terminal_rule("new_line", "\n"),
  # space ::= " "
  static_terminal_rule("space", " "),
  # equal ::= "="
  static_terminal_rule("equal", "="),
  # digit ::= [0-9]
  dynamic_terminal_rule("digit", isDigit),
  # lowercase_alphabet ::= [a-z]
  dynamic_terminal_rule("lowercase_alphabet", isLowerAscii),
  # uppercase_alphabet ::= [A-Z]
  dynamic_terminal_rule("uppercase_alphabet", isUpperAscii),
  # alphabet ::= lowercase_alphabet | uppercase_alphabet
  non_terminal_rule("alphabet", @["lowercase_alphabet", "uppercase_alphabet"]),
  # word ::= alphabet+
  non_terminal_rule("word", @["alphabet+"]),
  # integer ::= digit+
  non_terminal_rule("integer", @["digit+"]),
  # identifier_head ::= underscore | word
  non_terminal_rule("identifier_head", @["word", "underscore"]),
  # identifier_tail ::= underscore | word | integer
  non_terminal_rule("identifier_tail", @["word", "underscore", "integer"]),
  # identifier ::= identifier_head identifier_tail*
  non_terminal_rule("identifier", @["identifier_head identifier_tail*"]),
  # module_head ::= identifier period
  non_terminal_rule("module_head", @["identifier period"]),
  # module_tail ::= identifier
  non_terminal_rule("module_tail", @["identifier"]),
  # module ::= module_head* module_tail
  non_terminal_rule("identifier", @["module_head* module_tail"]),
  # empty_line ::= space* new_line
  non_terminal_rule("empty_line", @["space* new_line"]),
  # statement ::= identifier space* equal space* integer empty_line+
  non_terminal_rule("statement", @["identifier space* equal space* integer empty_line+"]),
  # last_statement ::= identifier space* equal space* integer space*
  non_terminal_rule("last_statement", @[
      "identifier space* equal space* integer space*"]),
  # program ::= statement* last_statement
  non_terminal_rule("program", @["statement* last_statement"]),
])

let content = @[
  "x = 1",
  "dsdf=2",
  "dkhjk    =2",
  "erb=   2",
  "dsxvc    =   2",
].join("\n")

when isMainModule:
  let maybe_match = grammar.match(content)
  if maybe_match.isErr: echo maybe_match.error
  echo maybe_match.get
