import results

import parser

import rules/reducer; export reducer
import rules/all

proc asl_grammar*(): Result[Grammar[Location, ParseResult], string] =
  new_grammar[Location, ParseResult](@[
    space,
    newline,
    underscore,
    equal,
    comma,
    colon,
    hashtag,
    period,
    paren_open,
    paren_close,
    visible_character,
    digit,
    lowercase_alphabet,
    uppercase_alphabet,
    alphabet_rule,
    identifier_head_rule,
    identifier_tail_rule,
    identifier_rule,
    integer,
    init_rule,
    leading_arg_rule,
    arglist_rule,
    fncall_rule,
    value_rule,
    assignment_rule,
    fn_keyword,
    returns_keyword,
    fn_macro_rule,
    args_keyword,
    arg_def_rule,
    leading_arg_def_rule,
    arg_def_list_rule,
    args_macro_rule,
    app_keyword,
    app_macro_rule,
    macro_call_rule,
    statement_rule,
    comment_rule,
    line_rule,
    leading_line_rule,
    program_rule,
  ])
