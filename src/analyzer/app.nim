## Phase-B app cluster — AnalyzedFile (per-file imports + modules with
## the resolver-side back-ref) and AnalyzedApp (the top-level container
## returned by `analyze`).
##
## Post-6c the analyzer has no separate def-level pass — every
## definition-level index and accessor is carried directly on the
## resolver's ResolvedApp / ResolvedFile / ResolvedModule / ResolvedGeneric
## / ResolvedStructDef / ResolvedUnionDef / ResolvedVariantDef. The facade's
## `analyze` walks the app tree file-by-file, seeds each file's scope
## from imports + local defined types, and drives per-module body
## analysis. Extern functions have no body to analyze — the walker
## skips them at the function layer.

import results, strformat, tables

import defanalyzer
import module
import imports
import function

# ---- AnalyzedFile ----
# Per-file result of the analyzer pass: the file's imports and modules
# alongside the resolver-side back-ref.

type AnalyzedFile* = ref object
  def: AnalyzedDefFile
  imports: seq[AnalyzedImport]
  modules: seq[AnalyzedModule]

proc newAnalyzedFile*(def: AnalyzedDefFile, imports: seq[AnalyzedImport], modules: seq[AnalyzedModule]): AnalyzedFile =
  AnalyzedFile(def: def, imports: imports, modules: modules)

proc path*(f: AnalyzedFile): string = f.def.path
proc modules*(f: AnalyzedFile): seq[AnalyzedModule] = f.modules

# The program entry point — a whole-program requirement applied by the
# CLI compile, deliberately NOT part of `analyze` (feature-level fixtures
# resolve/analyze snippets that have no entry point).
type EntryPoint* = ref object
  file: AnalyzedFile
  module: AnalyzedModule
  function: AnalyzedFunction

proc newEntryPoint(file: AnalyzedFile, module: AnalyzedModule, function: AnalyzedFunction): EntryPoint =
  EntryPoint(file: file, module: module, function: function)

proc function*(entry: EntryPoint): AnalyzedFunction = entry.function

# ---- AnalyzedApp ----

type AnalyzedApp* = ref object
  def: AnalyzedDefApp
  files: seq[AnalyzedFile]
  moduleIndex: Table[AnalyzedDefModule, AnalyzedModule]

proc newAnalyzedApp*(def: AnalyzedDefApp, files: seq[AnalyzedFile]): AnalyzedApp =
  # NOTE: Dissolve file level barrier for analyzed modules
  var moduleIndex: Table[AnalyzedDefModule, AnalyzedModule]
  for file in files:
    for module in file.modules:
      assert(module.def notin moduleIndex, "[BUG] - duplicate module def found")
      moduleIndex[module.def] = module

  AnalyzedApp(def: def, files: files, moduleIndex: moduleIndex)

proc files*(app: AnalyzedApp): seq[AnalyzedFile] = app.files

proc entry*(app: AnalyzedApp): Result[EntryPoint, string] =
  ## The root file (topo order puts it last) must expose exactly one
  ## public module with `public func start(): i32` (the `entry` predicate).
  var entrypoints: seq[EntryPoint]
  let entryFile = app.files[^1]
  for module in entryFile.modules:
    if module.public:
      for function in module.functions:
        if function.entry:
          entrypoints.add(newEntryPoint(entryFile, module, function))
  if entrypoints.len != 1:
    err(fmt"{entryFile.path} expected file to contain one public module with `public func start(): i32` but found {entrypoints.len}")
  else:
    ok(entrypoints[0])

proc findModule*(app: AnalyzedApp, module: AnalyzedDefModule): AnalyzedModule =
  assert(module in app.moduleIndex, "[BUG] - module does not exist in the module index")
  app.moduleIndex[module]