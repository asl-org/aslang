## App-level resolution + the public resolve* entry point.
##
## Single-pass: each ResolvedFile is built in dependency order (BFS
## already ordered `app.files` leaves-first), and every argument type
## along the way carries a parser Module back-ref so nothing depends
## on another file's resolved form existing yet.

import strformat, tables

import ./parser
import files

# ResolvedApp + entry
type ResolvedApp* = ref object
  files: seq[ResolvedFile]
  fileIndex: Table[parser.File, int]

proc newResolvedApp*(files: seq[ResolvedFile]): ResolvedApp =
  var fileIndex: Table[parser.File, int]
  for id, file in files:
    assert(file.parsed notin fileIndex, fmt"[BUG] - duplicate file `{file.path}` in the resolved app")
    fileIndex[file.parsed] = id
  ResolvedApp(files: files, fileIndex: fileIndex)

proc files*(app: ResolvedApp): seq[ResolvedFile] = app.files
proc findFile*(app: ResolvedApp, file: parser.File): ResolvedFile =
  ## Identity lookup — the resolver resolved every file the loader
  ## produced, so a miss is a compiler bug.
  assert(file in app.fileIndex, fmt"[BUG] - file `{file.path}` missing from the resolved app")
  app.files[app.fileIndex[file]]
