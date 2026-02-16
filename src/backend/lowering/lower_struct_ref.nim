import strformat

import ../../middle/analyzer

proc generate_data_ref_name*(struct_ref: AnalyzedStructRef): string =
  fmt"{struct_ref.module_ref.name}"

proc generate_data_ref_name*(union_ref: AnalyzedUnionRef): string =
  fmt"{union_ref.module_ref.name}_{union_ref.branch.name.asl}"

proc generate_data_ref_name*(data_ref: AnalyzedDataRef): string =
  case data_ref.kind:
  of ADRK_STRUCT: data_ref.struct.generate_data_ref_name
  of ADRK_UNION: data_ref.union.generate_data_ref_name
