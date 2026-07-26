## App-level resolution + the public resolve* entry point.
##
## Single-pass: each ResolvedFile is built in dependency order (BFS
## already ordered `app.files` leaves-first), and every argument type
## along the way carries a parser Module back-ref so nothing depends
## on another file's resolved form existing yet.

import results, strformat, tables

import ./parser
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
proc findFile*(app: ResolvedApp, file: parser.File): Result[ResolvedFile, string] =
  if file notin app.fileIndex: err(fmt"file `{file.path}` does not exist")
  else: ok(app.files[app.fileIndex[file]])
