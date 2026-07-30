## Phase-A `AnalyzedDefUnionRef` — a ResolvedUnionRef with its
## receiver arg-type lifted to the analyzed form. Produced by
## `analyzeDefUnionRef` during the phase-A body pre-walk.

import resolver
import argtype

type AnalyzedDefUnionRef* = ref object
  resolved: ResolvedUnionRef
  argType: AnalyzedModuleArgumentType
  union: ResolvedUnionDef

proc newAnalyzedDefUnionRef*(resolved: ResolvedUnionRef, argType: AnalyzedModuleArgumentType, union: ResolvedUnionDef): AnalyzedDefUnionRef =
  AnalyzedDefUnionRef(resolved: resolved, argType: argType, union: union)

proc module*(unionRef: AnalyzedDefUnionRef): ResolvedModule = unionRef.argType.module
proc union*(unionRef: AnalyzedDefUnionRef): ResolvedUnionDef = unionRef.union