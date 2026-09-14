## Resolver app/file cluster — ResolvedFile (a resolved file's scope:
## its name→scope-entry table plus resolved imports + local types with
## identity indexes) and ResolvedApp (the app-level result AND
## accumulator: the parsed App plus every ResolvedFile accumulated so
## far, so import resolution can link a binding to its source file's
## already-resolved types).

import results, sequtils, strformat, hashes, tables

import ../parser/main as parser
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
  id: int
  parsed: parser.File
  imports: seq[ResolvedImport]
  importedTypeIndex: Table[LocalType, ResolvedLocalType]
  localTypes: seq[ResolvedLocalType]
  localTypeIndex: Table[LocalType, int]
  typeIndex: Table[Identifier, Type]

proc insert(file: ResolvedFile, name: Identifier, typ: Type): Result[ResolvedFile, string] =
  if name in file.typeIndex:
    let loc = file.typeIndex[name].loc
    err(fmt"{name.loc} duplicate type declaration encountered, see previous declaration at {loc}")
  else:
    file.typeIndex[name] = typ
    ok(file)

proc newResolvedFile*(id: int, parsed: parser.File): Result[ResolvedFile, string] =
  var file = ResolvedFile(id: id, parsed: parsed)
  for typ in parsed.types:
    file = ? file.insert(typ.name, newType(typ))
  ok(file)

proc add*(file: ResolvedFile, imp: ResolvedImport): Result[ResolvedFile, string] =
  file.imports.add(imp)
  for impType in imp.importedTypes:
    discard ? file.insert(impType.binding, newType(impType))
    file.importedTypeIndex[impType.localType.parsed] = impType.localType
  ok(file)

proc add*(file: ResolvedFile, localType: ResolvedLocalType): Result[ResolvedFile, string] =
  if localType.parsed in file.localTypeIndex:
    err(fmt"[BUG] - {localType.loc} duplicate local type `{localType.name.asl}` in the resolved file")
  else:
    file.localTypeIndex[localType.parsed] = file.localTypes.len
    file.localTypes.add(localType)
    ok(file)

proc id*(file: ResolvedFile): int = file.id
proc path*(file: ResolvedFile): string = file.parsed.path
proc parsed*(file: ResolvedFile): parser.File = file.parsed
proc imports*(file: ResolvedFile): seq[ResolvedImport] = file.imports

proc exportedTypes*(file: ResolvedFile): seq[ResolvedImportedType] =
  file.localTypes.filterIt(it.public).mapIt(newResolvedImportedType(it))
proc localTypes*(file: ResolvedFile): seq[ResolvedLocalType] = file.localTypes

proc findLocalType*(file: ResolvedFile, name: Identifier): Result[LocalType, string] =
  if name in file.typeIndex: ok(file.typeIndex[name].localType)
  else: err(fmt"{name.loc} type `{name.asl}` does not exist in the scope")

proc findModule*(file: ResolvedFile, name: Identifier): Result[Module, string] =
  let initType = ? file.findLocalType(name)
  case initType.kind:
  of ltkGeneric: err(fmt"{name.loc} type `{name.asl}` is a generic and not a module")
  of ltkModule: ok(initType.module)

proc findGeneric*(file: ResolvedFile, name: Identifier): Result[Generic, string] =
  let initType = ? file.findLocalType(name)
  case initType.kind:
  of ltkModule: err(fmt"{name.loc} type `{name.asl}` is a module but expected generic")
  of ltkGeneric: ok(initType.generic)

# Identity lookups — every key handed to these was bound by the
# resolver against this same file, so a miss (or a kind mismatch) is
# a compiler bug, never a user error.
proc findLocalType*(file: ResolvedFile, localType: LocalType): ResolvedLocalType =
  assert(localType in file.localTypeIndex, fmt"[BUG] - {localType.loc} type `{localType.name.asl}` missing from the resolved file")
  file.localTypes[file.localTypeIndex[localType]]

proc findExportedType*(file: ResolvedFile, importedType: ImportedType): Result[ResolvedImportedType, string] =
  let localType = ? file.parsed.findExportedType(importedType.name)
  let resolvedLocalType = file.findLocalType(localType)
  ok(newResolvedImportedType(importedType, resolvedLocalType))

proc findGenericInScope*(file: ResolvedFile, generic: Generic): ResolvedGeneric =
  ## Identity lookup spanning the file's OWN types AND its import
  ## bindings — everything this file's scope can see. Identity keys
  ## (hash-by-loc) make it alias-immune: the file may import the generic
  ## under a different binding name. Serves the constraint hop: a
  ## module's requirement generic is always in its defining file's scope
  ## (the file referenced it to define the module), so a miss is a
  ## compiler bug.
  let localType = newLocalType(generic)
  if localType in file.localTypeIndex:
    return file.localTypes[file.localTypeIndex[localType]].generic
  if localType in file.importedTypeIndex:
    return file.importedTypeIndex[localType].generic
  assert(false, fmt"[BUG] - {generic.loc} generic `{generic.name.asl}` is not in the scope of file `{file.path}`")

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
