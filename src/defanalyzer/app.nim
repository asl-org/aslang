## Phase-A app/file cluster — AnalyzedDefFile (a file's analyzed imports
## + defined types + its ResolvedFileContext scope), AnalyzedDefApp (the
## top-level phase-A result: every file's def bundle, path-indexed), and
## ResolvedAppContext (the def analyzer's app-level accumulator wrapping
## the resolved app).

import sequtils, strformat, tables

import ../resolver/index as resolver
import ./context
import ./types
import ./importdef

# ============================================================
# AnalyzedDefFile
# ============================================================
# Per-file bundle: analyzed imports + defined types, the identity-keyed
# ResolvedFileContext (`scope`), and a local-only definedTypeIndex
# (ResolvedLocalType -> AnalyzedLocalType) behind findType / findModule.
# The local index deliberately excludes imports — analyzeImportedType
# uses it to verify an imported name is DEFINED in its source file.

proc buildTypeIndex(types: seq[AnalyzedLocalType]): Table[ResolvedLocalType, AnalyzedLocalType] =
  var typeIndex: Table[ResolvedLocalType, AnalyzedLocalType]
  for typ in types:
    assert(typ.resolved notin typeIndex, fmt"[BUG] - {typ.loc} duplicate defined type `{typ.name.asl}` in the file def")
    typeIndex[typ.resolved] = typ
  return typeIndex

type AnalyzedDefFile* = ref object
  resolved: ResolvedFile
  imports: seq[AnalyzedDefImport]
  types: seq[AnalyzedLocalType]
  scope: ResolvedFileContext
  definedTypeIndex: Table[ResolvedLocalType, AnalyzedLocalType]

proc newAnalyzedDefFile*(resolved: ResolvedFile, imports: seq[AnalyzedDefImport], types: seq[AnalyzedLocalType], scope: ResolvedFileContext): AnalyzedDefFile =
  let definedTypeIndex = buildTypeIndex(types)
  AnalyzedDefFile(resolved: resolved, imports: imports, types: types, scope: scope, definedTypeIndex: definedTypeIndex)

proc path*(f: AnalyzedDefFile): string = f.resolved.path
proc imports*(f: AnalyzedDefFile): seq[AnalyzedDefImport] = f.imports
proc types*(f: AnalyzedDefFile): seq[AnalyzedLocalType] = f.types
proc modules*(file: AnalyzedDefFile): seq[AnalyzedDefModule] =
  file.types.filterIt(it.kind == altkModule).mapIt(it.module)
proc generics*(file: AnalyzedDefFile): seq[AnalyzedGeneric] =
  file.types.filterIt(it.kind == altkGeneric).mapIt(it.generic)

# Identity lookups — phase A analyzed every type DEFINED in this
# file (local-only by design), so a miss is a compiler bug.
proc findType*(fileDef: AnalyzedDefFile, typ: ResolvedLocalType): AnalyzedLocalType =
  assert(typ in fileDef.definedTypeIndex, fmt"[BUG] - {typ.loc} type `{typ.name.asl}` missing from the file def")
  fileDef.definedTypeIndex[typ]

proc findModule*(fileDef: AnalyzedDefFile, module: ResolvedModule): AnalyzedDefModule =
  let foundType = fileDef.findType(newResolvedLocalType(module))
  assert(foundType.kind == altkModule, fmt"[BUG] - {module.loc} `{module.name.asl}` was analyzed as a module in phase A")
  foundType.module

# ============================================================
# AnalyzedDefApp
# ============================================================
# The top-level phase-A result: resolved app + every file's
# AnalyzedDefFile, indexed by absolute path for cross-file findFileDef.

type AnalyzedDefApp* = ref object
  resolved: ResolvedApp
  fileDefs: seq[AnalyzedDefFile]
  fileDefIndex: Table[string, int]

proc newAnalyzedDefApp*(resolved: ResolvedApp,
    fileDefs: seq[AnalyzedDefFile]): AnalyzedDefApp =
  var fileDefIndex: Table[string, int]
  for index, fileDef in fileDefs:
    assert(fileDef.path notin fileDefIndex, fmt"[BUG] - duplicate file def `{fileDef.path}` in the app def")
    fileDefIndex[fileDef.path] = index
  AnalyzedDefApp(resolved: resolved, fileDefs: fileDefs, fileDefIndex: fileDefIndex)

proc fileDefs*(a: AnalyzedDefApp): seq[AnalyzedDefFile] = a.fileDefs

proc findFileDef*(appDef: AnalyzedDefApp, path: string): AnalyzedDefFile =
  ## Identity lookup — phase A produced a file def for every resolved
  ## file, so a miss is a compiler bug.
  assert(path in appDef.fileDefIndex, fmt"[BUG] - file `{path}` missing from the app def")
  appDef.fileDefs[appDef.fileDefIndex[path]]

# ============================================================
# ResolvedAppContext
# ============================================================
# The def analyzer's app-level context: the resolved app plus every
# AnalyzedDefFile accumulated so far. The rung-2 twin of ResolvedApp.

type ResolvedAppContext* = ref object
  resolved: ResolvedApp
  fileDefs: seq[AnalyzedDefFile]
  fileDefIndex: Table[string, int]

proc newResolvedAppContext*(resolved: ResolvedApp): ResolvedAppContext =
  ResolvedAppContext(resolved: resolved)

proc files*(appCtx: ResolvedAppContext): seq[ResolvedFile] = appCtx.resolved.files
proc fileDefs*(appCtx: ResolvedAppContext): seq[AnalyzedDefFile] = appCtx.fileDefs

proc findFile*(appCtx: ResolvedAppContext, file: parser.File): ResolvedFile =
  appCtx.resolved.findFile(file)

proc add*(appCtx: ResolvedAppContext, fileDef: AnalyzedDefFile) =
  assert(fileDef.path notin appCtx.fileDefIndex, fmt"[BUG] - duplicate file def `{fileDef.path}` in the app context")
  appCtx.fileDefIndex[fileDef.path] = appCtx.fileDefs.len
  appCtx.fileDefs.add(fileDef)
