import strutils

import "../parser"
import reducer/parse_result

proc raw_transform(location: Location, value: string): (Location,
    ParseResult) =
  var updated = location
  for x in value:
    if x == '\n':
      updated.line += 1
      updated.col = 1
    else:
      updated.col += 1
  (updated, to_parse_result(value))

# static rules
let space* = static_rule("space", "' '", " ", raw_transform)
let newline* = static_rule("newline", "'\\n'", "\n", raw_transform)

let underscore* = static_rule("underscore", "'_'", "_", raw_transform)
let equal* = static_rule("equal", "'='", "=", raw_transform)
let period* = static_rule("period", "'.'", ".", raw_transform)
let comma* = static_rule("comma", "','", ",", raw_transform)
let colon* = static_rule("colon", "':'", ":", raw_transform)
let hashtag* = static_rule("hashtag", "'#'", "#", raw_transform)
let paren_open* = static_rule("paren_open", "'('", "(", raw_transform)
let paren_close* = static_rule("paren_close", "')'", ")", raw_transform)

# keywords/macros
let fn_keyword* = static_rule("fn_keyword", "'function'", "function", raw_transform)
let returns_keyword* = static_rule("returns_keyword", "'returns'", "returns", raw_transform)
let args_keyword* = static_rule("args_keyword", "'args'", "args", raw_transform)
let app_keyword* = static_rule("app_keyword", "'app'", "app", raw_transform)

# dynamic rules
proc is_visible(x: char): bool = 32 <= x.ord and x.ord < 127
let visible_character* = matcher_rule("visible_character", "ascii 32..<127",
    is_visible, raw_transform)
let digit* = matcher_rule("digit", "[0-9]", isDigit, raw_transform)
let lowercase_alphabet* = matcher_rule("lowercase_alphabet", "[a-z]",
    isLowerAscii, raw_transform)
let uppercase_alphabet* = matcher_rule("uppercase_alphabet", "[A-Z]",
    isUpperAscii, raw_transform)

proc raw_non_terminal_transform(location: Location, parts: seq[seq[seq[
    ParseResult]]]): (Location, ParseResult) =
  var value: string
  for prod in parts:
    for sym in prod:
      for item in sym:
        value.add($(item))
  (location, to_parse_result(value))

# non terminal rule
let alphabet* = non_terminal_rule("alphabet", @[
  new_production(@[lowercase_alphabet.exact_one]),
  new_production(@[uppercase_alphabet.exact_one])
], raw_non_terminal_transform)

let identifier_head* = non_terminal_rule("identifier_head", @[
  new_production(@[underscore.exact_one]),
  new_production(@[alphabet.exact_one])
], raw_non_terminal_transform)

let identifier_tail* = non_terminal_rule("identifier_tail", @[
  new_production(@[identifier_head.exact_one]),
  new_production(@[digit.exact_one])
], raw_non_terminal_transform)

let identifier* = non_terminal_rule("identifier", @[
  new_production(@[identifier_head.exact_one(), identifier_tail.any()])
], raw_non_terminal_transform)

let integer* = non_terminal_rule("integer", @[
  new_production(@[digit.at_least_one])
], raw_non_terminal_transform)
