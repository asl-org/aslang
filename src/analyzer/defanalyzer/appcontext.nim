## ResolvedAppContext — the def analyzer's app-level context: the
## resolved app plus every AnalyzedDefFile accumulated so far.
## `analyzeDefApp` adds each file's def bundle as it lands. The
## rung-2 twin of the resolver's ResolvedApp.

import strformat, tables

import ./resolver
import ./filedef

type ResolvedAppContext* = ref object
  resolved: ResolvedApp
  fileDefs: seq[AnalyzedDefFile]
  fileDefIndex: Table[string, int]

proc newResolvedAppContext*(resolved: ResolvedApp): ResolvedAppContext =
  ResolvedAppContext(resolved: resolved)

proc files*(appCtx: ResolvedAppContext): seq[ResolvedFile] = appCtx.resolved.files
proc fileDefs*(appCtx: ResolvedAppContext): seq[AnalyzedDefFile] = appCtx.fileDefs

proc findFile*(appCtx: ResolvedAppContext, file: parser.File): ResolvedFile =
  appCtx.resolved.findFile(file)

proc add*(appCtx: ResolvedAppContext, fileDef: AnalyzedDefFile) =
  assert(fileDef.path notin appCtx.fileDefIndex, fmt"[BUG] - duplicate file def `{fileDef.path}` in the app context")
  appCtx.fileDefIndex[fileDef.path] = appCtx.fileDefs.len
  appCtx.fileDefs.add(fileDef)
