import strformat, sequtils, strutils, options

import ../analyzer
import ../ir/constructors
import gen_module_ref
import gen_arg_def

proc generate_func_name*(def: AnalyzedFunctionDefinition): string =
  if def.extern.is_some:
    def.extern.get
  elif def.prefix == "":
    fmt"{def.name.asl}_{def.location.hash.to_hex}"
  else:
    fmt"{def.prefix}_{def.name.asl}_{def.location.hash.to_hex}"

proc generate_func_decl*(def: AnalyzedFunctionDefinition): CDecl =
  let generic_params: seq[(CType, string)] = if def.generics > 0:
    ((0.uint64)..<(def.generics)).map_it((c_named("U64"),
        fmt"__asl_impl_id_{it}"))
  else:
    @[]
  let arg_params = def.args.map_it(it.generate_param)
  let all_params = generic_params & arg_params
  let ret = def.returns.generate_type
  if def.extern.is_some:
    c_extern(ret, def.generate_func_name, all_params)
  else:
    c_func_decl(ret, def.generate_func_name, all_params)
