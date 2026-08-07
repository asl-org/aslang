## AnalyzedFile — per-file result of the analyzer pass. Bundles the
## file's imports and modules alongside the resolver-side back-ref.

import ./defanalyzer
import module
import imports

type AnalyzedFile* = ref object
  def: AnalyzedDefFile
  imports: seq[AnalyzedImport]
  modules: seq[AnalyzedModule]

proc newAnalyzedFile*(def: AnalyzedDefFile, imports: seq[AnalyzedImport], modules: seq[AnalyzedModule]): AnalyzedFile =
  AnalyzedFile(def: def, imports: imports, modules: modules)

proc path*(f: AnalyzedFile): string = f.def.path
