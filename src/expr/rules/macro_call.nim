import "../parser"

import base
import reducer

let fn_macro_rule* = non_terminal_rule("fn_macro", @[
  new_production(@[
    fn_keyword.exact_one,
    space.any,
    identifier.exact_one,
    space.any,
    returns_keyword.exact_one,
    space.any,
    identifier.exact_one,
    space.any,
    colon.exact_one,
  ])
], fn_macro_reducer)

let arg_def_rule* = non_terminal_rule("arg_def", @[
  new_production(@[
    identifier.exact_one,
    space.any,
    identifier.exact_one,
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

let args_macro_rule* = non_terminal_rule("args_macro", @[
  new_production(@[
    args_keyword.exact_one,
    space.any,
    arg_def_list_rule.exact_one,
    space.any,
    colon.exact_one,
  ])
], args_macro_reducer)

let macro_call_rule* = non_terminal_rule("macro_call", @[
  new_production(@[fn_macro_rule.exact_one]),
  new_production(@[args_macro_rule.exact_one])
], macro_call_reducer)
