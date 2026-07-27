## AnalyzedModule — the per-module driver's result: the resolver
## ResolvedModule back-ref plus the analyzed function list.

import ./defanalyzer
import function

type AnalyzedModule* = ref object
  def: AnalyzedModuleDefinition
  functions: seq[AnalyzedFunction]

proc newAnalyzedModule*(def: AnalyzedModuleDefinition, functions: seq[AnalyzedFunction]): AnalyzedModule =
  AnalyzedModule(def: def, functions: functions)

proc loc*(m: AnalyzedModule): Location = m.def.loc
proc name*(m: AnalyzedModule): Identifier = m.def.name
proc def*(m: AnalyzedModule): AnalyzedModuleDefinition = m.def
proc functions*(m: AnalyzedModule): seq[AnalyzedFunction] = m.functions
