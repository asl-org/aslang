import strformat

import ../analyzer
import module_ref

proc c*(literal: AnalyzedLiteral, result_arg: string): string =
  fmt"{literal.module_ref.c} {result_arg} = {literal.literal.asl};"
