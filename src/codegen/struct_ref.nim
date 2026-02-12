import strformat

import analyzer

proc c*(struct_ref: AnalyzedStructRef): string =
  case struct_ref.struct.kind:
  of RSK_DEFAULT: fmt"{struct_ref.module_ref.name}"
  of RSK_NAMED: fmt"{struct_ref.module_ref.name}_{struct_ref.struct.name.asl}"

proc c*(union_ref: AnalyzedUnionRef): string =
  fmt"{union_ref.module_ref.name}_{union_ref.branch.name.asl}"

proc c*(data_ref: AnalyzedDataRef): string =
  case data_ref.kind:
  of ADRK_STRUCT: data_ref.struct.c
  of ADRK_UNION: data_ref.union.c
