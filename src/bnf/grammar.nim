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
  # colon ::= ":"
  static_terminal_rule("colon", ":"),
  # comma ::= ","
  static_terminal_rule("comma", ","),
  # period ::= "."
  static_terminal_rule("period", "."),
  # single_quote ::= "'"
  static_terminal_rule("single_quote", "'"),
  # double_quote ::= "\""
  static_terminal_rule("double_quote", "\""),
  # backslash ::= "\\"
  static_terminal_rule("backslash", "\\"),
  # open_curly ::= "{"
  static_terminal_rule("open_curly", "{"),
  # close_curly ::= "}"
  static_terminal_rule("close_curly", "}"),
  # open_square ::= "["
  static_terminal_rule("open_square", "["),
  # close_square ::= "]"
  static_terminal_rule("close_square", "]"),
  # open_paren ::= "("
  static_terminal_rule("open_paren", "("),
  # close_paren ::= ")"
  static_terminal_rule("close_paren", ")"),
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
  # identifier_head ::= word | underscore
  non_terminal_rule("identifier_head", @["word", "underscore"]),
  # identifier_tail ::= word | underscore | integer
  non_terminal_rule("identifier_tail", @["word", "underscore", "integer"]),
  # identifier ::= identifier_head identifier_tail*
  non_terminal_rule("identifier", @["identifier_head identifier_tail*"]),
  # module_head ::= identifier period
  non_terminal_rule("module_head", @["identifier period"]),
  # module_tail ::= identifier
  non_terminal_rule("module_tail", @["identifier"]),
  # module ::= module_head* module_tail
  non_terminal_rule("identifier", @["module_head* module_tail"]),
  # statement ::= identifier space* equal space* integer space* new_line?
  non_terminal_rule("statement", @["identifier space* equal space* integer space* new_line?"]),
  # program ::= statement+
  non_terminal_rule("program", @["statement+"]),
])

let content = @[
  "x = 1",
  "dsdf=2",
  "dkhjk    =2",
  "erb=   2  ",
  "dsxvc    =   2   \n",
].join("\n")

when isMainModule:
  let maybe_match = grammar.match(content)
  if maybe_match.isErr: echo maybe_match.error
  else: echo maybe_match.get
