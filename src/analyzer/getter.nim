## AnalyzedGetter — a resolved struct field access. Carries the
## source variable's analyzed argument type, the resolved field def
## from the struct's declaration, and the field's analyzed argument
## type (post-generic-substitution in the calling module context).
## Independent of the mutually-recursive expression/statement cluster.

import ./resolver
import argtype

type AnalyzedGetter* = ref object
  resolved: ResolvedGetter
  source: AnalyzedArgumentType
  property: ResolvedArgumentDef
  propertyArgType: AnalyzedArgumentType

proc newAnalyzedGetter*(resolved: ResolvedGetter, source: AnalyzedArgumentType, property: ResolvedArgumentDef, propertyArgType: AnalyzedArgumentType): AnalyzedGetter =
  AnalyzedGetter(resolved: resolved, source: source, property: property, propertyArgType: propertyArgType)

proc loc*(getter: AnalyzedGetter): Location = getter.resolved.loc
proc resolved*(getter: AnalyzedGetter): ResolvedGetter = getter.resolved
proc source*(getter: AnalyzedGetter): AnalyzedArgumentType = getter.source
proc argType*(getter: AnalyzedGetter): AnalyzedArgumentType = getter.propertyArgType
proc property*(getter: AnalyzedGetter): ResolvedArgumentDef = getter.property
