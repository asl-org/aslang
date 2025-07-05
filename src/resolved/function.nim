import results, strformat, sequtils, sets, strutils, options

import "../blocks"
import function_call
import function_step

type ResolvedFunction* = ref object of RootObj
  module: Option[Module]
  function: Function
  steps: seq[ResolvedFunctionStep]

proc function_set*(function: ResolvedFunction): Hashset[ExternalFunction] =
  var function_set: Hashset[ExternalFunction]
  for step in function.steps:
    function_set.incl(step.function_set)
  function_set

proc h*(resolved_function: ResolvedFunction): string =
  let prefix =
    if resolved_function.module.is_some:
      fmt"{resolved_function.module.get.name}_"
    else:
      ""

  let function = resolved_function.function
  let args_def_str = function.definition.arg_def_list.map_it(it.c).join(", ")
  fmt"{function.native_return_type} {prefix}{function.name}({args_def_str});"

proc c*(resolved_function: ResolvedFunction): string =
  let prefix =
    if resolved_function.module.is_some:
      fmt"{resolved_function.module.get.name}_"
    else:
      ""

  let function = resolved_function.function
  let args_def_str = function.definition.arg_def_list.map_it(it.c).join(", ")
  let signature = fmt"{function.native_return_type} {prefix}{function.name}({args_def_str})"

  var body = resolved_function.steps.map_it(it.c)
  let return_arg_name = resolved_function.steps[^1].return_argument.arg_name
  body.add(fmt"return {return_arg_name};")

  @[signature, "{", body.join("\n"), "}"].join("\n")

proc new_resolved_function*(module: Option[Module], function: Function,
    steps: seq[ResolvedFunctionStep]): Result[ResolvedFunction, string] =
  let actual_return_type = steps[^1].return_argument.arg_type
  if $(function.return_type) != $(actual_return_type):
    return err(fmt"{function.location} expected {function.name} to return {function.return_type} but found {actual_return_type}")
  ok(ResolvedFunction(module: module, function: function, steps: steps))
