## AnalyzedExternFunction — an extern function has no body, so the
## analyzed form is just the resolver back-ref + the function def.

import ./defanalyzer

type AnalyzedExternFunction* = ref object
  resolved: ResolvedExternFunction
  def: ResolvedFunctionDef

proc newAnalyzedExternFunction*(resolved: ResolvedExternFunction, def: ResolvedFunctionDef): AnalyzedExternFunction =
  AnalyzedExternFunction(resolved: resolved, def: def)

proc resolved*(function: AnalyzedExternFunction): ResolvedExternFunction = function.resolved
proc def*(function: AnalyzedExternFunction): ResolvedFunctionDef = function.def
