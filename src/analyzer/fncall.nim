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

proc location(fncall: AnalyzedFunctionCall): Location =
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

proc c*(fncall: AnalyzedFunctionCall, result_arg: string): seq[string] =
  var lines: seq[string]
  case fncall.fnref.kind:
  of RFRK_LOCAL:
    let args = fncall.args.map_it(it.c).join(", ")
    lines.add(fmt"{fncall.original_def.returns.c} {result_arg} = {fncall.original_def.c_name}({args});")
  of RFRK_MODULE:
    let module_ref = fncall.fnref.module_ref
    case module_ref.kind:
    of AMRK_GENERIC:
      let args = fncall.args.map_it(it.c).join(", ")
      let impl_id = fmt"__asl_impl_id_{module_ref.generic.id}"
      lines.add(fmt"{fncall.original_def.returns.c} {result_arg} = {fncall.original_def.c_name}({impl_id}, {args});")
    of AMRK_MODULE:
      var new_args: seq[string]
      for impl in module_ref.impls:
        let child = impl.module_ref
        case child.kind:
        of AMRK_GENERIC:
          new_args.add(fmt"__asl_impl_id_{child.generic.id}")
        of AMRK_MODULE:
          let arg = fmt"__asl_impl_id_{child.location.hash.to_hex}"
          lines.add(fmt"U64 {arg} = {child.module.id};")
          new_args.add(arg)

      for index in 0..<fncall.args.len:
        let original_def = fncall.original_def.args[index]
        let concrete_def = fncall.concrete_def.args[index]
        let arg = fncall.args[index]

        case original_def.module_ref.kind:
        of AMRK_GENERIC:
          case concrete_def.module_ref.kind:
          of AMRK_GENERIC: new_args.add(arg.asl)
          else:
            let arg_name = fmt"__asl_arg_{arg.location.hash.to_hex}"
            lines.add(fmt"Pointer {arg_name} = System_box_{concrete_def.module_ref.c}({arg.c});")
            new_args.add(arg_name)
        else: new_args.add(arg.asl)

      let args_str = new_args.join(", ")
      case fncall.original_def.returns.kind:
      of AMRK_GENERIC:
        case fncall.concrete_def.returns.kind:
        of AMRK_GENERIC:
          lines.add(fmt"{fncall.original_def.returns.c} {result_arg} = {fncall.original_def.c_name}({args_str});")
        else:
          let arg_name = fmt"__asl_arg_{fncall.location.hash.to_hex}"
          lines.add(fmt"{fncall.original_def.returns.c} {arg_name} = {fncall.original_def.c_name}({args_str});")
          lines.add(fmt"{fncall.concrete_def.returns.c} {result_arg} = {fncall.concrete_def.returns.c}_read({arg_name}, 0);")
      else:
        lines.add(fmt"{fncall.original_def.returns.c} {result_arg} = {fncall.original_def.c_name}({args_str});")

  return lines

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
