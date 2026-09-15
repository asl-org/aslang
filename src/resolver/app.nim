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

type FileContext* = ref object
  app: App
  id: int
  file: parser.File
  importedTypeIndex: Table[Identifier, LocalType]

proc newFileContext*(app: App, id: int, file: parser.File): FileContext =
  FileContext(app: app, id: id, file: file)

proc id*(context: FileContext): int = context.id

proc findType*(context: FileContext, name: Identifier): Result[LocalType, string] =
  let maybeLocalType = context.file.findType(name)
  if maybeLocalType.isOk:
    ok(maybeLocalType.get)
  elif name in context.importedTypeIndex:
    ok(context.importedTypeIndex[name])
  else:
    err(fmt"{name.loc} type `{name.asl}` is not defined in file `{context.file.path}`")

proc add*(context: FileContext, imp: ResolvedImport): Result[FileContext, string] =
  for impType in imp.importedTypes:
    let maybeType = context.findType(impType.binding)
    if maybeType.isOk:
      return err(fmt"{impType.binding.loc} duplicate type declaration encountered, see previous declaration at {maybeType.get.loc}")
    context.importedTypeIndex[impType.binding] = impType.localType.parsed
  ok(context)

proc findModule*(context: FileContext, name: Identifier): Result[Module, string] =
  let typ = ? context.findType(name)
  case typ.kind:
  of ltkGeneric: err(fmt"{name.loc} type `{name.asl}` is a generic and not a module")
  of ltkModule: ok(typ.module)

proc findGeneric*(context: FileContext, name: Identifier): Result[Generic, string] =
  let typ = ? context.findType(name)
  case typ.kind:
  of ltkModule: err(fmt"{name.loc} type `{name.asl}` is a module but expected generic")
  of ltkGeneric: ok(typ.generic)

# ============================================================
# ResolvedFile
# ============================================================
# A file's resolved result: its resolved imports and local types, each
# kept behind an identity index (hash-by-loc) so later phases can look a
# type up by the parsed LocalType the resolver bound it to. Built in one
# shot from the fully-resolved imports + local types (see newResolvedFile);
# name-based scope resolution during the resolve pass lives on FileContext.

type ResolvedFile* = ref object
  id: int
  parsed: parser.File
  imports: seq[ResolvedImport]
  importedTypeIndex: Table[LocalType, ResolvedLocalType]
  localTypes: seq[ResolvedLocalType]
  localTypeIndex: Table[LocalType, int]

proc newResolvedFile*(id: int, parsed: parser.File, imports: seq[ResolvedImport], localTypes: seq[ResolvedLocalType]): Result[ResolvedFile, string] =
  var importedTypeIndex: Table[LocalType, ResolvedLocalType]
  for imp in imports:
    for impType in imp.importedTypes:
      importedTypeIndex[impType.localType.parsed] = impType.localType

  var localTypeIndex: Table[LocalType, int]
  for index, localType in localTypes:
    assert(localType.parsed notin localTypeIndex, fmt"[BUG] - {localType.loc} duplicate local type `{localType.name.asl}` in the resolved file")
    localTypeIndex[localType.parsed] = index
  ok(ResolvedFile(id: id, parsed: parsed, imports: imports, importedTypeIndex: importedTypeIndex, localTypes: localTypes, localTypeIndex: localTypeIndex))

proc id*(file: ResolvedFile): int = file.id
proc path*(file: ResolvedFile): string = file.parsed.path
proc parsed*(file: ResolvedFile): parser.File = file.parsed
proc imports*(file: ResolvedFile): seq[ResolvedImport] = file.imports

proc exportedTypes*(file: ResolvedFile): seq[ResolvedImportedType] =
  file.localTypes.filterIt(it.public).mapIt(newResolvedImportedType(it))
proc localTypes*(file: ResolvedFile): seq[ResolvedLocalType] = file.localTypes

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
# ladder — the def analyzer's ResolvedAppContext wraps it; phase B walks
# the AnalyzedDefApp directly (no analyzer-side app context).

type ResolvedApp* = ref object
  parsed: App
  files: seq[ResolvedFile]
  fileIndex: Table[string, int]

proc newResolvedApp*(parsed: App): ResolvedApp = ResolvedApp(parsed: parsed)

proc parsed*(app: ResolvedApp): App = app.parsed
proc files*(app: ResolvedApp): seq[ResolvedFile] = app.files

proc add*(app: ResolvedApp, file: ResolvedFile) =
  assert(file.path notin app.fileIndex, fmt"[BUG] - duplicate file `{file.path}` in the app context")
  app.fileIndex[file.path] = app.files.len
  app.files.add(file)

proc findFile*(app: ResolvedApp, path: string): ResolvedFile =
  assert(path in app.fileIndex, fmt"[BUG] - file `{path}` not resolved before its importer")
  app.files[app.fileIndex[path]]
