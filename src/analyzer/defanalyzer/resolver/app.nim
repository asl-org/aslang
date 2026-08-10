## Resolver app/file cluster — ResolvedFile (a resolved file's types +
## imports with identity-keyed lookups) and ResolvedApp (the app-level
## result AND accumulator: the parsed App plus every ResolvedFile
## accumulated so far, so import resolution can link a binding to its
## source file's already-resolved types).

import results, strformat, tables

import parser
import types
import imports
import context

# ============================================================
# ResolvedFile
# ============================================================

type ResolvedFile* = ref object
  context: FileContext
  parsed: parser.File
  imports: seq[ResolvedImport]
  types: seq[ResolvedLocalType]
  typeIndex: Table[parser.LocalType, int]

proc newResolvedFile*(parsed: parser.File, imports: seq[ResolvedImport], types: seq[ResolvedLocalType], context: FileContext): ResolvedFile =
  var typeIndex: Table[parser.LocalType, int]
  for id, typ in types:
    assert(typ.parsed notin typeIndex, fmt"[BUG] - {typ.loc} duplicate local type `{typ.name.asl}` in the resolved file")
    typeIndex[typ.parsed] = id
  ResolvedFile(context: context, parsed: parsed, imports: imports, types: types, typeIndex: typeIndex)

proc path*(file: ResolvedFile): string = file.context.path
proc parsed*(file: ResolvedFile): parser.File = file.context.parsed
proc imports*(file: ResolvedFile): seq[ResolvedImport] = file.context.imports
proc types*(file: ResolvedFile): seq[ResolvedLocalType] = file.context.localTypes
proc modules*(file: ResolvedFile): seq[ResolvedModule] = file.context.modules
proc exportedTypes*(file: ResolvedFile): seq[ResolvedImportedType] = file.context.exportedTypes
proc importedBindings(file: ResolvedFile): seq[ResolvedImportedType] = file.context.importedBindings

# Identity lookups — every key handed to these was bound by the
# resolver against this same file, so a miss (or a kind mismatch) is
# a compiler bug, never a user error.
proc findType*(file: ResolvedFile, localType: parser.LocalType): ResolvedLocalType = file.context.findLocalType(localType)
proc findModule*(file: ResolvedFile, module: Module): ResolvedModule = file.context.findModule(module)
proc findGeneric*(file: ResolvedFile, generic: Generic): ResolvedGeneric = file.context.findGeneric(generic)
proc findExportedType*(file: ResolvedFile, importedType: ImportedType): Result[ResolvedImportedType, string] = file.context.findExportedType(importedType)
proc findGenericInScope*(file: ResolvedFile, typ: Generic): ResolvedGeneric = file.context.findGenericInScope(typ)

# ============================================================
# ResolvedApp
# ============================================================
# The app-level result AND accumulator. The rung-1 base of the app
# ladder — ResolvedAppContext (def analyzer) and AnalyzedAppContext
# (analyzer) wrap it in turn.

type ResolvedApp* = ref object
  parsed: App
  files: seq[ResolvedFile]
  fileIndex: Table[parser.File, int]
  filePathIndex: Table[string, int]

proc newResolvedApp*(parsed: App): ResolvedApp =
  ResolvedApp(parsed: parsed)

proc files*(appCtx: ResolvedApp): seq[ResolvedFile] = appCtx.files

proc add*(appCtx: ResolvedApp, file: ResolvedFile) =
  assert(file.path notin appCtx.filePathIndex, fmt"[BUG] - duplicate file `{file.path}` in the app context")
  appCtx.filePathIndex[file.path] = appCtx.files.len

  assert(file.parsed notin appCtx.fileIndex, fmt"[BUG] - duplicate file `{file.path}` in the app context")
  appCtx.fileIndex[file.parsed] = appCtx.files.len

  appCtx.files.add(file)

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
