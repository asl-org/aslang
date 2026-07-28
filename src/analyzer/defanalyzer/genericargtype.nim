## Analyzed argument-type cluster.
##
## `AnalyzedGenericArgumentType`, `AnalyzedModuleArgumentType`, and the
## outer `AnalyzedArgumentType` tagged union all live in this single
## file because Nim requires mutually-referencing `ref object` types to
## share one `type` block (`impls: seq[AnalyzedArgumentType]` on the
## module variant references the outer union). Both context overloads
## of the `analyze*` procs (module ctx with ResolvedFileScope, generic
## ctx) live on the analyzer facade.
##
## Post-task-7: `analyzeModuleArgumentType` on the facade no longer
## performs arity or generic-constraint validation — that's the
## resolver's job. Each ResolvedModuleArgumentType's `impls` seq is a
## provably valid value by the time the analyzer sees it.

import hashes

import ./resolver

# AnalyzedGenericArgumentType — wraps a ResolvedGeneric with the
# use-site location so analyzer diagnostics can point precisely.
type AnalyzedGenericArgumentType* = ref object
  resolved: ResolvedGeneric
  loc: Location

proc newAnalyzedGenericArgumentType*(resolved: ResolvedGeneric, loc: Location): AnalyzedGenericArgumentType =
  AnalyzedGenericArgumentType(resolved: resolved, loc: loc)

proc resolved*(g: AnalyzedGenericArgumentType): ResolvedGeneric = g.resolved
proc loc*(g: AnalyzedGenericArgumentType): Location = g.loc
proc name*(g: AnalyzedGenericArgumentType): Identifier = g.resolved.name
proc hash*(g: AnalyzedGenericArgumentType): Hash = g.resolved.hash
proc `==`*(a, b: AnalyzedGenericArgumentType): bool = a.hash == b.hash
proc asl*(argType: AnalyzedGenericArgumentType): string =
  argType.resolved.name.asl
