import strformat, sequtils, strutils

import ../analyzer
import ../ir/constructors
import ../emitter/emit
import gen_func_def
import gen_module_ref
import gen_arg

proc generate_fncall*(fncall: AnalyzedFunctionCall,
    result_arg: string): seq[CStmt] =
  var stmts: seq[CStmt]
  case fncall.fnref.kind:
  of RFRK_LOCAL:
    let args = fncall.args.map_it(c_ident(it.generate_arg))
    stmts.add(c_decl_var(fncall.original_def.returns.generate_type,
        result_arg,
        c_call(fncall.original_def.generate_func_name, args)))
  of RFRK_MODULE:
    let module_ref = fncall.fnref.module_ref
    case module_ref.kind:
    of AMRK_GENERIC:
      let args = fncall.args.map_it(c_ident(it.generate_arg))
      let impl_id = fmt"__asl_impl_id_{module_ref.generic.id}"
      let all_args = @[c_ident(impl_id)] & args
      stmts.add(c_decl_var(fncall.original_def.returns.generate_type,
          result_arg,
          c_call(fncall.original_def.generate_func_name, all_args)))
    of AMRK_MODULE:
      var new_args: seq[CExpr]
      for impl in module_ref.impls:
        let child = impl.module_ref
        case child.kind:
        of AMRK_GENERIC:
          new_args.add(c_ident(fmt"__asl_impl_id_{child.generic.id}"))
        of AMRK_MODULE:
          let impl_arg = fmt"__asl_impl_id_{child.location.hash.to_hex}"
          stmts.add(c_decl_var(c_named("U64"), impl_arg,
              c_lit($child.module.id)))
          new_args.add(c_ident(impl_arg))

      for index in 0..<fncall.args.len:
        let original_def = fncall.original_def.args[index]
        let concrete_def = fncall.concrete_def.args[index]
        let fn_arg = fncall.args[index]

        case original_def.module_ref.kind:
        of AMRK_GENERIC:
          case concrete_def.module_ref.kind:
          of AMRK_GENERIC: new_args.add(c_ident(fn_arg.asl))
          else:
            let arg_name = fmt"__asl_arg_{fn_arg.location.hash.to_hex}"
            stmts.add(c_decl_var(c_pointer(), arg_name,
                c_call(fmt"System_box_{concrete_def.module_ref.generate_type.emit}",
                @[c_ident(fn_arg.generate_arg)])))
            new_args.add(c_ident(arg_name))
        else: new_args.add(c_ident(fn_arg.asl))

      case fncall.original_def.returns.kind:
      of AMRK_GENERIC:
        case fncall.concrete_def.returns.kind:
        of AMRK_GENERIC:
          stmts.add(c_decl_var(fncall.original_def.returns.generate_type,
              result_arg,
              c_call(fncall.original_def.generate_func_name, new_args)))
        else:
          let arg_name = fmt"__asl_arg_{fncall.location.hash.to_hex}"
          stmts.add(c_decl_var(fncall.original_def.returns.generate_type,
              arg_name,
              c_call(fncall.original_def.generate_func_name, new_args)))
          stmts.add(c_decl_var(fncall.concrete_def.returns.generate_type,
              result_arg,
              c_call(fmt"{fncall.concrete_def.returns.generate_type.emit}_read",
              @[c_ident(arg_name), c_lit("0")])))
      else:
        stmts.add(c_decl_var(fncall.original_def.returns.generate_type,
            result_arg,
            c_call(fncall.original_def.generate_func_name, new_args)))

  return stmts
