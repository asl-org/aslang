import strutils

import "../location"
export location

import "../parser"
export parser

import "../parse_result"
export parse_result

import "../struct"
export struct

proc raw_value*(parts: seq[seq[seq[ParseResult]]]): string =
  var value: string
  for prod in parts:
    for symbol in prod:
      for item in symbol:
        value.add($(item))
  return value

proc raw_value_transform*(value: string, location: Location): ParseResult =
  new_raw_value_parse_result(value, location)

proc raw_parts_transform*(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  parts.raw_value.raw_value_transform(location)

proc is_visible*(x: char): bool = x.ord in 32..<127

let base_rules* = @[
  # visible_character ::= [^\n]
  dynamic_terminal_rule("visible_character", is_visible,
      raw_value_transform),
  # lowercase_alphabet ::= [a-z]
  dynamic_terminal_rule("lowercase_alphabet", is_lower_ascii,
      raw_value_transform),
  # uppercase_alphabet ::= [A-Z]
  dynamic_terminal_rule("uppercase_alphabet", is_upper_ascii,
      raw_value_transform),
  # alphabet ::= lowercase_alphabet | uppercase_alphabet
  non_terminal_rule("alphabet", @["lowercase_alphabet", "uppercase_alphabet"],
      raw_parts_transform),
  # word ::= alphabet+
  non_terminal_rule("word", @["alphabet+"], raw_parts_transform),
  # comment ::= space* hashtag visible_character+ new_line?
  non_terminal_rule("comment", @["hashtag visible_character+"],
      raw_parts_transform),
  # empty_space ::= space* new_line | space+
  non_terminal_rule("empty_space", @["space* new_line", "space+"],
      raw_parts_transform),
  # colon_separated ::= space* colon space*
  non_terminal_rule("colon_separated", @["space* colon space*"],
      raw_parts_transform),
  # comma_separated ::= space* comma space*
  non_terminal_rule("comma_separated", @["space* comma space*"],
      raw_parts_transform),
  # equal_separated ::= space* equal space*
  non_terminal_rule("equal_separated", @["space* equal space*"],
      raw_parts_transform),
]
