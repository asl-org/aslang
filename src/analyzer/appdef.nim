## Phase-A `AnalyzedAppDefinition` — the top-level phase-A result.
## Bundles the resolved app + every file's AnalyzedFileDefinition,
## indexed by absolute path for cross-file lookup during phase B
## (specifically, the import walk in analyzeFile augments defScope
## by looking up the source file's fileDef via findFileDef).
##
## Also indexes every module's every funcDef so phase B can go from
## `ResolvedFunctionDef` (what analyzeFunctionCall gets from
## overload resolution) to `AnalyzedFunctionDefinition` (pre-analyzed
## args + return type) in O(1). This avoids the current
## re-analysis-per-call-site cost.

import results, strformat, tables

import ./resolver
import ./filedef
import ./definedtype
import ./moduledef
import ./generic
import ./funcdef

type AnalyzedAppDefinition* = ref object
  resolved: ResolvedApp
  fileDefs: seq[AnalyzedFileDefinition]
  fileDefIndex: Table[string, int]
  funcDefIndex: Table[ResolvedFunctionDef, AnalyzedFunctionDefinition]

proc buildFuncDefIndex(fileDefs: seq[AnalyzedFileDefinition]): Table[ResolvedFunctionDef, AnalyzedFunctionDefinition] =
  ## Walk every file → every defined type → every module or generic →
  ## every funcDef, indexing by the underlying ResolvedFunctionDef.
  ## Used by `findFunctionDef` on the app-level lookup for phase B.
  for fileDef in fileDefs:
    for definedType in fileDef.types:
      case definedType.kind:
      of adtkModule:
        for funcDef in definedType.module.funcDefs:
          result[funcDef.resolved] = funcDef
      of adtkGeneric:
        for funcDef in definedType.generic.funcDefs:
          result[funcDef.resolved] = funcDef

proc newAnalyzedAppDefinition*(resolved: ResolvedApp,
    fileDefs: seq[AnalyzedFileDefinition]): AnalyzedAppDefinition =
  var fileDefIndex: Table[string, int]
  for index, fileDef in fileDefs:
    fileDefIndex[fileDef.path] = index
  AnalyzedAppDefinition(resolved: resolved, fileDefs: fileDefs,
    fileDefIndex: fileDefIndex,
    funcDefIndex: buildFuncDefIndex(fileDefs))

proc resolved*(a: AnalyzedAppDefinition): ResolvedApp = a.resolved
proc fileDefs*(a: AnalyzedAppDefinition): seq[AnalyzedFileDefinition] = a.fileDefs

proc findFileDef*(appDef: AnalyzedAppDefinition, path: string): Result[AnalyzedFileDefinition, string] =
  if path notin appDef.fileDefIndex:
    err(fmt"file `{path}` not found")
  else:
    ok(appDef.fileDefs[appDef.fileDefIndex[path]])

proc findFunctionDef*(appDef: AnalyzedAppDefinition, funcDef: ResolvedFunctionDef): Result[AnalyzedFunctionDefinition, string] =
  ## Given a ResolvedFunctionDef (what overload resolution hands
  ## back from ResolvedModule.findFunctionDefs), return the
  ## pre-analyzed AnalyzedFunctionDefinition — no re-analysis of arg
  ## types or return type. Used by analyzeArgumentList to consume
  ## phase-A results.
  if funcDef notin appDef.funcDefIndex:
    err(fmt"{funcDef.loc} UNREACHABLE: funcDef `{funcDef.name.asl}` not indexed in phase-A output")
  else:
    ok(appDef.funcDefIndex[funcDef])
