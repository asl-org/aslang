import results, sequtils, strformat, tables, strutils, sets, options

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

proc c*(module: AnalyzedModule, generic_impls: seq[seq[(
    AnalyzedModuleDefinition, seq[AnalyzedFunctionDefinition])]]): seq[string] =
  var lines: seq[string]
  for gen_index, (generic, impls) in zip(module.def.generics, generic_impls):
    for def_index, def in generic.defs:
      lines.add(def.h.replace(";", ""))
      lines.add("{")
      lines.add(fmt"switch(__asl_impl_id_{gen_index})")
      lines.add("{")

      for (impl_module, impl_functions) in impls:
        lines.add(fmt"case {impl_module.id}:")
        lines.add("{")
        let impl_fn = impl_functions[def_index]
        var new_args: seq[string]
        for arg_index, (def_arg, impl_arg) in zip(def.args, impl_fn.args):
          case def_arg.module_ref.kind:
          of AMRK_GENERIC:
            case impl_arg.module_ref.kind:
            of AMRK_GENERIC: new_args.add(def_arg.name.asl)
            else:
              let arg_name = fmt"__asl_arg_{arg_index}"
              lines.add(fmt"{impl_arg.module_ref.c} {arg_name} = {impl_arg.module_ref.c}_read({def_arg.name.asl}, 0);")
              new_args.add(arg_name)
          else:
            new_args.add(def_arg.name.asl)

        let args_str = new_args.join(", ")
        lines.add(fmt"{impl_fn.returns.c} __asl_result = {impl_fn.c_name}({args_str});")

        case def.returns.kind:
        of AMRK_GENERIC:
          lines.add(fmt"return System_box_{impl_fn.returns.c}(__asl_result);")
        else:
          lines.add("return __asl_result;")

        lines.add("}")
      lines.add("}")
      lines.add("UNREACHABLE();")
      lines.add("}")

  for function in module.functions:
    lines.add(function.c)
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
