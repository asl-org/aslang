## AnalyzedUserFunction — a user-defined function whose body has been
## analyzed. Carries the resolver's back-ref, the function's arg/return
## def, and the analyzed statement list.

import ./defanalyzer
import statement

type AnalyzedUserFunction* = ref object
  resolved: ResolvedUserFunction
  def: AnalyzedFunctionDefinition
  statements: seq[AnalyzedStatement]

proc newAnalyzedUserFunction*(resolved: ResolvedUserFunction, def: AnalyzedFunctionDefinition, statements: seq[AnalyzedStatement]): AnalyzedUserFunction =
  AnalyzedUserFunction(resolved: resolved, def: def, statements: statements)

proc resolved*(function: AnalyzedUserFunction): ResolvedUserFunction = function.resolved
proc def*(function: AnalyzedUserFunction): AnalyzedFunctionDefinition = function.def
proc statements*(function: AnalyzedUserFunction): seq[AnalyzedStatement] = function.statements
