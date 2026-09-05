## Phase-A ref wrappers — `AnalyzedStructRef` / `AnalyzedUnionRef` pair a
## resolved ref with its receiver arg-type lifted to the analyzed form
## plus the RESOLVED struct/union def(s). The resolver's refs carry only
## the parser-level def; the def analyzer re-derives the resolved twins
## from the module. Produced by `analyzeDefStructRef` / `analyzeDefUnionRef`
## during the phase-A body walk.

import resolver/index as resolver
import argtype

type AnalyzedStructRef* = ref object
  resolved: ResolvedStructRef
  argType: AnalyzedModuleArgumentType
  struct: ResolvedStructDef

proc newAnalyzedStructRef*(resolved: ResolvedStructRef, argType: AnalyzedModuleArgumentType, struct: ResolvedStructDef): AnalyzedStructRef =
  AnalyzedStructRef(resolved: resolved, argType: argType, struct: struct)

proc newAnalyzedStructRef*(resolved: ResolvedStructRef, module: ResolvedModule, struct: ResolvedStructDef): AnalyzedStructRef =
  let argType = newAnalyzedModuleArgumentType(resolved.argType, module)
  newAnalyzedStructRef(resolved, argType, struct)

proc module*(structRef: AnalyzedStructRef): ResolvedModule = structRef.argType.module
proc argType*(structRef: AnalyzedStructRef): AnalyzedModuleArgumentType = structRef.argType

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
