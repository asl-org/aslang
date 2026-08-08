## AnalyzedBinding — the (name, argType, impls) triple produced when a
## binding enters the function scope (a case pattern's variable, an
## assignment's target). `impls` is the generic-impl map that
## concretizes the binding's type on demand — carried so a variable
## used later as a match subject can concretize a pulled variant field.
##
## Lives in its own file because it's referenced across the pattern
## cluster (union/case patterns) and the statement cluster (`arg`
## accessor on AnalyzedStatement).

import ./defanalyzer

type AnalyzedBinding* = ref object
  name: Identifier
  argType: AnalyzedArgumentType
  impls: GenericImplMap

proc newAnalyzedBinding*(name: Identifier, argType: AnalyzedArgumentType, impls: GenericImplMap): AnalyzedBinding =
  AnalyzedBinding(name: name, argType: argType, impls: impls)

proc name*(binding: AnalyzedBinding): Identifier = binding.name
proc argType*(binding: AnalyzedBinding): AnalyzedArgumentType = binding.argType
# The impl map inherited from whatever bound this variable — used to
# concretize a variant field when the binding is a match subject.
proc impls*(binding: AnalyzedBinding): GenericImplMap = binding.impls
