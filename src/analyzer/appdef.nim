## Phase-A `AnalyzedAppDefinition` — the top-level phase-A result.
## Bundles the resolved app + every file's AnalyzedFileDefinition,
## indexed by absolute path for cross-file lookup during phase B
## (specifically, the import walk in analyzeFile augments defScope
## by looking up the source file's fileDef via findFileDef).

import results, strformat, tables

import ./resolver
import ./filedef

type AnalyzedAppDefinition* = ref object
  resolved: ResolvedApp
  fileDefs: seq[AnalyzedFileDefinition]
  fileDefIndex: Table[string, int]

proc newAnalyzedAppDefinition*(resolved: ResolvedApp,
    fileDefs: seq[AnalyzedFileDefinition]): AnalyzedAppDefinition =
  var fileDefIndex: Table[string, int]
  for index, fileDef in fileDefs:
    fileDefIndex[fileDef.path] = index
  AnalyzedAppDefinition(resolved: resolved, fileDefs: fileDefs,
    fileDefIndex: fileDefIndex)

proc resolved*(a: AnalyzedAppDefinition): ResolvedApp = a.resolved
proc fileDefs*(a: AnalyzedAppDefinition): seq[AnalyzedFileDefinition] = a.fileDefs

proc findFileDef*(appDef: AnalyzedAppDefinition, path: string): Result[AnalyzedFileDefinition, string] =
  if path notin appDef.fileDefIndex:
    err(fmt"file `{path}` not found")
  else:
    ok(appDef.fileDefs[appDef.fileDefIndex[path]])
