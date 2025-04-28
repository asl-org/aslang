
import strutils

import parser
import transformer

proc is_visible(x: char): bool = x.ord in 32..<127
proc is_not_double_quote(x: char): bool = x.is_visible and x != '"'

let rules* =
  @[
  # new_line ::= "\n"
  static_terminal_rule("new_line", "\n", raw_terminal),
  # space ::= " "
  static_terminal_rule("space", " ", raw_terminal),
  # equal ::= "="
  static_terminal_rule("equal", "=", raw_terminal),
  # colon ::= ":"
  static_terminal_rule("colon", ":", raw_terminal),
  # comma ::= ","
  static_terminal_rule("comma", ",", raw_terminal),
  # period ::= "."
  static_terminal_rule("period", ".", raw_terminal),
  # underscore ::= "_"
  static_terminal_rule("underscore", "_", raw_terminal),
  # hashtag ::= "_"
  static_terminal_rule("hashtag", "#", raw_terminal),
  # single_quote ::= "'"
  static_terminal_rule("single_quote", "'", raw_terminal),
  # double_quote ::= "\""
  static_terminal_rule("double_quote", "\"", raw_terminal),
  # backslash ::= "\\"
  static_terminal_rule("backslash", "\\", raw_terminal),
  # open_curly ::= "{"
  static_terminal_rule("open_curly", "{", raw_terminal),
  # close_curly ::= "}"
  static_terminal_rule("close_curly", "}", raw_terminal),
  # open_square ::= "["
  static_terminal_rule("open_square", "[", raw_terminal),
  # close_square ::= "]"
  static_terminal_rule("close_square", "]", raw_terminal),
  # open_paren ::= "("
  static_terminal_rule("open_paren", "(", raw_terminal),
  # close_paren ::= ")"
  static_terminal_rule("close_paren", ")", raw_terminal),
  # except_new_line ::= [^\n]
  dynamic_terminal_rule("except_new_line", is_visible, raw_terminal),
  # except_double_quote ::= [^"]
  dynamic_terminal_rule("except_double_quote", is_not_double_quote,
      raw_terminal),
  # digit ::= [0-9]
  dynamic_terminal_rule("digit", is_digit, raw_terminal),
  # lowercase_alphabet ::= [a-z]
  dynamic_terminal_rule("lowercase_alphabet", is_lower_ascii,
      raw_terminal),
  # uppercase_alphabet ::= [A-Z]
  dynamic_terminal_rule("uppercase_alphabet", is_upper_ascii,
      raw_terminal),
  # alphabet ::= lowercase_alphabet | uppercase_alphabet
  non_terminal_rule("alphabet", @["lowercase_alphabet", "uppercase_alphabet"],
      raw_non_terminal),
  # word ::= alphabet+
  non_terminal_rule("word", @["alphabet+"], raw_non_terminal),
  # comment ::= space* hashtag except_new_line+ new_line?
  non_terminal_rule("comment", @["space* hashtag except_new_line+ new_line?"],
      raw_non_terminal),
  # empty_space ::= space* new_line | space+
  non_terminal_rule("empty_space", @["space* new_line", "space+"],
      raw_non_terminal),
  # escaped_double_quote ::= backslash double_quote
  non_terminal_rule("escaped_double_quote", @["backslash double_quote"],
      raw_non_terminal),
  # string_content ::= except_double_quote | escaped_double_quote
  non_terminal_rule("string_content", @["except_double_quote",
      "escaped_double_quote"], raw_non_terminal),
  # string ::= double_quote string_content* double_quote
  non_terminal_rule("string", @["double_quote string_content* double_quote"],
      raw_non_terminal),
  # integer ::= digit+
  non_terminal_rule("integer", @["digit+"], raw_non_terminal),
  # float ::= integer period integer
  non_terminal_rule("float", @["integer period integer"],
      raw_non_terminal),
  # native_literal ::= number | identifier (order matters here)
  non_terminal_rule("native_literal", @["float", "integer", "string"],
      native_literal),
  # identifier_head ::= word | underscore
  non_terminal_rule("identifier_head", @["word", "underscore"],
      raw_non_terminal),
  # identifier_tail ::= word | underscore | integer
  non_terminal_rule("identifier_tail", @["word", "underscore", "integer"],
      raw_non_terminal),
  # identifier ::= identifier_head identifier_tail*
  non_terminal_rule("identifier", @["identifier_head identifier_tail*"],
      identifier),
  # native_argument ::= native_literal | identifier
  non_terminal_rule("native_argument", @["native_literal", "identifier"],
      native_argument),
 # kwarg ::= identifier space* colon space* native_argument comma
  non_terminal_rule("kwarg", @["identifier space* colon space* native_argument comma space*"],
      struct_kwarg),
  # last_kwarg ::= identifier space* colon space* native_argument
  non_terminal_rule("last_kwarg", @["identifier space* colon space* native_argument"],
      struct_kwarg),
  # TODO: Struct Literal do not support nesting due to readability constraints.
  # struct_literal ::= open_curly space* kwarg* last_kwarg space* close_curly
  non_terminal_rule("struct_literal", @[
      "open_curly space* kwarg* last_kwarg space* close_curly"],
      struct_literal),
  # literal ::= native_literal | struct_literal
  non_terminal_rule("literal", @["native_literal", "struct_literal"], literal),
  # initializer ::= identifier space* equal space* identifier space* struct_literal empty_space
  non_terminal_rule("initializer", @["identifier space* equal space* identifier space* literal empty_space"],
      initializer),
  # call_argument ::= native_argument space* comma space*
  non_terminal_rule("call_argument", @["native_argument space* comma space*"],
      call_argument),
  # call_argument_list ::= open_paren space* call_argument* identifier space* close_paren
  non_terminal_rule("call_argument_list", @[
      "open_paren space* call_argument* native_argument space* close_paren"],
      call_argument_list),
  # function_call ::= identifier space* equal space* identifier period identifier space* call_argument_list empty_space
  non_terminal_rule("function_call", @[
      "identifier space* equal space* identifier period identifier space* call_argument_list empty_space"],
      function_call),
  # statement ::= initializer | function_call | comment
  non_terminal_rule("statement", @["space* initializer",
      "space* function_call"], statement),
  # line ::= statement | comment | empty_space
  non_terminal_rule("line", @["statement", "comment", "empty_space"],
      line),
  # program ::= statement+
  non_terminal_rule("program", @["line+"], program),
]
