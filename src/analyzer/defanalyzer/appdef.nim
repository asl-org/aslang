## Phase-A `AnalyzedDefApp` — the top-level phase-A result.
## Bundles the resolved app + every file's AnalyzedDefFile,
## indexed by absolute path for cross-file `findFileDef` queries.
##
## One identity-keyed index carries the phase-B lookup weight:
## `definedTypeIndex` (`ResolvedLocalType → AnalyzedLocalType`) —
## app-wide identity lookup used by `findDefinedType`. Every caller
## with a ResolvedLocalType in hand (from `fileCtx.findType`, an
## argType's carried module, etc.) reaches the analyzed
## module/generic without going through name-keyed per-file scopes;
## pre-analyzed funcDef signatures are then read off the result via
## `findFunctionDefs`. Immune to aliased-import name mismatch.

import strformat, tables

import ./resolver
import ./filedef

type AnalyzedDefApp* = ref object
  resolved: ResolvedApp
  fileDefs: seq[AnalyzedDefFile]
  fileDefIndex: Table[string, int]

proc newAnalyzedDefApp*(resolved: ResolvedApp,
    fileDefs: seq[AnalyzedDefFile]): AnalyzedDefApp =
  var fileDefIndex: Table[string, int]
  for index, fileDef in fileDefs:
    assert(fileDef.path notin fileDefIndex, fmt"[BUG] - duplicate file def `{fileDef.path}` in the app def")
    fileDefIndex[fileDef.path] = index
  AnalyzedDefApp(resolved: resolved, fileDefs: fileDefs, fileDefIndex: fileDefIndex)

proc resolved*(a: AnalyzedDefApp): ResolvedApp = a.resolved
proc fileDefs*(a: AnalyzedDefApp): seq[AnalyzedDefFile] = a.fileDefs

proc findFileDef*(appDef: AnalyzedDefApp, path: string): AnalyzedDefFile =
  ## Identity lookup — phase A produced a file def for every resolved
  ## file, so a miss is a compiler bug.
  assert(path in appDef.fileDefIndex, fmt"[BUG] - file `{path}` missing from the app def")
  appDef.fileDefs[appDef.fileDefIndex[path]]
