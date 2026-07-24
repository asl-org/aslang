## App-level resolution + the public resolve* entry point.
##
## Single-pass: each ResolvedFile is built in dependency order (BFS
## already ordered `app.files` leaves-first), and every argument type
## along the way carries a parser Module back-ref so nothing depends
## on another file's resolved form existing yet.

import tables, options

import ./parser
import files
import types

# ResolvedApp + entry
type ResolvedApp* = ref object
  files: seq[ResolvedFile]
  fileIndex: Table[parser.File, int]
  typeIndex: Table[parser.Type, ResolvedType]

proc newResolvedApp*(files: seq[ResolvedFile]): ResolvedApp =
  var fileIndex: Table[parser.File, int]
  var typeIndex: Table[parser.Type, ResolvedType]
  for id, file in files:
    fileIndex[file.parsed] = id
    for typ in file.types:
      typeIndex[typ.parsed] = typ
  ResolvedApp(files: files, fileIndex: fileIndex, typeIndex: typeIndex)

proc files*(app: ResolvedApp): seq[ResolvedFile] = app.files
proc findFile*(app: ResolvedApp, file: parser.File): Option[ResolvedFile] =
  if file notin app.fileIndex: none(ResolvedFile)
  else: some(app.files[app.fileIndex[file]])

proc findType*(app: ResolvedApp, parsed: parser.Type): Option[ResolvedType] =
  ## Identity-based lookup: given a parser.Type (from a
  ## ResolvedModuleArgumentType.module etc.), return the ResolvedType
  ## that wraps it. Immune to the aliased-import name mismatch — the
  ## parser.Type is loc-hashed and stable regardless of what binding
  ## name it was imported under. See
  ## plans/plan_identity_based_lookups.md.
  if parsed notin app.typeIndex: none(ResolvedType)
  else: some(app.typeIndex[parsed])
