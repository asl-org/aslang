## Phase-A ref wrappers — `AnalyzedDefStructRef` / `AnalyzedDefUnionRef`
## pair a resolved ref with its receiver arg-type lifted to the
## analyzed form plus the RESOLVED data def (the resolver's ref only
## carries the parser-level def; the def analyzer re-derives the
## resolved twin from the module). Produced by `analyzeDefStructRef` /
## `analyzeDefUnionRef` during the phase-A body pre-walk.

import resolver
import argtype

type AnalyzedDefStructRef* = ref object
  resolved: ResolvedStructRef
  argType: AnalyzedModuleArgumentType
  struct: ResolvedStructDef

proc newAnalyzedDefStructRef*(resolved: ResolvedStructRef, argType: AnalyzedModuleArgumentType, struct: ResolvedStructDef): AnalyzedDefStructRef =
  AnalyzedDefStructRef(resolved: resolved, argType: argType, struct: struct)

proc newAnalyzedDefStructRef*(resolved: ResolvedStructRef, module: ResolvedModule, struct: ResolvedStructDef): AnalyzedDefStructRef =
  let argType = newAnalyzedModuleArgumentType(resolved.argType, module)
  newAnalyzedDefStructRef(resolved, argType, struct)

proc module*(structRef: AnalyzedDefStructRef): ResolvedModule = structRef.argType.module
proc struct*(structRef: AnalyzedDefStructRef): ResolvedStructDef = structRef.struct

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