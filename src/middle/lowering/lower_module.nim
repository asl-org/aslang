import sequtils, strformat

import ../analyzer
import ../../ir/constructors
import ../../backend/emitter
import lower_func_def
import lower_module_ref
import lower_function

proc generate_module*(module: AnalyzedModule, generic_impls: seq[seq[(
    AnalyzedModuleDefinition, seq[AnalyzedFunctionDefinition])]]): seq[CDecl] =
  var decls: seq[CDecl]
  for gen_index, (generic, impls) in zip(module.def.generics, generic_impls):
    for def_index, def in generic.defs:
      let func_decl = def.generate_func_decl
      var body: seq[CStmt]

      var switch_cases: seq[(CExpr, seq[CStmt])]
      for (impl_module, impl_functions) in impls:
        var case_body: seq[CStmt]
        let impl_fn = impl_functions[def_index]
        var new_args: seq[CExpr]
        for arg_index, (def_arg, impl_arg) in zip(def.args, impl_fn.args):
          case def_arg.module_ref.kind:
          of AMRK_GENERIC:
            case impl_arg.module_ref.kind:
            of AMRK_GENERIC: new_args.add(c_ident(def_arg.name.asl))
            else:
              let arg_name = fmt"__asl_arg_{arg_index}"
              case_body.add(c_decl_var(impl_arg.module_ref.generate_type,
                  arg_name,
                  c_call(
                    fmt"{impl_arg.module_ref.generate_type.emit}_read",
                    @[c_ident(def_arg.name.asl), c_lit("0")])))
              new_args.add(c_ident(arg_name))
          else:
            new_args.add(c_ident(def_arg.name.asl))

        let args_str_call = c_call(impl_fn.generate_func_name, new_args)
        case_body.add(c_decl_var(impl_fn.returns.generate_type,
            "__asl_result", args_str_call))

        case def.returns.kind:
        of AMRK_GENERIC:
          case_body.add(c_return(c_call(
              fmt"System_box_{impl_fn.returns.generate_type.emit}",
              @[c_ident("__asl_result")])))
        else:
          case_body.add(c_return(c_ident("__asl_result")))

        switch_cases.add((c_lit($impl_module.id), case_body))

      body.add(c_switch(c_ident(fmt"__asl_impl_id_{gen_index}"),
          switch_cases))
      body.add(c_raw("UNREACHABLE();"))

      decls.add(c_func_def(func_decl.func_return, func_decl.func_name,
          func_decl.func_params, body))

  for function in module.functions:
    decls.add(function.generate_function)
  return decls
