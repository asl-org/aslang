## AnalyzedBinding — the (name, argType) pair produced when a case
## pattern introduces a variable into scope. Body-level replacement
## for the retired AnalyzedArgumentDef wrapper: the analyzer's
## function scope keys on Identifier and stores AnalyzedArgumentType,
## so a binding is exactly a name + its analyzed argument type.
##
## Pure tuple alias — no procs. Lives in its own file because it's
## referenced across the pattern cluster (union/case patterns) and
## the statement cluster (`arg` accessor on AnalyzedStatement).

import ./resolver
import argtype

type AnalyzedBinding* = tuple[name: Identifier, argType: AnalyzedArgumentType]
