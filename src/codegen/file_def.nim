import ../analyzer
import module_def
import func_def

proc h*(file: AnalyzedFileDefinition): seq[string] =
  var lines: seq[string]
  for module in file.modules:
    lines.add(module.h)
  for fndef in file.function_defs:
    lines.add(fndef.h)
  return lines

proc c*(file: AnalyzedFileDefinition): seq[string] =
  var lines: seq[string]
  for module in file.modules:
    lines.add(module.c)
  return lines
