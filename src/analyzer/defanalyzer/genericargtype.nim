## AnalyzedGenericArgumentType — wraps a ResolvedGeneric with the
## use-site location so analyzer diagnostics can point precisely.
## Lives outside ./argtype because it does not participate in the
## mutually-recursive ref-object cycle there (only the module variant
## references the outer union).

import hashes

import ./resolver

type AnalyzedGenericArgumentType* = ref object
  resolved: ResolvedGeneric
  loc: Location

proc newAnalyzedGenericArgumentType*(resolved: ResolvedGeneric, loc: Location): AnalyzedGenericArgumentType =
  AnalyzedGenericArgumentType(resolved: resolved, loc: loc)

proc generic*(g: AnalyzedGenericArgumentType): ResolvedGeneric = g.resolved
proc loc*(g: AnalyzedGenericArgumentType): Location = g.loc
proc name*(g: AnalyzedGenericArgumentType): Identifier = g.resolved.name
proc hash*(g: AnalyzedGenericArgumentType): Hash = g.resolved.hash
proc `==`*(a, b: AnalyzedGenericArgumentType): bool = a.hash == b.hash
proc self*(argType: AnalyzedGenericArgumentType): ResolvedGenericArgumentType =
  newResolvedGenericArgumentType(argType.resolved.parsed, newLocation())
proc asl*(argType: AnalyzedGenericArgumentType): string =
  argType.resolved.name.asl
