import strformat, sequtils, sets, strutils, tables

import "../blocks"
import arg
import function_ref
import function_step

type ResolvedFunctionDefinition* = ref object of RootObj
  name: Token
  arg_defs: seq[ResolvedArgumentDefinition]
  return_type*: Module

proc new_resolved_function_definition*(name: Token, arg_defs: seq[
    ResolvedArgumentDefinition],
    return_type: Module): ResolvedFunctionDefinition =
  ResolvedFunctionDefinition(name: name, arg_defs: arg_defs,
      return_type: return_type)

type ResolvedFunction* = ref object of RootObj
  func_ref*: ResolvedFunctionRef
  function*: Function
  steps*: seq[ResolvedFunctionStep]

proc function_refs*(function: ResolvedFunction): Hashset[ResolvedFunctionRef] =
  var function_ref_set: Hashset[ResolvedFunctionRef]
  for step in function.steps:
    function_ref_set.incl(step.function_refs)
  function_ref_set

proc generic_impls*(function: ResolvedFunction): Table[string, Table[string,
    HashSet[string]]] =
  var impls: Table[string, Table[string, HashSet[string]]]
  for step in function.steps:
    for (module_name, impl_map) in step.generic_impls.pairs:
      if module_name notin impls:
        impls[module_name] = init_table[string, HashSet[string]]()
      for (generic, concrete) in impl_map.pairs:
        if generic notin impls[module_name]:
          impls[module_name][generic] = init_hashset[string]()
        impls[module_name][generic].incl(concrete)
  return impls

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
    steps: seq[ResolvedFunctionStep]): ResolvedFunction =
  ResolvedFunction(func_ref: func_ref, function: function, steps: steps)
