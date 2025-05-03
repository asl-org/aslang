import base

let symbol_rules* = @[
  # new_line ::= "\n"
  static_terminal_rule("new_line", "\n", raw_value_transform),
  # space ::= " "
  static_terminal_rule("space", " ", raw_value_transform),
  # equal ::= "="
  static_terminal_rule("equal", "=", raw_value_transform),
  # colon ::= ":"
  static_terminal_rule("colon", ":", raw_value_transform),
  # comma ::= ","
  static_terminal_rule("comma", ",", raw_value_transform),
  # period ::= "."
  static_terminal_rule("period", ".", raw_value_transform),
  # underscore ::= "_"
  static_terminal_rule("underscore", "_", raw_value_transform),
  # hashtag ::= "_"
  static_terminal_rule("hashtag", "#", raw_value_transform),
  # single_quote ::= "'"
  static_terminal_rule("single_quote", "'", raw_value_transform),
  # double_quote ::= "\""
  static_terminal_rule("double_quote", "\"", raw_value_transform),
  # backslash ::= "\\"
  static_terminal_rule("backslash", "\\", raw_value_transform),
  # open_curly ::= "{"
  static_terminal_rule("open_curly", "{", raw_value_transform),
  # close_curly ::= "}"
  static_terminal_rule("close_curly", "}", raw_value_transform),
  # open_square ::= "["
  static_terminal_rule("open_square", "[", raw_value_transform),
  # close_square ::= "]"
  static_terminal_rule("close_square", "]", raw_value_transform),
  # open_paren ::= "("
  static_terminal_rule("open_paren", "(", raw_value_transform),
  # close_paren ::= ")"
  static_terminal_rule("close_paren", ")", raw_value_transform),
  # fn_macro ::= "fn"
  static_terminal_rule("fn_keyword", "fn", raw_value_transform),
  # ret_macro ::= "returns"
  static_terminal_rule("ret_keyword", "returns", raw_value_transform),
  # args_macro ::= "args"
  static_terminal_rule("args_keyword", "args", raw_value_transform),
]
