import results, sequtils, strformat, tables, strutils, sets, options

import resolver
import module_ref
import arg_def
import func_def
import module_def
import file_def
import func_ref
import arg

type AnalyzedFunctionCall* = ref object of RootObj
  fnref: AnalyzedFunctionRef
  concrete_def: AnalyzedFunctionDefinition
  original_def: AnalyzedFunctionDefinition
  args: seq[AnalyzedArgument]

proc new_analyzed_function_call(fnref: AnalyzedFunctionRef,
    original_def: AnalyzedFunctionDefinition,
        concrete_def: AnalyzedFunctionDefinition,
    args: seq[AnalyzedArgument]): AnalyzedFunctionCall =
  AnalyzedFunctionCall(fnref: fnref, original_def: original_def,
      concrete_def: concrete_def, args: args)

proc fnref*(fncall: AnalyzedFunctionCall): AnalyzedFunctionRef = fncall.fnref
proc concrete_def*(fncall: AnalyzedFunctionCall): AnalyzedFunctionDefinition = fncall.concrete_def
proc original_def*(fncall: AnalyzedFunctionCall): AnalyzedFunctionDefinition = fncall.original_def
proc args*(fncall: AnalyzedFunctionCall): seq[AnalyzedArgument] = fncall.args

proc location*(fncall: AnalyzedFunctionCall): Location =
  fncall.fnref.location

proc returns*(fncall: AnalyzedFunctionCall): AnalyzedModuleRef =
  fncall.concrete_def.returns

proc generic_impls*(fncall: AnalyzedFunctionCall): Table[ResolvedModule, seq[
    HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedModule, seq[HashSet[AnalyzedImpl]]]
  impl_set = impl_set.merge(fncall.fnref.generic_impls)
  impl_set = impl_set.merge(fncall.concrete_def.generic_impls)
  for arg in fncall.args: impl_set = impl_set.merge(arg.generic_impls)
  return impl_set

proc asl*(fncall: AnalyzedFunctionCall): string =
  let args_str = fncall.args.map_it(it.asl).join(", ")
  fncall.fnref.asl & "(" & args_str & ")"

proc analyze*(file_def: AnalyzedFileDefinition, scope: FunctionScope,
    fncall: ResolvedFunctionCall,
    module_def: Option[AnalyzedModuleDefinition] = none[AnalyzedModuleDefinition]()): Result[AnalyzedFunctionCall, string] =
  let analyzed_function_ref = ? analyze(file_def, fncall.fnref, module_def)
  var error_message = @[fmt"{fncall.location} failed to find matching function call:"]
  for (original_def, concrete_def) in analyzed_function_ref.defs:
    let maybe_analyzed_args = analyze(file_def, scope, fncall.args,
        concrete_def.args)
    if maybe_analyzed_args.is_ok:
      return ok(new_analyzed_function_call(analyzed_function_ref, original_def,
          concrete_def, maybe_analyzed_args.get))
    else:
      error_message.add(maybe_analyzed_args.error)
      error_message.add(concrete_def.asl)
  err(error_message.join("\n"))
