## AnalyzedUserFunction — a user-defined function whose body has been
## analyzed. Carries the resolver's back-ref, the function's arg/return
## def, and the analyzed statement list.

import ./defanalyzer
import statement

type AnalyzedUserFunction* = ref object
  def: AnalyzedDefUserFunction
  statements: seq[AnalyzedStatement]

proc newAnalyzedUserFunction*(def: AnalyzedDefUserFunction, statements: seq[AnalyzedStatement]): AnalyzedUserFunction =
  AnalyzedUserFunction(def: def, statements: statements)

proc resolved*(function: AnalyzedUserFunction): ResolvedUserFunction = function.def.resolved
proc def*(function: AnalyzedUserFunction): AnalyzedDefUserFunction = function.def
proc statements*(function: AnalyzedUserFunction): seq[AnalyzedStatement] = function.statements
