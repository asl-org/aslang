import strutils

import "../parser"
import reducer

# character.nim
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
let brace_open* = static_rule("brace_open", "'{'", "{", raw_string_reducer)
let brace_close* = static_rule("brace_close", "'}'", "}", raw_string_reducer)

proc is_visible(x: char): bool = 32 <= x.ord and x.ord < 127
let visible_character* = matcher_rule("visible_character", "ascii 32..<127",
    is_visible, raw_string_reducer)

let is_eof = proc(x: char): bool = x.ord == 0
let eof_rule* = matcher_rule("eof", "'EOF'",
    is_eof, raw_string_reducer)

let digit* = matcher_rule("digit", "[0-9]", isDigit, raw_string_reducer)
let lowercase_alphabet* = matcher_rule("lowercase_alphabet", "[a-z]",
    isLowerAscii, raw_string_reducer)
let uppercase_alphabet* = matcher_rule("uppercase_alphabet", "[A-Z]",
    isUpperAscii, raw_string_reducer)

# keyword.nim
let fn_keyword* = static_rule("fn_keyword", "'fn'", "fn",
    raw_string_reducer)
let returns_keyword* = static_rule("returns_keyword", "'returns'", "returns",
    raw_string_reducer)
let args_keyword* = static_rule("args_keyword", "'args'", "args",
    raw_string_reducer)
let app_keyword* = static_rule("app_keyword", "'app'", "app",
    raw_string_reducer)
let module_keyword* = static_rule("module_keyword", "'module'", "module",
    raw_string_reducer)
let struct_keyword* = static_rule("struct_keyword", "'struct'", "struct",
    raw_string_reducer)
let union_keyword* = static_rule("union_keyword", "'union'", "union",
    raw_string_reducer)
let match_keyword* = static_rule("match_keyword", "'match'", "match",
    raw_string_reducer)
let case_keyword* = static_rule("case_keyword", "'case'", "case",
    raw_string_reducer)
let else_keyword* = static_rule("else_keyword", "'else'", "else",
    raw_string_reducer)

# identifier.nim
let alphabet_rule* = non_terminal_rule("alphabet", @[
  new_production(@[lowercase_alphabet.exact_one]),
  new_production(@[uppercase_alphabet.exact_one])
], raw_parts_reducer)

let identifier_head_rule* = non_terminal_rule("identifier_head", @[
  new_production(@[underscore.exact_one]),
  new_production(@[alphabet_rule.exact_one])
], raw_parts_reducer)

let identifier_tail_rule* = non_terminal_rule("identifier_tail", @[
  new_production(@[identifier_head_rule.exact_one]),
  new_production(@[digit.exact_one])
], raw_parts_reducer)

let identifier_rule* = non_terminal_rule("identifier", @[
  new_production(@[identifier_head_rule.exact_one(), identifier_tail_rule.any()])
], identifier_reducer)

# number.nim
let integer* = non_terminal_rule("integer", @[
  new_production(@[digit.at_least_one])
], raw_parts_reducer)

# keyword_arg.nim
let keyword_arg_rule* = non_terminal_rule("keyword_arg", @[
  new_production(@[
    identifier_rule.exact_one,
    space.any,
    colon.exact_one,
    space.any,
    integer.exact_one,
  ])
], keyword_arg_reducer)

let leading_keyword_arg_rule* = non_terminal_rule("leading_keyword_arg", @[
  new_production(@[
    keyword_arg_rule.exact_one,
    space.any,
    comma.exact_one,
    space.any,
  ])
], leading_keyword_arg_reducer)

# struct.nim
let struct_rule* = non_terminal_rule("struct", @[
  new_production(@[
    brace_open.exact_one,
    space.any,
    leading_keyword_arg_rule.any,
    keyword_arg_rule.exact_one,
    space.any,
    brace_close.exact_one,
  ])
], struct_reducer)

# literal.nim
let literal_rule* = non_terminal_rule("literal", @[
  new_production(@[integer.exact_one]),
  new_production(@[struct_rule.exact_one])
], literal_reducer)

# init.nim
let init_rule* = non_terminal_rule("init", @[
  new_production(@[
    identifier_rule.exact_one,
    space.any,
    literal_rule.exact_one
  ])
], init_reducer)

let arg_rule* = non_terminal_rule("arg", @[
  new_production(@[identifier_rule.exact_one]),
  new_production(@[literal_rule.exact_one]),
], arg_reducer)

# arglist.nim
let leading_arg_rule* = non_terminal_rule("leading_arg", @[
  new_production(@[
    arg_rule.exact_one,
    space.any,
    comma.exact_one,
    space.any
  ])
], leading_arg_reducer)

let arglist_rule* = non_terminal_rule("arglist", @[
  new_production(@[
    paren_open.exact_one,
    space.any,
    leading_arg_rule.any,
    arg_rule.exact_one,
    space.any,
    paren_close.exact_one
  ])
], arglist_reducer)

# fncall.nim
let fncall_rule* = non_terminal_rule("fncall", @[
  new_production(@[
    identifier_rule.exact_one,
    period.exact_one,
    identifier_rule.exact_one,
    arglist_rule.exact_one,
  ])
], fncall_reducer)

# value.nim
let value_rule* = non_terminal_rule("value", @[
  new_production(@[init_rule.exact_one]),
  new_production(@[fncall_rule.exact_one])
], value_reducer)

# assignment.nim
let assignment_rule* = non_terminal_rule("assignment", @[
  new_production(@[
    identifier_rule.exact_one,
    space.any,
    equal.exact_one,
    space.any,
    value_rule.exact_one,
  ])
], assignment_reducer)

# arg_def.nim
let arg_def_rule* = non_terminal_rule("arg_def", @[
  new_production(@[
    identifier_rule.exact_one,
    space.any,
    identifier_rule.exact_one,
  ]),
], arg_def_reducer)

let leading_arg_def_rule* = non_terminal_rule("leading_arg_def", @[
  new_production(@[
    arg_def_rule.exact_one,
    space.any,
    comma.exact_one,
    space.any,
  ]),
], leading_arg_def_reducer)

let arg_def_list_rule* = non_terminal_rule("arg_def_list", @[
  new_production(@[
    paren_open.exact_one,
    space.any,
    leading_arg_def_rule.any,
    arg_def_rule.exact_one,
    space.any,
    paren_close.exact_one,
  ])
], arg_def_list_reducer)

# fn_def.nim
let fn_def_rule* = non_terminal_rule("fn_def", @[
  new_production(@[
    fn_keyword.exact_one,
    space.any,
    identifier_rule.exact_one,
    space.any,
    arg_def_list_rule.exact_one,
    space.any,
    returns_keyword.exact_one,
    space.any,
    identifier_rule.exact_one,
    space.any,
    colon.exact_one,
  ])
], fn_def_reducer)

# app_def.nim
let app_def_rule* = non_terminal_rule("app_def", @[
  new_production(@[
    app_keyword.exact_one,
    space.any,
    identifier_rule.exact_one,
    space.any,
    colon.exact_one,
  ])
], app_def_reducer)

# module_def.nim
let module_def_rule* = non_terminal_rule("module_def", @[
  new_production(@[
    module_keyword.exact_one,
    space.any,
    identifier_rule.exact_one,
    space.any,
    colon.exact_one,
  ])
], module_def_reducer)

# struct_def.nim
let struct_def_rule* = non_terminal_rule("struct_def", @[
  new_production(@[
    struct_keyword.exact_one,
    space.any,
    identifier_rule.exact_one,
    space.any,
    colon.exact_one,
  ])
], struct_def_reducer)

# union_def.nim
let union_def_rule* = non_terminal_rule("union_def", @[
  new_production(@[
    union_keyword.exact_one,
    space.any,
    identifier_rule.exact_one,
    space.any,
    colon.exact_one,
  ])
], union_def_reducer)

# match_def.nim
let match_def_rule* = non_terminal_rule("match_def", @[
  new_production(@[
    match_keyword.exact_one,
    space.any,
    identifier_rule.exact_one,
    space.any,
    colon.exact_one,
  ])
], match_def_reducer)

# case_def.nim
let case_def_rule* = non_terminal_rule("case_def", @[
  new_production(@[
    case_keyword.exact_one,
    space.any,
    integer.exact_one,
    space.any,
    colon.exact_one,
  ])
], case_def_reducer)

let else_def_rule* = non_terminal_rule("else_def", @[
  new_production(@[
    else_keyword.exact_one,
    space.any,
    colon.exact_one,
  ])
], else_def_reducer)

# macro_call.nim
let macro_call_rule* = non_terminal_rule("macro_call", @[
  new_production(@[fn_def_rule.exact_one]),
  new_production(@[app_def_rule.exact_one]),
  new_production(@[module_def_rule.exact_one]),
  new_production(@[struct_def_rule.exact_one]),
  new_production(@[union_def_rule.exact_one]),
  new_production(@[match_def_rule.exact_one]),
  new_production(@[case_def_rule.exact_one]),
  new_production(@[else_def_rule.exact_one]),
], macro_call_reducer)

# statement.nim
let statement_rule* = non_terminal_rule("statement", @[
  new_production(@[assignment_rule.exact_one]),
  new_production(@[fncall_rule.exact_one]),
  new_production(@[identifier_rule.exact_one]),
], statement_reducer)

# comment.nim
let comment_rule* = non_terminal_rule("comment", @[
  new_production(@[
    hashtag.exact_one,
    visible_character.at_least_one,
  ])
], comment_reducer)

# line.nim
let line_rule* = non_terminal_rule("line", @[
  new_production(@[space.any, macro_call_rule.exact_one, space.any]),
  new_production(@[space.any, statement_rule.exact_one, space.any]),
  new_production(@[space.any, comment_rule.exact_one, space.any]),
  new_production(@[space.any]),
], line_reducer)

let leading_line_rule* = non_terminal_rule("leading_line", @[
  new_production(@[line_rule.exact_one, newline.exact_one]),
], leading_line_reducer)

# program.nim
let program_rule* = non_terminal_rule("program", @[
  new_production(@[
    leading_line_rule.any,
    line_rule.exact_one,
    newline.at_most_one,
    eof_rule.exact_one,
  ])
], program_reducer)
