## DefinedType / File / App + the public resolve* entry point.

import results, tables, options

import parser
import files

# ResolvedApp + entry
type ResolvedApp* = ref object
  files: seq[ResolvedFile]
  fileIndex: Table[parser.File, int]

proc newResolvedApp*(files: seq[ResolvedFile]): ResolvedApp =
  var fileIndex: Table[parser.File, int]
  for id, file in files:
    fileIndex[file.parsed] = id
  ResolvedApp(files: files, fileIndex: fileIndex)

proc files*(app: ResolvedApp): seq[ResolvedFile] = app.files
proc findFile*(app: ResolvedApp, file: parser.File): Option[ResolvedFile] =
  if file notin app.fileIndex: none(ResolvedFile)
  else: some(app.files[app.fileIndex[file]])

proc resolve*(app: App): Result[ResolvedApp, string] =
  var resolvedFiles: seq[ResolvedFile]
  for id, file in app.files:
    let resolvedFile = ? resolveFile(app, id, file)
    resolvedFiles.add(resolvedFile)
  ok(newResolvedApp(resolvedFiles))
