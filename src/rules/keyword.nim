from "../parser" import static_rule, matcher_rule
from reducer import raw_string_reducer

let fn_keyword* = static_rule("fn_keyword", "'function'", "function",
    raw_string_reducer)
let returns_keyword* = static_rule("returns_keyword", "'returns'", "returns",
    raw_string_reducer)
let args_keyword* = static_rule("args_keyword", "'args'", "args",
    raw_string_reducer)
let app_keyword* = static_rule("app_keyword", "'app'", "app",
    raw_string_reducer)
