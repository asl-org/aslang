import strformat, strutils

import ../analyzer
import func_def
import expression

proc c*(function: AnalyzedUserFunction): seq[string] =
  var lines: seq[string]
  lines.add(function.def.h.replace(";", ""))
  lines.add("{")
  for statement in function.statements:
    lines.add(statement.c)
  let last_arg = function.statements[^1].arg.name.asl
  lines.add(fmt"return {last_arg};")
  lines.add("}")
  return lines

proc c*(function: AnalyzedFunction): seq[string] =
  case function.kind:
  of AFK_EXTERN: @[]
  of AFK_USER: function.user.c
