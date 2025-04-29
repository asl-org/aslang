import sequtils

import "../parser"
import "../transformer"

import "../location"
import "../common/keyword_argument"
import "../common/literal"
import "../common/struct"

proc struct_keyword_arg_transform(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  let kwarg = new_kwarg(parts[0][0][0].identifier, parts[0][2][
      0].native_argument, location)
  new_keyword_arg_parse_result(kwarg)

proc leading_struct_keyword_arg_transform(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  parts[0][0][0]

proc struct_literal_transform(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  let kwargs = (parts[0][2] & parts[0][3]).map(proc(
      s: ParseResult): KeywordArgument = s.kwarg)
  new_struct(kwargs, location).new_struct_literal_parse_result()

proc literal_transform(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  var literal: Literal
  if parts[0].len > 0:
    literal = new_native_literal(parts[0][0][0].native_literal, location)
  elif parts[1].len > 0:
    literal = new_struct_literal(parts[1][0][0].struct_literal, location)
  new_literal_parse_result(literal)

let literal_rules* = @[
  # keyword_argument ::= identifier colon_separated native_argument
  non_terminal_rule("keyword_argument", @[
      "identifier colon_separated native_argument"],
      struct_keyword_arg_transform),
  # leading_keyword_arg ::= keyword_argument comma_separated
  non_terminal_rule("leading_keyword_arg", @[
      "keyword_argument comma_separated"],
      leading_struct_keyword_arg_transform),
  # struct_literal ::= open_curly space* leading_keyword_arg* keyword_argument space* close_curly
  non_terminal_rule("struct_literal", @[
      "open_curly space* leading_keyword_arg* keyword_argument space* close_curly"],
      struct_literal_transform),
  # literal ::= native_literal | struct_literal
  non_terminal_rule("literal", @["native_literal", "struct_literal"],
      literal_transform),
]
