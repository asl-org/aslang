## AnalyzedAppContext — the analyzer's app-level context: the phase-A
## def bundle plus every AnalyzedFile accumulated so far. `analyze*`
## adds each file's analyzed form as it lands. The rung-3 twin of the
## resolver's ResolvedApp and the def analyzer's ResolvedAppContext.

import strformat, tables

import ./defanalyzer
import file

type AnalyzedAppContext* = ref object
  appDef: AnalyzedDefApp
  files: seq[AnalyzedFile]
  fileIndex: Table[string, int]

proc newAnalyzedAppContext*(appDef: AnalyzedDefApp): AnalyzedAppContext =
  AnalyzedAppContext(appDef: appDef)

proc fileDefs*(appCtx: AnalyzedAppContext): seq[AnalyzedDefFile] = appCtx.appDef.fileDefs
proc files*(appCtx: AnalyzedAppContext): seq[AnalyzedFile] = appCtx.files

proc findFileDef*(appCtx: AnalyzedAppContext, path: string): AnalyzedDefFile =
  appCtx.appDef.findFileDef(path)

proc add*(appCtx: AnalyzedAppContext, file: AnalyzedFile) =
  assert(file.path notin appCtx.fileIndex, fmt"[BUG] - duplicate file `{file.path}` in the app context")
  appCtx.fileIndex[file.path] = appCtx.files.len
  appCtx.files.add(file)
