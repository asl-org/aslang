## AnalyzedBinding — the (name, argType) pair produced when a binding
## enters the function scope (a case pattern's variable, an
## assignment's target). The generic bindings a later match on this
## variable needs are intrinsic to its `argType` (every module argtype
## carries its slot→impl map), so no separate map rides on the binding.
##
## Lives in its own file because it's referenced across the pattern
## cluster (union/case patterns) and the statement cluster (`arg`
## accessor on AnalyzedStatement).

import ./defanalyzer

type AnalyzedBinding* = ref object
  name: Identifier
  argType: AnalyzedArgumentType

proc newAnalyzedBinding*(name: Identifier, argType: AnalyzedArgumentType): AnalyzedBinding =
  AnalyzedBinding(name: name, argType: argType)

proc name*(binding: AnalyzedBinding): Identifier = binding.name
proc argType*(binding: AnalyzedBinding): AnalyzedArgumentType = binding.argType
