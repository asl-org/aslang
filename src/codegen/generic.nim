import ../analyzer
import func_def

proc c*(generic: AnalyzedGeneric, prefix: string): seq[string] =
  var lines: seq[string]
  for def in generic.defs:
    lines.add(def.h)
  # TODO: provide implementation of generic calls
  return lines
