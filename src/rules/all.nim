import strutils

import "../parser"
import reducer

# character.nim
let space_rule* = static_rule("space", "' '", " ", raw_string_reducer)
let newline_rule* = static_rule("newline", "'\\n'", "\n", raw_string_reducer)

let minus_rule* = static_rule("minus", "'-'", "-", raw_string_reducer)

let underscore_rule* = static_rule("underscore", "'_'", "_", raw_string_reducer)
let equal_rule* = static_rule("equal", "'='", "=", raw_string_reducer)
let period_rule* = static_rule("period", "'.'", ".", raw_string_reducer)
let comma_rule* = static_rule("comma", "','", ",", raw_string_reducer)
let colon_rule* = static_rule("colon", "':'", ":", raw_string_reducer)
let hashtag_rule* = static_rule("hashtag", "'#'", "#", raw_string_reducer)
let paren_open_rule* = static_rule("paren_open", "'('", "(", raw_string_reducer)
let paren_close_rule* = static_rule("paren_close", "')'", ")",
    raw_string_reducer)
let brace_open_rule* = static_rule("brace_open", "'{'", "{", raw_string_reducer)
let brace_close_rule* = static_rule("brace_close", "'}'", "}", raw_string_reducer)

proc is_visible(x: char): bool = 32 <= x.ord and x.ord < 127
let visible_character_rule* = matcher_rule("visible_character",
    "ascii 32..<127", is_visible, raw_string_reducer)

let is_eof = proc(x: char): bool = x.ord == 0
let eof_rule* = matcher_rule("eof", "'EOF'",
    is_eof, raw_string_reducer)

let digit_rule* = matcher_rule("digit", "[0-9]", isDigit, raw_string_reducer)
let lowercase_alphabet_rule* = matcher_rule("lowercase_alphabet", "[a-z]",
    isLowerAscii, raw_string_reducer)
let uppercase_alphabet_rule* = matcher_rule("uppercase_alphabet", "[A-Z]",
    isUpperAscii, raw_string_reducer)

# keyword.nim
let fn_keyword_rule* = static_rule("fn_keyword", "'fn'", "fn",
    raw_string_reducer)
let returns_keyword_rule* = static_rule("returns_keyword", "'returns'",
    "returns", raw_string_reducer)
let args_keyword_rule* = static_rule("args_keyword", "'args'", "args",
    raw_string_reducer)
let app_keyword_rule* = static_rule("app_keyword", "'app'", "app",
    raw_string_reducer)
let module_keyword_rule* = static_rule("module_keyword", "'module'", "module",
    raw_string_reducer)
let struct_keyword_rule* = static_rule("struct_keyword", "'struct'", "struct",
    raw_string_reducer)
let union_keyword_rule* = static_rule("union_keyword", "'union'", "union",
    raw_string_reducer)
let match_keyword_rule* = static_rule("match_keyword", "'match'", "match",
    raw_string_reducer)
let case_keyword_rule* = static_rule("case_keyword", "'case'", "case",
    raw_string_reducer)
let else_keyword_rule* = static_rule("else_keyword", "'else'", "else",
    raw_string_reducer)

# identifier.nim
let alphabet_rule* = non_terminal_rule("alphabet", @[
  new_production(@[lowercase_alphabet_rule.exact_one]),
  new_production(@[uppercase_alphabet_rule.exact_one])
], raw_parts_reducer)

let identifier_head_rule* = non_terminal_rule("identifier_head", @[
  new_production(@[underscore_rule.exact_one]),
  new_production(@[alphabet_rule.exact_one])
], raw_parts_reducer)

let identifier_tail_rule* = non_terminal_rule("identifier_tail", @[
  new_production(@[identifier_head_rule.exact_one]),
  new_production(@[digit_rule.exact_one])
], raw_parts_reducer)

let identifier_rule* = non_terminal_rule("identifier", @[
  new_production(@[identifier_head_rule.exact_one(), identifier_tail_rule.any()])
], identifier_reducer)

# number.nim
let integer_rule* = non_terminal_rule("integer", @[
  new_production(@[minus_rule.at_most_one, digit_rule.at_least_one])
], raw_parts_reducer)

# keyword_arg.nim

let keyword_arg_def_rule* = non_terminal_rule("keyword_arg_def", @[
  new_production(@[
    identifier_rule.exact_one,
    space_rule.any,
    colon_rule.exact_one,
    space_rule.any,
    identifier_rule.exact_one,
  ])
], keyword_arg_def_reducer)

let leading_keyword_arg_def_rule* = non_terminal_rule("leading_keyword_arg_def", @[
  new_production(@[
    keyword_arg_def_rule.exact_one,
    space_rule.any,
    comma_rule.exact_one,
    space_rule.any,
  ])
], leading_keyword_arg_def_reducer)

let struct_def_rule* = non_terminal_rule("struct_def", @[
  new_production(@[
    brace_open_rule.exact_one,
    space_rule.any,
    leading_keyword_arg_def_rule.any,
    keyword_arg_def_rule.exact_one,
    space_rule.any,
    brace_close_rule.exact_one,
  ])
], struct_def_reducer)

let union_def_rule* = non_terminal_rule("union_def", @[
  new_production(@[
    identifier_rule.exact_one,
    space_rule.any,
    struct_def_rule.exact_one,
  ])
], union_def_reducer)

let keyword_arg_value_rule* = non_terminal_rule("keyword_arg_value", @[
  new_production(@[integer_rule.exact_one]),
  new_production(@[identifier_rule.exact_one])
], keyword_arg_value_reducer)

let keyword_arg_rule* = non_terminal_rule("keyword_arg", @[
  new_production(@[
    identifier_rule.exact_one,
    space_rule.any,
    colon_rule.exact_one,
    space_rule.any,
    keyword_arg_value_rule.exact_one,
  ])
], keyword_arg_reducer)

let leading_keyword_arg_rule* = non_terminal_rule("leading_keyword_arg", @[
  new_production(@[
    keyword_arg_rule.exact_one,
    space_rule.any,
    comma_rule.exact_one,
    space_rule.any,
  ])
], leading_keyword_arg_reducer)

# struct.nim
let struct_rule* = non_terminal_rule("struct", @[
  new_production(@[
    brace_open_rule.exact_one,
    space_rule.any,
    leading_keyword_arg_rule.any,
    keyword_arg_rule.exact_one,
    space_rule.any,
    brace_close_rule.exact_one,
  ])
], struct_reducer)

# literal.nim
let literal_rule* = non_terminal_rule("literal", @[
  new_production(@[integer_rule.exact_one]),
  new_production(@[struct_rule.exact_one])
], literal_reducer)

let leading_module_ref_rule* = non_terminal_rule("leading_module_ref", @[
  new_production(@[
    identifier_rule.exact_one,
    period_rule.exact_one,
  ]),
], leading_module_ref_reducer)

let module_ref_rule* = non_terminal_rule("module_ref", @[
  new_production(@[
    leading_module_ref_rule.any,
    identifier_rule.exact_one,
  ]),
], module_ref_reducer)

# init.nim
# TODO: replace identifier with module_ref in backward compatible manner
let init_rule* = non_terminal_rule("init", @[
  new_production(@[
    module_ref_rule.exact_one,
    space_rule.any,
    literal_rule.exact_one
  ])
], init_reducer)

let arg_rule* = non_terminal_rule("arg", @[
  new_production(@[identifier_rule.exact_one, period_rule.exact_one,
      identifier_rule.exact_one]),
  new_production(@[identifier_rule.exact_one]),
  new_production(@[literal_rule.exact_one]),
], arg_reducer)

# arglist.nim
let leading_arg_rule* = non_terminal_rule("leading_arg", @[
  new_production(@[
    arg_rule.exact_one,
    space_rule.any,
    comma_rule.exact_one,
    space_rule.any
  ])
], leading_arg_reducer)

let arglist_rule* = non_terminal_rule("arglist", @[
  new_production(@[
    paren_open_rule.exact_one,
    space_rule.any,
    leading_arg_rule.any,
    arg_rule.exact_one,
    space_rule.any,
    paren_close_rule.exact_one
  ])
], arglist_reducer)

# fncall.nim
let fncall_rule* = non_terminal_rule("fncall", @[
  new_production(@[
    identifier_rule.exact_one,
    period_rule.exact_one,
    identifier_rule.exact_one,
    arglist_rule.exact_one,
  ])
], fncall_reducer)

# value.nim
let expr_rule* = non_terminal_rule("expr_value", @[
  new_production(@[init_rule.exact_one]),
  new_production(@[fncall_rule.exact_one]),
  new_production(@[identifier_rule.exact_one]),
], value_reducer)

# assignment.nim
let assignment_rule* = non_terminal_rule("assignment", @[
  new_production(@[
    identifier_rule.exact_one,
    space_rule.any,
    equal_rule.exact_one,
    space_rule.any,
    expr_rule.exact_one,
  ])
], assignment_reducer)

# statement.nim
let statement_rule* = non_terminal_rule("statement", @[
  new_production(@[assignment_rule.exact_one]),
  new_production(@[expr_rule.exact_one]),
], statement_reducer)

# arg_def.nim
let arg_def_rule* = non_terminal_rule("arg_def", @[
  new_production(@[
    identifier_rule.exact_one,
    space_rule.any,
    identifier_rule.exact_one,
  ]),
], arg_def_reducer)

let leading_arg_def_rule* = non_terminal_rule("leading_arg_def", @[
  new_production(@[
    arg_def_rule.exact_one,
    space_rule.any,
    comma_rule.exact_one,
    space_rule.any,
  ]),
], leading_arg_def_reducer)

let arg_def_list_rule* = non_terminal_rule("arg_def_list", @[
  new_production(@[
    paren_open_rule.exact_one,
    space_rule.any,
    leading_arg_def_rule.any,
    arg_def_rule.exact_one,
    space_rule.any,
    paren_close_rule.exact_one,
  ])
], arg_def_list_reducer)

# fn_def.nim
let fn_def_rule* = non_terminal_rule("fn_def", @[
  new_production(@[
    fn_keyword_rule.exact_one,
    space_rule.any,
    identifier_rule.exact_one,
    space_rule.any,
    arg_def_list_rule.exact_one,
    space_rule.any,
    returns_keyword_rule.exact_one,
    space_rule.any,
    identifier_rule.exact_one,
    space_rule.any,
    colon_rule.exact_one,
  ])
], fn_def_reducer)

# app_def.nim
let app_def_rule* = non_terminal_rule("app_def", @[
  new_production(@[
    app_keyword_rule.exact_one,
    space_rule.any,
    identifier_rule.exact_one,
    space_rule.any,
    colon_rule.exact_one,
  ])
], app_def_reducer)

# module_def.nim
let module_def_rule* = non_terminal_rule("module_def", @[
  new_production(@[
    module_keyword_rule.exact_one,
    space_rule.any,
    identifier_rule.exact_one,
    space_rule.any,
    colon_rule.exact_one,
  ])
], module_def_reducer)

# match_def.nim
let match_def_rule* = non_terminal_rule("match_def", @[
  new_production(@[
    match_keyword_rule.exact_one,
    space_rule.any,
    identifier_rule.exact_one,
    space_rule.any,
    colon_rule.exact_one,
  ])
], match_def_reducer)

# case_def.nim
let case_pattern_rule* = non_terminal_rule("case_pattern", @[
  new_production(@[integer_rule.exact_one]),
  new_production(@[
    module_ref_rule.exact_one,
    space_rule.any,
    struct_def_rule.exact_one,
  ])
], case_pattern_reducer)

let case_def_rule* = non_terminal_rule("case_def", @[
  new_production(@[
    case_keyword_rule.exact_one,
    space_rule.any,
    case_pattern_rule.exact_one,
    space_rule.any,
    colon_rule.exact_one,
  ])
], case_def_reducer)

let else_def_rule* = non_terminal_rule("else_def", @[
  new_production(@[
    else_keyword_rule.exact_one,
    space_rule.any,
    colon_rule.exact_one,
  ])
], else_def_reducer)

# struct.nim
let struct_macro_rule* = non_terminal_rule("struct_macro", @[
  new_production(@[
    struct_keyword_rule.exact_one,
    space_rule.any,
    colon_rule.exact_one,
    space_rule.any,
  ])
], struct_macro_reducer)

# union.nim
let union_macro_rule* = non_terminal_rule("union_macro", @[
  new_production(@[
    union_keyword_rule.exact_one,
    space_rule.any,
    colon_rule.exact_one,
    space_rule.any,
  ])
], union_macro_reducer)

# macro_call.nim
let macro_call_rule* = non_terminal_rule("macro_call", @[
  new_production(@[fn_def_rule.exact_one]),
  new_production(@[app_def_rule.exact_one]),
  new_production(@[module_def_rule.exact_one]),
  new_production(@[match_def_rule.exact_one]),
  new_production(@[case_def_rule.exact_one]),
  new_production(@[else_def_rule.exact_one]),
  new_production(@[struct_macro_rule.exact_one]),
  new_production(@[union_macro_rule.exact_one]),
], macro_call_reducer)

# comment.nim
let comment_rule* = non_terminal_rule("comment", @[
  new_production(@[
    hashtag_rule.exact_one,
    visible_character_rule.at_least_one,
  ])
], comment_reducer)

# line.nim
let line_rule* = non_terminal_rule("line", @[
  new_production(@[space_rule.any, macro_call_rule.exact_one, space_rule.any]),
  new_production(@[space_rule.any, arg_def_rule.exact_one, space_rule.any]),
  new_production(@[space_rule.any, statement_rule.exact_one, space_rule.any]),
  new_production(@[space_rule.any, union_def_rule.exact_one, space_rule.any]),
  new_production(@[space_rule.any, comment_rule.exact_one, space_rule.any]),
  new_production(@[space_rule.any]),
], line_reducer)

let leading_line_rule* = non_terminal_rule("leading_line", @[
  new_production(@[line_rule.exact_one, newline_rule.exact_one]),
], leading_line_reducer)

# program.nim
let program_rule* = non_terminal_rule("program", @[
  new_production(@[
    leading_line_rule.any,
    line_rule.exact_one,
    newline_rule.at_most_one,
    eof_rule.exact_one,
  ])
], program_reducer)
