import strformat

import analyzer
import module_ref

proc h*(literal: AnalyzedLiteral, module_name: string): string =
  fmt"typedef {literal.name} {module_name};"

proc c*(literal: AnalyzedLiteralInit, result_arg: string): string =
  fmt"{literal.module_ref.c} {result_arg} = {literal.literal.asl};"
