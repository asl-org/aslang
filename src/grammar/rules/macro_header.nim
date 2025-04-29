import sequtils

import "../parser"
import "../transformer"

import "../location"
import "../common/macro_header"
import "../common/identifier"

proc fn_macro_transform(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  let name = parts[0][1][0].identifier
  let returns = parts[0][3][0].identifier
  new_fn_macro(name, returns, location).new_fn_macro_parse_result()

proc args_macro_argument_transform(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  let module = parts[0][0][0].identifier
  let name = parts[0][2][0].identifier
  new_args_def(name, module, location).new_arg_def_parse_result()

proc args_macro_argument_list_transform(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  var leading_arg_defs = parts[0][2].map(proc(
      x: ParseResult): ArgumentDef = x.arg_def)
  let module = parts[0][3][0].identifier
  let name = parts[0][5][0].identifier
  leading_arg_defs.add(new_args_def(name, module, module.location))
  new_args_def_list(leading_arg_defs, location).new_arg_def_list_parse_result()

proc args_macro_transform(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  parts[0][2][0]

proc macro_header_transform(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  echo parts
  if parts[0].len > 0:
    return new_fn_macro_header(parts[0][0][
        0].fn_macro).new_macro_header_parse_result()
  elif parts[1].len > 0:
    return new_args_macro_header(parts[1][0][
        0].arg_defs).new_macro_header_parse_result()

var macro_header_rules* = @[
  # fn_macro_header ::= fn_macro identifier ret_macro identifier colon
  non_terminal_rule("fn_macro_header", @[
      "fn_macro identifier ret_macro identifier colon"], fn_macro_transform),
  # args_macro_argument ::= native_argument comma_separated
  non_terminal_rule("args_macro_argument", @[
      "identifier space* identifier comma_separated"],
      args_macro_argument_transform),
  # args_macro_argumentlist ::= open_paren space* args_macro_argument* identifier space* identifier space* close_paren
  non_terminal_rule("args_macro_argumentlist", @[
      "open_paren space* args_macro_argument* identifier space* identifier space* close_paren"],
      args_macro_argument_list_transform),
  # args_macro ::= args space* args_macro_argumentlist space* colon
  non_terminal_rule("args_macro", @[
      "args_macro space* args_macro_argumentlist space* colon"],
      args_macro_transform),
  # macro ::= fn_macro_header | args_macro
  non_terminal_rule("macro", @["fn_macro_header", "args_macro"],
      macro_header_transform),
]
