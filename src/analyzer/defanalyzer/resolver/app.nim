## Resolver app/file cluster — ResolvedFile (a resolved file's scope:
## its name→scope-entry table plus resolved imports + local types with
## identity indexes) and ResolvedApp (the app-level result AND
## accumulator: the parsed App plus every ResolvedFile accumulated so
## far, so import resolution can link a binding to its source file's
## already-resolved types).

import results, sequtils, strformat, hashes, tables

import parser
import types
import imports

# ============================================================
# ResolvedFile
# ============================================================
# Per-file resolver scope: the name -> scope-entry table (`Type`, the
# Local | Imported union defined in imports.nim) plus the file's
# resolved imports and local types with an identity index — populated
# by `insert` / `add` as the resolver walks the file. A `Type` entry
# resolves either to a type declared in this file or to a LINKED import
# binding carrying the source file's LocalType.

type ResolvedFile* = ref object
  parsed: parser.File
  imports: seq[ResolvedImport]
  importedTypeIndex: Table[LocalType, ResolvedLocalType]
  localTypes: seq[ResolvedLocalType]
  localTypeIndex: Table[LocalType, int]
  typeIndex: Table[Identifier, Type]

proc insert(fileCtx: ResolvedFile, name: Identifier, typ: Type): Result[ResolvedFile, string] =
  if name in fileCtx.typeIndex:
    let loc = fileCtx.typeIndex[name].loc
    err(fmt"{name.loc} duplicate type declaration encountered, see previous declaration at {loc}")
  else:
    fileCtx.typeIndex[name] = typ
    ok(fileCtx)

proc newResolvedFile*(parsed: parser.File): Result[ResolvedFile, string] =
  var fileCtx = ResolvedFile(parsed: parsed)
  for typ in parsed.types:
    fileCtx = ? fileCtx.insert(typ.name, newType(typ))
  ok(fileCtx)

proc add*(fileCtx: ResolvedFile, imp: ResolvedImport): Result[ResolvedFile, string] =
  fileCtx.imports.add(imp)
  for impType in imp.importedTypes:
    discard ? fileCtx.insert(impType.binding, newType(impType))
    fileCtx.importedTypeIndex[impType.localType.parsed] = impType.localType
  ok(fileCtx)

proc add*(fileCtx: ResolvedFile, localType: ResolvedLocalType): Result[ResolvedFile, string] =
  if localType.parsed in fileCtx.localTypeIndex:
    err(fmt"[BUG] - {localType.loc} duplicate local type `{localType.name.asl}` in the resolved file")
  else:
    fileCtx.localTypeIndex[localType.parsed] = fileCtx.localTypes.len
    fileCtx.localTypes.add(localType)
    ok(fileCtx)

proc findLocalType*(fileCtx: ResolvedFile, name: Identifier): Result[LocalType, string] =
  if name in fileCtx.typeIndex: ok(fileCtx.typeIndex[name].localType)
  else: err(fmt"{name.loc} type `{name.asl}` does not exist in the scope")

proc findModule*(fileCtx: ResolvedFile, name: Identifier): Result[Module, string] =
  let initType = ? fileCtx.findLocalType(name)
  case initType.kind:
  of ltkGeneric: err(fmt"{name.loc} type `{name.asl}` is a generic and not a module")
  of ltkModule: ok(initType.module)

proc findGeneric*(fileCtx: ResolvedFile, name: Identifier): Result[Generic, string] =
  let initType = ? fileCtx.findLocalType(name)
  case initType.kind:
  of ltkModule: err(fmt"{name.loc} type `{name.asl}` is a module but expected generic")
  of ltkGeneric: ok(initType.generic)

proc path*(fileCtx: ResolvedFile): string = fileCtx.parsed.path
proc parsed*(fileCtx: ResolvedFile): parser.File = fileCtx.parsed
proc imports*(fileCtx: ResolvedFile): seq[ResolvedImport] = fileCtx.imports

proc modules*(fileCtx: ResolvedFile): seq[ResolvedModule] =
  fileCtx.localTypes.filterIt(it.kind == rltkModule).mapIt(it.module)
proc exportedTypes*(fileCtx: ResolvedFile): seq[ResolvedImportedType] =
  fileCtx.localTypes.filterIt(it.public).mapIt(newResolvedImportedType(it))
proc localTypes*(fileCtx: ResolvedFile): seq[ResolvedLocalType] = fileCtx.localTypes

# Identity lookups — every key handed to these was bound by the
# resolver against this same file, so a miss (or a kind mismatch) is
# a compiler bug, never a user error.
proc findLocalType*(fileCtx: ResolvedFile, localType: LocalType): ResolvedLocalType =
  assert(localType in fileCtx.localTypeIndex, fmt"[BUG] - {localType.loc} type `{localType.name.asl}` missing from the resolved file")
  fileCtx.localTypes[fileCtx.localTypeIndex[localType]]

proc findModule*(fileCtx: ResolvedFile, typ: Module): ResolvedModule =
  let resolvedLocalType = fileCtx.findLocalType(newLocalType(typ))
  assert(resolvedLocalType.kind == rltkModule, fmt"[BUG] - {typ.loc} `{typ.name.asl}` was bound as a module by the resolver")
  resolvedLocalType.module

proc findGeneric*(fileCtx: ResolvedFile, typ: Generic): ResolvedGeneric =
  let resolvedLocalType = fileCtx.findLocalType(newLocalType(typ))
  assert(resolvedLocalType.kind == rltkGeneric, fmt"[BUG] - {typ.loc} `{typ.name.asl}` was bound as a generic by the resolver")
  resolvedLocalType.generic

proc findExportedType*(fileCtx: ResolvedFile, importedType: ImportedType): Result[ResolvedImportedType, string] =
  let localType = ? fileCtx.parsed.findExportedType(importedType.name)
  let resolvedLocalType = fileCtx.findLocalType(localType)
  ok(newResolvedImportedType(importedType, resolvedLocalType))

proc findGenericInScope*(fileCtx: ResolvedFile, generic: Generic): ResolvedGeneric =
  ## Identity lookup spanning the file's OWN types AND its import
  ## bindings — everything this file's scope can see. Identity keys
  ## (hash-by-loc) make it alias-immune: the file may import the generic
  ## under a different binding name. Serves the constraint hop: a
  ## module's requirement generic is always in its defining file's scope
  ## (the file referenced it to define the module), so a miss is a
  ## compiler bug.
  let localType = newLocalType(generic)
  if localType in fileCtx.localTypeIndex:
    return fileCtx.localTypes[fileCtx.localTypeIndex[localType]].generic
  if localType in fileCtx.importedTypeIndex:
    return fileCtx.importedTypeIndex[localType].generic
  assert(false, fmt"[BUG] - {generic.loc} generic `{generic.name.asl}` is not in the scope of file `{fileCtx.path}`")

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

proc files*(app: ResolvedApp): seq[ResolvedFile] = app.files

proc add*(app: ResolvedApp, file: ResolvedFile) =
  assert(file.path notin app.filePathIndex, fmt"[BUG] - duplicate file `{file.path}` in the app context")
  app.filePathIndex[file.path] = app.files.len

  assert(file.parsed notin app.fileIndex, fmt"[BUG] - duplicate file `{file.path}` in the app context")
  app.fileIndex[file.parsed] = app.files.len

  app.files.add(file)

proc findFile*(app: ResolvedApp, file: parser.File): ResolvedFile =
  ## Identity lookup — the resolver resolved every file the loader
  ## produced, so a miss is a compiler bug.
  assert(file in app.fileIndex, fmt"[BUG] - file `{file.path}` missing from the resolved app")
  app.files[app.fileIndex[file]]

proc findImportedFile*(app: ResolvedApp, path: string): ResolvedFile =
  ## Identity lookup — topo order (BFS leaves-first) guarantees every
  ## import's source file was resolved before its importer, so a miss
  ## is a compiler bug.
  assert(path in app.filePathIndex, fmt"[BUG] - file `{path}` not resolved before its importer")
  app.files[app.filePathIndex[path]]
