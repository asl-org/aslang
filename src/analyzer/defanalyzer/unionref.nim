## Phase-A union-ref wrapper — `AnalyzedUnionRef` pairs the
## resolved ref with its receiver arg-type lifted to the analyzed form
## plus the RESOLVED union def and variant (the resolver's ref only
## carries the parser-level def; the def analyzer re-derives the
## resolved twins from the module). Produced by `analyzeDefUnionRef`
## during the phase-A body walk.

import resolver
import argtype

type AnalyzedUnionRef* = ref object
  resolved: ResolvedUnionRef
  argType: AnalyzedModuleArgumentType
  union: ResolvedUnionDef
  variant: ResolvedVariantDef

proc newAnalyzedUnionRef*(resolved: ResolvedUnionRef, argType: AnalyzedModuleArgumentType, union: ResolvedUnionDef, variant: ResolvedVariantDef): AnalyzedUnionRef =
  AnalyzedUnionRef(resolved: resolved, argType: argType, union: union, variant: variant)

proc newAnalyzedUnionRef*(resolved: ResolvedUnionRef, module: ResolvedModule, union: ResolvedUnionDef, variant: ResolvedVariantDef): AnalyzedUnionRef =
  let argType = newAnalyzedModuleArgumentType(resolved.argType, module)
  newAnalyzedUnionRef(resolved, argType, union, variant)

proc module*(unionRef: AnalyzedUnionRef): ResolvedModule = unionRef.argType.module
proc argType*(unionRef: AnalyzedUnionRef): AnalyzedModuleArgumentType = unionRef.argType