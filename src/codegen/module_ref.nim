import analyzer

proc byte_size*(module_ref: AnalyzedModuleRef): uint64 =
  case module_ref.name:
  of "U8", "S8": 1
  of "U16", "S16": 2
  of "U32", "S32", "F32": 4
  of "U64", "S64", "F64": 8
  else: 8

proc c*(module_ref: AnalyzedModuleRef): string =
  let module_name = module_ref.name
  case module_name:
  of "U8", "S8": module_name
  of "U16", "S16": module_name
  of "U32", "S32", "F32": module_name
  of "U64", "S64", "F64": module_name
  of "String", "System": module_name
  else: "Pointer"
