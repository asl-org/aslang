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

import ./defanalyzer
import module
import imports

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

# ---- AnalyzedApp ----

type AnalyzedApp* = ref object
  def: AnalyzedDefApp
  files: seq[AnalyzedFile]

proc newAnalyzedApp*(def: AnalyzedDefApp, files: seq[AnalyzedFile]): AnalyzedApp =
  AnalyzedApp(def: def, files: files)

proc files*(app: AnalyzedApp): seq[AnalyzedFile] = app.files