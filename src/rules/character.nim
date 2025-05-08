import strutils

from "../parser" import matcher_rule, static_rule
from reducer import raw_string_reducer

let space* = static_rule("space", "' '", " ", raw_string_reducer)
let newline* = static_rule("newline", "'\\n'", "\n", raw_string_reducer)

let underscore* = static_rule("underscore", "'_'", "_", raw_string_reducer)
let equal* = static_rule("equal", "'='", "=", raw_string_reducer)
let period* = static_rule("period", "'.'", ".", raw_string_reducer)
let comma* = static_rule("comma", "','", ",", raw_string_reducer)
let colon* = static_rule("colon", "':'", ":", raw_string_reducer)
let hashtag* = static_rule("hashtag", "'#'", "#", raw_string_reducer)
let paren_open* = static_rule("paren_open", "'('", "(", raw_string_reducer)
let paren_close* = static_rule("paren_close", "')'", ")", raw_string_reducer)

proc is_visible(x: char): bool = 32 <= x.ord and x.ord < 127
let visible_character* = matcher_rule("visible_character", "ascii 32..<127",
    is_visible, raw_string_reducer)
let digit* = matcher_rule("digit", "[0-9]", isDigit, raw_string_reducer)
let lowercase_alphabet* = matcher_rule("lowercase_alphabet", "[a-z]",
    isLowerAscii, raw_string_reducer)
let uppercase_alphabet* = matcher_rule("uppercase_alphabet", "[A-Z]",
    isUpperAscii, raw_string_reducer)
