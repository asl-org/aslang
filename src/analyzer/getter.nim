## AnalyzedGetter — a resolved struct field access. Carries the
## source variable's analyzed argument type, the resolved field def
## from the struct's declaration, and the field's analyzed argument
## type (post-generic-substitution in the calling module context).
## Independent of the mutually-recursive expression/statement cluster.

import ./defanalyzer

type AnalyzedGetter* = ref object
  resolved: ResolvedGetter
  source: AnalyzedArgumentType
  property: AnalyzedArgumentDef

proc newAnalyzedGetter*(resolved: ResolvedGetter, source: AnalyzedArgumentType, property: AnalyzedArgumentDef): AnalyzedGetter =
  AnalyzedGetter(resolved: resolved, source: source, property: property)

proc loc*(getter: AnalyzedGetter): Location = getter.resolved.loc
proc argType*(getter: AnalyzedGetter): AnalyzedArgumentType = getter.property.argType
