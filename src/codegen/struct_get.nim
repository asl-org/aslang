import strformat

import analyzer
import module_ref

proc c*(struct_get: AnalyzedStructGet, result_arg: string): string =
  fmt"{struct_get.field.module_ref.c} {result_arg} = {struct_get.variable.module_ref.name}_get_{struct_get.field.name.asl}({struct_get.variable.name.asl});"
