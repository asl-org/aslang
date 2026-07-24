## AnalyzedFile — per-file result of the analyzer pass. Bundles the
## file's imports and modules alongside the resolver-side back-ref.

import ./resolver
import importdef
import module

type AnalyzedFile* = ref object
  resolved: ResolvedFile
  imports: seq[AnalyzedImportDefinition]
  modules: seq[AnalyzedModule]

proc newAnalyzedFile*(resolved: ResolvedFile, imports: seq[AnalyzedImportDefinition], modules: seq[AnalyzedModule]): AnalyzedFile =
  AnalyzedFile(resolved: resolved, imports: imports, modules: modules)

proc resolved*(f: AnalyzedFile): ResolvedFile = f.resolved
proc path*(f: AnalyzedFile): string = f.resolved.path
proc imports*(f: AnalyzedFile): seq[AnalyzedImportDefinition] = f.imports
proc modules*(f: AnalyzedFile): seq[AnalyzedModule] = f.modules
