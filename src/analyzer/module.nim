## AnalyzedModule — the per-module driver's result: the resolver
## ResolvedModule back-ref plus the analyzed function list.

import ./defanalyzer
import function

type AnalyzedModule* = ref object
  def: AnalyzedDefModule
  functions: seq[AnalyzedFunction]

proc newAnalyzedModule*(def: AnalyzedDefModule, functions: seq[AnalyzedFunction]): AnalyzedModule =
  AnalyzedModule(def: def, functions: functions)

proc public*(module: AnalyzedModule): bool = module.def.public
proc functions*(module: AnalyzedModule): seq[AnalyzedFunction] = module.functions