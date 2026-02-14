import ../analyzer
import ../ir/constructors

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
