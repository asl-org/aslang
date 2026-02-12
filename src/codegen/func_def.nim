import strformat, sequtils, strutils, options

import ../analyzer
import module_ref
import arg_def

proc c_name*(def: AnalyzedFunctionDefinition): string =
  if def.extern.is_some:
    def.extern.get
  elif def.prefix == "":
    fmt"{def.name.asl}_{def.location.hash.to_hex}"
  else:
    fmt"{def.prefix}_{def.name.asl}_{def.location.hash.to_hex}"

proc h*(def: AnalyzedFunctionDefinition): string =
  let generic_args = if def.generics > 0: ((0.uint64)..<(
      def.generics)).map_it(fmt"U64 __asl_impl_id_{it}") else: @[]
  let args = generic_args & def.args.map_it(it.c)
  let args_str = args.join(", ")
  let code = fmt"{def.returns.c} {def.c_name}({args_str});"
  if def.extern.is_some: fmt"extern {code}" else: code
