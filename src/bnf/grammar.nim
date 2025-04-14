import os, results, strutils, strformat

import parser

proc is_visible(x: char): bool = x.ord in 32..<127
proc is_not_double_quote(x: char): bool = x.is_visible and x != '"'

let rules =
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
  # underscore ::= "_"
  static_terminal_rule("underscore", "_"),
  # hashtag ::= "_"
  static_terminal_rule("hashtag", "#"),
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
  # except_new_line ::= [^\n]
  dynamic_terminal_rule("except_new_line", is_visible),
  # except_double_quote ::= [^"]
  dynamic_terminal_rule("except_double_quote", is_not_double_quote),
  # digit ::= [0-9]
  dynamic_terminal_rule("digit", is_digit),
  # lowercase_alphabet ::= [a-z]
  dynamic_terminal_rule("lowercase_alphabet", is_lower_ascii),
  # uppercase_alphabet ::= [A-Z]
  dynamic_terminal_rule("uppercase_alphabet", is_upper_ascii),
  # alphabet ::= lowercase_alphabet | uppercase_alphabet
  non_terminal_rule("alphabet", @["lowercase_alphabet", "uppercase_alphabet"]),
  # word ::= alphabet+
  non_terminal_rule("word", @["alphabet+"]),
  # integer ::= digit+
  non_terminal_rule("integer", @["digit+"]),
  # float ::= integer period integer
  non_terminal_rule("float", @["integer period integer"]),
  # number ::= float | integer
  non_terminal_rule("number", @["float", "integer"]),
  # empty_space ::= space* new_line | space+
  non_terminal_rule("empty_space", @["space* new_line", "space+"]),
  # comment ::= space* hashtag except_new_line+ new_line?
  non_terminal_rule("comment", @["space* hashtag except_new_line+ new_line?"]),
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
  non_terminal_rule("module", @["module_head* module_tail"]),
  # escaped_double_quote ::= backslash double_quote
  non_terminal_rule("escaped_double_quote", @["backslash double_quote"]),
  # string_content ::= except_double_quote | escaped_double_quote
  non_terminal_rule("string_content", @["except_double_quote",
      "escaped_double_quote"]),
  # string ::= double_quote string_content* double_quote
  non_terminal_rule("string", @["double_quote string_content* double_quote"]),
  # field_value ::= number | identifier (order matters here)
  non_terminal_rule("field_value", @["number", "identifier"]),
  # field ::= identifier space* colon space* integer comma
  non_terminal_rule("field", @["identifier space* colon space* field_value comma space*"]),
  # last_field ::= identifier space* colon space* integer
  non_terminal_rule("last_field", @["identifier space* colon space* field_value"]),
  # struct ::= open_curly space* field* last_field space* close_curly
  non_terminal_rule("struct", @["open_curly space* field* last_field space* close_curly"]),
  # initializer ::= identifier space* equal space* module space* struct empty_space
  non_terminal_rule("initializer", @["identifier space* equal space* module space* struct empty_space"]),
  # argument ::= identifier space* comma space*
  non_terminal_rule("argument", @["identifier space* comma space*"]),
  # call_arguments ::= open_paren space* argument* identifier space* close_paren
  non_terminal_rule("call_arguments", @[
      "open_paren space* argument* identifier space* close_paren"]),
  # function_call ::= identifier space* equal space* module space* call_arguments empty_space
  non_terminal_rule("function_call", @[
      "identifier space* equal space* module space* call_arguments empty_space"]),
  # move_op ::= identifier space* equal space* identifier empty_space
  non_terminal_rule("move_op", @["identifier space* equal space* identifier empty_space"]),
  # statement ::= initializer | function_call | move_op | comment
  non_terminal_rule("statement", @["initializer", "function_call", "move_op"]),
  # line ::= statement | comment | empty_space
  non_terminal_rule("line", @["statement", "comment", "empty_space"]),
  # program ::= statement+
  non_terminal_rule("program", @["line+"]),
]

proc `$`(struct: Struct): string =
  fmt"{struct.location} {struct.kind}"

when is_main_module:
  let maybe_parsed = "example.asl".absolute_path.parse("program", rules)
  if maybe_parsed.isErr: echo maybe_parsed.error
  else: echo $(maybe_parsed.get)
