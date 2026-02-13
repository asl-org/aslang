import sequtils

import analyzer
import generic
import struct
import func_def

proc typedefs*(def: AnalyzedModuleDefinition): seq[string] =
  def.data.typedefs(def.name.asl)

proc h*(def: AnalyzedModuleDefinition): seq[string] =
  var lines: seq[string]
  for generic in def.generics:
    lines.add(generic.c(def.name.asl))

  lines.add(def.data.h(def.name.asl))
  lines.add(def.function_defs.map_it(it.h))

  return lines

proc c*(def: AnalyzedModuleDefinition): seq[string] =
  var lines: seq[string]
  for generic in def.generics:
    lines.add(generic.c(def.name.asl))

  lines.add(def.data.c(def.name.asl))

  return lines
