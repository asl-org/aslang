## AnalyzedModule — the per-module driver's result: the resolver
## ResolvedModule back-ref plus the analyzed function list.

import tables

import defanalyzer
import function

type AnalyzedModule* = ref object
  def: AnalyzedDefModule
  functions: seq[AnalyzedFunction]
  funcDefIndex: Table[AnalyzedFunctionDef, AnalyzedFunction]

proc newAnalyzedModule*(def: AnalyzedDefModule, functions: seq[AnalyzedFunction]): AnalyzedModule =
  var funcDefIndex: Table[AnalyzedFunctionDef, AnalyzedFunction]
  for function in functions:
    assert(function.def notin funcDefIndex, "[BUG] - function def not availabe in the function def index")
    funcDefIndex[function.def] = function

  AnalyzedModule(def: def, functions: functions, funcDefIndex: funcDefIndex)

proc public*(module: AnalyzedModule): bool = module.def.public
proc def*(module: AnalyzedModule): AnalyzedDefModule = module.def
proc functions*(module: AnalyzedModule): seq[AnalyzedFunction] = module.functions
proc findFunction*(module: AnalyzedModule, funcDef: AnalyzedFunctionDef): AnalyzedFunction =
  assert(funcDef in module.funcDefIndex, "[BUG] - function definition not present in the module func def index")
  module.funcDefIndex[funcDef]