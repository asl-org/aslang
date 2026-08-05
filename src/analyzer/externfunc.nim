## AnalyzedExternFunction — an extern function has no body, so the
## analyzed form is just the resolver back-ref + the function def.

import ./defanalyzer

type AnalyzedExternFunction* = ref object
  def: AnalyzedDefExternFunction

proc newAnalyzedExternFunction*(def: AnalyzedDefExternFunction): AnalyzedExternFunction =
  AnalyzedExternFunction(def: def)

