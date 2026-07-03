## App-level resolution + the public resolve* entry point.
##
## Runs the declare pass (shell allocation for every parser Module
## in the app) before delegating to per-file resolution. The
## `ResolvedModuleShells` table threads through the define pass so
## every ResolvedModuleArgumentType can point at a stable shell.

import results, tables, options

import parser
import types
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

proc buildModuleShells(app: App): ResolvedModuleShells =
  ## Declare pass: walk every DefinedType in every file (both
  ## `.asl` sources and `.aslr` runtime files) and allocate a shell
  ## ResolvedModule for each parser Module. The shells are empty
  ## except for their `parsed` back-ref; the define pass `populate`s
  ## each one when the corresponding module resolves.
  for file in app.files:
    for definedType in file.definedTypes:
      case definedType.kind:
      of dtkModule:
        let parsedModule = definedType.module
        if parsedModule notin result:
          result[parsedModule] = newResolvedModuleShell(parsedModule)
      of dtkGeneric:
        discard  # generic edge stays parser-level (task 6c scope limit)

proc resolve*(app: App): Result[ResolvedApp, string] =
  let shells = buildModuleShells(app)
  var resolvedFiles: seq[ResolvedFile]
  for id, file in app.files:
    let resolvedFile = ? resolveFile(app, shells, id, file)
    resolvedFiles.add(resolvedFile)
  ok(newResolvedApp(resolvedFiles))
