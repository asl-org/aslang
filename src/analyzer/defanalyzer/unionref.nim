## Phase-A union-ref wrapper — `AnalyzedDefUnionRef` pairs the
## resolved ref with its receiver arg-type lifted to the analyzed form
## plus the RESOLVED union def and variant (the resolver's ref only
## carries the parser-level def; the def analyzer re-derives the
## resolved twins from the module). Produced by `analyzeDefUnionRef`
## during the phase-A body walk.

import resolver
import argtype

type AnalyzedDefUnionRef* = ref object
  resolved: ResolvedUnionRef
  argType: AnalyzedModuleArgumentType
  union: ResolvedUnionDef
  variant: ResolvedVariant

proc newAnalyzedDefUnionRef*(resolved: ResolvedUnionRef, argType: AnalyzedModuleArgumentType, union: ResolvedUnionDef, variant: ResolvedVariant): AnalyzedDefUnionRef =
  AnalyzedDefUnionRef(resolved: resolved, argType: argType, union: union, variant: variant)

proc newAnalyzedDefUnionRef*(resolved: ResolvedUnionRef, module: ResolvedModule, union: ResolvedUnionDef, variant: ResolvedVariant): AnalyzedDefUnionRef =
  let argType = newAnalyzedModuleArgumentType(resolved.argType, module)
  newAnalyzedDefUnionRef(resolved, argType, union, variant)

proc module*(unionRef: AnalyzedDefUnionRef): ResolvedModule = unionRef.argType.module
proc union*(unionRef: AnalyzedDefUnionRef): ResolvedUnionDef = unionRef.union
proc variant*(unionRef: AnalyzedDefUnionRef): ResolvedVariant = unionRef.variant
proc argType*(unionRef: AnalyzedDefUnionRef): AnalyzedModuleArgumentType = unionRef.argType