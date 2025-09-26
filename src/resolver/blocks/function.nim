import strformat, sequtils, sets, strutils, tables

import arg
import function_ref
import function_step

type
  ResolvedFunctionDefinitionKind = enum
    RFDK_LOCAL, RFDK_MODULE
  ResolvedFunctionDefinition* = ref object of RootObj
    name: Token
    arg_defs*: seq[ResolvedArgumentDefinition]
    return_type*: Module
    case kind: ResolvedFunctionDefinitionKind
    of RFDK_LOCAL: discard
    of RFDK_MODULE: module: UserModule

proc new_resolved_function_definition*(name: Token, arg_defs: seq[
    ResolvedArgumentDefinition],
    return_type: Module): ResolvedFunctionDefinition =
  ResolvedFunctionDefinition(kind: RFDK_LOCAL, name: name, arg_defs: arg_defs,
      return_type: return_type)

proc new_resolved_function_definition*(module: UserModule, name: Token,
    arg_defs: seq[ResolvedArgumentDefinition],
    return_type: Module): ResolvedFunctionDefinition =
  ResolvedFunctionDefinition(kind: RFDK_MODULE, module: module, name: name,
      arg_defs: arg_defs, return_type: return_type)

proc c*(func_def: ResolvedFunctionDefinition): string =
  let name =
    case func_def.kind:
    of RFDK_LOCAL: $(func_def.name)
    of RFDK_MODULE: fmt"{func_def.module.name}_{func_def.name}"

  let args = func_def.arg_defs.map_it($(it.c)).join(", ")
  let return_type =
    case func_def.return_type.kind:
    of MK_USER: "Pointer"
    of MK_BUILTIN: $(func_def.return_type.name)

  fmt"{return_type} {name}({args})"

type ResolvedFunction* = ref object of RootObj
  func_def*: ResolvedFunctionDefinition
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

proc h*(function: ResolvedFunction): string =
  fmt"{function.func_def.c};"

proc c*(function: ResolvedFunction): string =
  let signature = fmt"{function.func_def.c}"

  var body = function.steps.map_it(it.c)
  let return_arg_name = function.steps[^1].return_argument.name
  body.add(fmt"return {return_arg_name};")

  @[signature, "{", body.join("\n"), "}"].join("\n")

proc new_resolved_function*(func_def: ResolvedFunctionDefinition, steps: seq[
    ResolvedFunctionStep]): ResolvedFunction =
  ResolvedFunction(func_def: func_def, steps: steps)
