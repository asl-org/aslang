import results, strformat, tables, sets, options

import resolver
import module_ref
import arg_def
import func_def
import generic
import module_def
import file_def
import function

type AnalyzedModule* = ref object of RootObj
  def: AnalyzedModuleDefinition
  functions: seq[AnalyzedFunction]

proc new_analyzed_module(def: AnalyzedModuleDefinition, functions: seq[
    AnalyzedFunction]): AnalyzedModule =
  AnalyzedModule(def: def, functions: functions)

proc def*(module: AnalyzedModule): AnalyzedModuleDefinition = module.def
proc functions*(module: AnalyzedModule): seq[AnalyzedFunction] = module.functions

proc generic_impls*(module: AnalyzedModule): Table[ResolvedModule, seq[
    HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedModule, seq[HashSet[AnalyzedImpl]]]
  impl_set = impl_set.merge(module.def.generic_impls)
  for function in module.functions: impl_set = impl_set.merge(
      function.generic_impls)
  return impl_set

proc asl*(module: AnalyzedModule, indent: string): seq[string] =
  var lines = @[fmt"module {module.def.name.asl}:"]
  for line in module.def.asl(indent):
    lines.add(indent & line)
  lines.add("\n")
  for function in module.functions:
    for line in function.asl(indent):
      lines.add(indent & line)
    lines.add("\n")
  return lines

proc analyze*(file_def: AnalyzedFileDefinition,
    module_def: AnalyzedModuleDefinition): Result[AnalyzedModule, string] =
  var analyzed_functions: seq[AnalyzedFunction]
  for function in module_def.resolved_module.functions:
    let analyzed_function =
      case function.kind:
      of RFK_USER:
        let analyzed_user_function = ? analyze(file_def, function.user, some(module_def))
        new_analyzed_function(analyzed_user_function)
      of RFK_EXTERN:
        let analyzed_function_def = ? module_def.find_function_def(
            function.extern.def)
        new_analyzed_function(analyzed_function_def,
            function.extern)
    analyzed_functions.add(analyzed_function)

  ok(new_analyzed_module(module_def, analyzed_functions))
