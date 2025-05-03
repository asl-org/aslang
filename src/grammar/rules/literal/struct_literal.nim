import sequtils

import "../base"

proc struct_keyword_arg_transform(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  let kwarg = new_kwarg(parts[0][0][0].identifier, parts[0][2][
      0].argument, location)
  new_keyword_arg_parse_result(kwarg)

proc leading_struct_keyword_arg_transform(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  parts[0][0][0]

proc struct_literal_transform(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  let kwargs = (parts[0][2] & parts[0][3]).map(proc(
      s: ParseResult): KeywordArgument = s.kwarg)
  new_struct_literal(kwargs, location).new_struct_literal_parse_result()

let struct_literal_rules* = @[
  # keyword_argument ::= identifier colon_separated argument
  non_terminal_rule("keyword_argument", @[
      "identifier colon_separated argument"],
      struct_keyword_arg_transform),
  # leading_keyword_argument ::= keyword_argument comma_separated
  non_terminal_rule("leading_keyword_argument", @[
      "keyword_argument comma_separated"],
      leading_struct_keyword_arg_transform),
  # struct_literal ::= open_curly space* leading_keyword_argument* keyword_argument space* close_curly
  non_terminal_rule("struct_literal", @[
      "open_curly space* leading_keyword_argument* keyword_argument space* close_curly"],
      struct_literal_transform),
]
