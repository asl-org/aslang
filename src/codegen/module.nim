import sequtils, strformat, strutils

import analyzer
import func_def
import module_ref
import function

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
