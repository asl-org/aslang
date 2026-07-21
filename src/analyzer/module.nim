## AnalyzedModule — the per-module driver's result: the resolver
## ResolvedModule back-ref plus the analyzed function list.

import ./resolver
import function

type AnalyzedModule* = ref object
  def: ResolvedModule
  functions: seq[AnalyzedFunction]

proc newAnalyzedModule*(def: ResolvedModule, functions: seq[AnalyzedFunction]): AnalyzedModule =
  AnalyzedModule(def: def, functions: functions)

proc def*(m: AnalyzedModule): ResolvedModule = m.def
proc resolved*(m: AnalyzedModule): ResolvedModule = m.def
proc loc*(m: AnalyzedModule): Location = m.def.loc
proc name*(m: AnalyzedModule): Identifier = m.def.name
proc functions*(m: AnalyzedModule): seq[AnalyzedFunction] = m.functions
