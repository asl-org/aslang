## Resolver app/file cluster — ResolvedFile (a resolved file's types +
## imports with identity-keyed lookups) and ResolvedApp (the app-level
## result AND accumulator: the parsed App plus every ResolvedFile
## accumulated so far, so import resolution can link a binding to its
## source file's already-resolved types).

import results, sequtils, strformat, tables

import parser
import types
import imports

# ============================================================
# ResolvedFile
# ============================================================

type ResolvedFile* = ref object
  parsed: parser.File
  imports: seq[ResolvedImport]
  types: seq[ResolvedLocalType]
  typeIndex: Table[parser.LocalType, int]

proc newResolvedFile*(parsed: parser.File, imports: seq[ResolvedImport], types: seq[ResolvedLocalType]): ResolvedFile =
  var typeIndex: Table[parser.LocalType, int]
  for id, typ in types:
    assert(typ.parsed notin typeIndex, fmt"[BUG] - {typ.loc} duplicate local type `{typ.name.asl}` in the resolved file")
    typeIndex[typ.parsed] = id
  ResolvedFile(parsed: parsed, imports: imports, types: types, typeIndex: typeIndex)

proc path*(file: ResolvedFile): string = file.parsed.path
proc parsed*(file: ResolvedFile): parser.File = file.parsed
proc imports*(file: ResolvedFile): seq[ResolvedImport] = file.imports
proc types*(file: ResolvedFile): seq[ResolvedLocalType] = file.types
proc modules*(file: ResolvedFile): seq[ResolvedModule] =
  file.types.filterIt(it.kind == rltkModule).mapIt(it.module)
proc exportedTypes*(file: ResolvedFile): seq[ResolvedImportedType] =
  file.types.filterIt(it.public).mapIt(newResolvedImportedType(it))

# Identity lookups — every key handed to these was bound by the
# resolver against this same file, so a miss (or a kind mismatch) is
# a compiler bug, never a user error.
proc findType*(file: ResolvedFile, typ: parser.LocalType): ResolvedLocalType =
  assert(typ in file.typeIndex, fmt"[BUG] - {typ.loc} type `{typ.name.asl}` missing from the resolved file")
  file.types[file.typeIndex[typ]]

proc findModule*(file: ResolvedFile, typ: Module): ResolvedModule =
  let resolvedType = file.findType(newLocalType(typ))
  assert(resolvedType.kind == rltkModule, fmt"[BUG] - {typ.loc} `{typ.name.asl}` was bound as a module by the resolver")
  resolvedType.module

proc findGeneric*(file: ResolvedFile, typ: Generic): ResolvedGeneric =
  let resolvedType = file.findType(newLocalType(typ))
  assert(resolvedType.kind == rltkGeneric, fmt"[BUG] - {typ.loc} `{typ.name.asl}` was bound as a generic by the resolver")
  resolvedType.generic

proc importedBindings(file: ResolvedFile): seq[ResolvedImportedType] =
  var bindings: seq[ResolvedImportedType]
  for imp in file.imports:
    bindings.add(imp.importedTypes)
  bindings

proc findGenericInScope*(file: ResolvedFile, typ: Generic): ResolvedGeneric =
  ## Identity lookup spanning the file's OWN types AND its import
  ## bindings — everything this file's scope can see. Identity keys
  ## (hash-by-loc) make it alias-immune: the file may import the
  ## generic under a different binding name. Serves the constraint
  ## hop: a module's requirement generic is always in its defining
  ## file's scope (the file referenced it to define the module), so
  ## a miss is a compiler bug.
  let parsed = newLocalType(typ)
  if parsed in file.typeIndex:
    return file.findGeneric(typ)
  for impType in file.importedBindings:
    if impType.typ == parsed:
      return impType.localType.generic
  assert(false, fmt"[BUG] - {typ.loc} generic `{typ.name.asl}` is not in the scope of file `{file.path}`")

proc findExportedType*(file: ResolvedFile, importedType: ImportedType): Result[ResolvedImportedType, string] =
  let localType = ? file.parsed.findExportedType(importedType.name)
  let resolvedLocalType = file.findType(localType)
  ok(newResolvedImportedType(importedType, resolvedLocalType))

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
