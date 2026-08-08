## AnalyzedBinding — the (name, argType, impls) triple produced when a
## binding enters the function scope (a case pattern's variable, an
## assignment's target). `impls` is the generic-impl map that
## concretizes the binding's type on demand — carried so a variable
## used later as a match subject can concretize a pulled variant field.
##
## Pure tuple alias — no procs. Lives in its own file because it's
## referenced across the pattern cluster (union/case patterns) and
## the statement cluster (`arg` accessor on AnalyzedStatement).

import ./defanalyzer

type AnalyzedBinding* = tuple[name: Identifier, argType: AnalyzedArgumentType, impls: GenericImplMap]
