import strformat, sequtils, strutils, hashes

import ../analyzer
import func_def
import module_ref
import arg

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
          let impl_arg = fmt"__asl_impl_id_{child.location.hash.to_hex}"
          lines.add(fmt"U64 {impl_arg} = {child.module.id};")
          new_args.add(impl_arg)

      for index in 0..<fncall.args.len:
        let original_def = fncall.original_def.args[index]
        let concrete_def = fncall.concrete_def.args[index]
        let fn_arg = fncall.args[index]

        case original_def.module_ref.kind:
        of AMRK_GENERIC:
          case concrete_def.module_ref.kind:
          of AMRK_GENERIC: new_args.add(fn_arg.asl)
          else:
            let arg_name = fmt"__asl_arg_{fn_arg.location.hash.to_hex}"
            lines.add(fmt"Pointer {arg_name} = System_box_{concrete_def.module_ref.c}({fn_arg.c});")
            new_args.add(arg_name)
        else: new_args.add(fn_arg.asl)

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
