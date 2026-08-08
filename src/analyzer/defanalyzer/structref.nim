## Phase-A struct-ref wrapper — `AnalyzedStructRef` pairs the
## resolved ref with its receiver arg-type lifted to the analyzed form
## plus the RESOLVED struct def (the resolver's ref only carries the
## parser-level def; the def analyzer re-derives the resolved twin
## from the module). Produced by `analyzeDefStructRef` during the
## phase-A body walk.

import resolver
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
