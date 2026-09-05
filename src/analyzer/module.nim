## AnalyzedModule — the per-module driver's result: the resolver
## ResolvedModule back-ref plus the analyzed function list.

import tables, options

import ../defanalyzer/index as defanalyzer
import function

type AnalyzedModule* = ref object
  def: AnalyzedDefModule
  functions: seq[AnalyzedFunction]
  funcDefIndex: Table[AnalyzedFunctionDef, int]

proc newAnalyzedModule*(def: AnalyzedDefModule, functions: seq[AnalyzedFunction]): AnalyzedModule =
  var funcDefIndex: Table[AnalyzedFunctionDef, int]
  for id, function in functions:
    assert(function.def notin funcDefIndex, "[BUG] - function def not availabe in the function def index")
    funcDefIndex[function.def] = id

  AnalyzedModule(def: def, functions: functions, funcDefIndex: funcDefIndex)

proc loc*(module: AnalyzedModule): Location = module.def.resolved.loc
proc resolved*(module: AnalyzedModule): ResolvedModule = module.def.resolved
proc public*(module: AnalyzedModule): bool = module.def.public
proc name*(module: AnalyzedModule): Identifier = module.def.name
proc data*(module: AnalyzedModule): Option[AnalyzedDataDef] = module.def.data
proc def*(module: AnalyzedModule): AnalyzedDefModule = module.def
proc functions*(module: AnalyzedModule): seq[AnalyzedFunction] = module.functions
proc findFunctionId*(module: AnalyzedModule, funcDef: AnalyzedFunctionDef): int =
  assert(funcDef in module.funcDefIndex, "[BUG] - function definition not present in the module func def index")
  module.funcDefIndex[funcDef]
proc findFunction*(module: AnalyzedModule, funcDef: AnalyzedFunctionDef): AnalyzedFunction =
  module.functions[module.findFunctionId(funcDef)]