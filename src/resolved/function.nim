import results, strformat, sequtils, sets, strutils

import "../blocks"
import function_call
import function_step

type ResolvedFunction* = ref object of RootObj
  func_ref*: ResolvedFunctionRef
  function*: Function
  steps*: seq[ResolvedFunctionStep]

proc function_refs*(function: ResolvedFunction): Hashset[ResolvedFunctionRef] =
  var function_ref_set: Hashset[ResolvedFunctionRef]
  for step in function.steps:
    function_ref_set.incl(step.function_refs)
  function_ref_set

proc h*(resolved_function: ResolvedFunction): string =
  let function = resolved_function.function
  let args_def_str = function.definition.arg_def_list.map_it(it.c).join(", ")
  fmt"{function.native_return_type} {resolved_function.func_ref.name}({args_def_str});"

proc c*(resolved_function: ResolvedFunction): string =
  let function = resolved_function.function
  let args_def_str = function.definition.arg_def_list.map_it(it.c).join(", ")
  let signature = fmt"{function.native_return_type} {resolved_function.func_ref.name}({args_def_str})"

  var body = resolved_function.steps.map_it(it.c)
  let return_arg_name = resolved_function.steps[^1].return_argument.name
  body.add(fmt"return {return_arg_name};")

  @[signature, "{", body.join("\n"), "}"].join("\n")

proc new_resolved_function*(func_ref: ResolvedFunctionRef, function: Function,
    steps: seq[ResolvedFunctionStep]): Result[ResolvedFunction, string] =
  let actual_return_type = steps[^1].return_argument.typ
  if $(function.return_type) != $(actual_return_type):
    return err(fmt"{function.location} expected {function.name} to return {function.return_type} but found {actual_return_type}")
  ok(ResolvedFunction(func_ref: func_ref, function: function, steps: steps))
