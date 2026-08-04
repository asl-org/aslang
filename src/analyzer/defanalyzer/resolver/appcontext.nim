## AppContext — the resolver's app-level context: the parsed App plus
## every ResolvedFile accumulated so far. `resolve*` adds each file's
## resolved twin as it lands, so import resolution can link a binding
## to its source file's already-resolved types. The rung-1 analogue
## of what ResolvedApp is to the def analyzer.

import results, strformat, tables

import ./parser
import files

type AppContext* = ref object
  app: App
  resolvedFiles: seq[ResolvedFile]
  fileIndex: Table[string, int]

proc newAppContext*(app: App): AppContext =
  AppContext(app: app)

proc files*(appCtx: AppContext): seq[parser.File] = appCtx.app.files
proc resolvedFiles*(appCtx: AppContext): seq[ResolvedFile] = appCtx.resolvedFiles

proc findFile*(appCtx: AppContext, path: string): Result[parser.File, string] =
  appCtx.app.findFile(path)

proc add*(appCtx: AppContext, file: ResolvedFile) =
  assert(file.path notin appCtx.fileIndex, fmt"[BUG] - duplicate file `{file.path}` in the app context")
  appCtx.fileIndex[file.path] = appCtx.resolvedFiles.len
  appCtx.resolvedFiles.add(file)

proc findImportedFile*(appCtx: AppContext, path: string): ResolvedFile =
  ## Identity lookup — topo order (BFS leaves-first) guarantees every
  ## import's source file was resolved before its importer, so a miss
  ## is a compiler bug.
  assert(path in appCtx.fileIndex, fmt"[BUG] - file `{path}` not resolved before its importer")
  appCtx.resolvedFiles[appCtx.fileIndex[path]]
