## AnalyzedVariable — a resolved identifier bound to an argument type
## via the function scope. Independent of the mutually-recursive
## expression/statement cluster.

import ./resolver
import argtype

type AnalyzedVariable* = ref object
  name: Identifier
  argType: AnalyzedArgumentType

proc newAnalyzedVariable*(name: Identifier, argType: AnalyzedArgumentType): AnalyzedVariable =
  AnalyzedVariable(name: name, argType: argType)

proc loc*(variable: AnalyzedVariable): Location = variable.name.loc
proc name*(variable: AnalyzedVariable): Identifier = variable.name
proc argType*(variable: AnalyzedVariable): AnalyzedArgumentType = variable.argType
