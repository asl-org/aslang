import sequtils

import "../parser"
import "../transformer"

import "../location"
import "../common/function_call"
import "../common/native_argument"
import "../common/argument_list"

proc leading_call_argument_transform(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult = parts[0][0][0]

proc call_argument_list_transform(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  let arguments = (parts[0][2] & parts[0][3]).map(proc(
      x: ParseResult): NativeArgument = x.native_argument)
  new_argument_list(arguments, location).new_arg_list_parse_result()

proc function_call_transform(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  let dest = parts[0][0][0].identifier
  let module = parts[0][2][0].identifier
  let name = parts[0][4][0].identifier
  let arglist = parts[0][6][0].arglist
  new_function_call(name, dest, module, arglist,
      location).new_function_call_parse_result()

var function_call_rules* = @[
  # call_argument ::= native_argument comma_separated
  non_terminal_rule("call_argument", @["native_argument comma_separated"],
      leading_call_argument_transform),
  # call_argument_list ::= open_paren space* call_argument* identifier space* close_paren
  non_terminal_rule("call_argument_list", @[
      "open_paren space* call_argument* native_argument space* close_paren"],
      call_argument_list_transform),
  # function_call ::= identifier equal_separated identifier period identifier space* call_argument_list empty_space
  non_terminal_rule("function_call", @[
      "identifier equal_separated identifier period identifier space* call_argument_list empty_space"],
      function_call_transform),
]
