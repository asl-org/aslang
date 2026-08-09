## ResolvedApp — the resolver's app-level result AND accumulator: the
## parsed App plus every ResolvedFile accumulated so far. `resolve*`
## adds each file's resolved twin as it lands, so import resolution
## can link a binding to its source file's already-resolved types.
## The rung-1 base of the app ladder — ResolvedAppContext (def
## analyzer) and AnalyzedAppContext (analyzer) wrap it in turn.

import results, strformat, tables

import parser
import files

type ResolvedApp* = ref object
  parsed: App
  files: seq[ResolvedFile]
  fileIndex: Table[parser.File, int]
  filePathIndex: Table[string, int]

proc newResolvedApp*(parsed: App): ResolvedApp =
  ResolvedApp(parsed: parsed)

# proc files*(appCtx: ResolvedApp): seq[parser.File] = appCtx.app.files
proc files*(appCtx: ResolvedApp): seq[ResolvedFile] = appCtx.files

proc add*(appCtx: ResolvedApp, file: ResolvedFile) =
  assert(file.path notin appCtx.filePathIndex, fmt"[BUG] - duplicate file `{file.path}` in the app context")
  appCtx.filePathIndex[file.path] = appCtx.files.len

  assert(file.parsed notin appCtx.fileIndex, fmt"[BUG] - duplicate file `{file.path}` in the app context")
  appCtx.fileIndex[file.parsed] = appCtx.files.len

  appCtx.files.add(file)

proc findFile*(appCtx: ResolvedApp, path: string): Result[parser.File, string] =
  appCtx.parsed.findFile(path)

proc findFile*(appCtx: ResolvedApp, file: parser.File): ResolvedFile =
  ## Identity lookup — the resolver resolved every file the loader
  ## produced, so a miss is a compiler bug.
  assert(file in appCtx.fileIndex, fmt"[BUG] - file `{file.path}` missing from the resolved app")
  appCtx.files[appCtx.fileIndex[file]]

proc findImportedFile*(appCtx: ResolvedApp, path: string): ResolvedFile =
  ## Identity lookup — topo order (BFS leaves-first) guarantees every
  ## import's source file was resolved before its importer, so a miss
  ## is a compiler bug.
  assert(path in appCtx.filePathIndex, fmt"[BUG] - file `{path}` not resolved before its importer")
  appCtx.files[appCtx.filePathIndex[path]]
