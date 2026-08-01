## Phase-A struct-ref wrapper — `AnalyzedDefStructRef` pairs the
## resolved ref with its receiver arg-type lifted to the analyzed form
## plus the RESOLVED struct def (the resolver's ref only carries the
## parser-level def; the def analyzer re-derives the resolved twin
## from the module). Produced by `analyzeDefStructRef` during the
## phase-A body walk.

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
