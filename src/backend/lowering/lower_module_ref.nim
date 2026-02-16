import strformat

import ../../middle/analyzer
import ../ir/constructors

proc generate_impl_id_inline*(module_ref: AnalyzedModuleRef): seq[CExpr] =
  case module_ref.kind:
  of AMRK_GENERIC: @[]
  of AMRK_MODULE:
    var args: seq[CExpr]
    for impl in module_ref.impls:
      let child = impl.module_ref
      case child.kind:
      of AMRK_GENERIC:
        args.add(c_ident(fmt"__asl_impl_id_{child.generic.id}"))
      of AMRK_MODULE:
        args.add(c_lit($child.module.id))
    args

proc generate_type*(module_ref: AnalyzedModuleRef): CType =
  let module_name = module_ref.name
  case module_name:
  of "U8", "S8", "U16", "S16", "U32", "S32", "F32", "U64", "S64", "F64",
      "String", "System":
    c_named(module_name)
  else:
    c_pointer()

proc generate_byte_size*(module_ref: AnalyzedModuleRef): uint64 =
  case module_ref.name:
  of "U8", "S8": 1
  of "U16", "S16": 2
  of "U32", "S32", "F32": 4
  of "U64", "S64", "F64": 8
  else: 8
