## AnalyzedVariable — a resolved identifier bound to an argument type
## via the function scope. Independent of the mutually-recursive
## expression/statement cluster.

import ./defanalyzer

type AnalyzedVariable* = ref object
  name: Identifier
  argType: AnalyzedArgumentType
  impls: GenericImplMap

proc newAnalyzedVariable*(name: Identifier, argType: AnalyzedArgumentType, impls: GenericImplMap): AnalyzedVariable =
  AnalyzedVariable(name: name, argType: argType, impls: impls)

proc loc*(variable: AnalyzedVariable): Location = variable.name.loc
proc argType*(variable: AnalyzedVariable): AnalyzedArgumentType = variable.argType
# The impl map inherited from whatever bound this variable — used to
# concretize a variant field when the variable is a match subject.
proc impls*(variable: AnalyzedVariable): GenericImplMap = variable.impls
