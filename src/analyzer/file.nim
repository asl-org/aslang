## AnalyzedFile — per-file result of the analyzer pass. Bundles the
## file's imports and modules alongside the resolver-side back-ref.

import ./defanalyzer
import module

type AnalyzedFile* = ref object
  def: AnalyzedDefFile
  imports: seq[AnalyzedDefImport]
  modules: seq[AnalyzedModule]

proc newAnalyzedFile*(def: AnalyzedDefFile, imports: seq[AnalyzedDefImport], modules: seq[AnalyzedModule]): AnalyzedFile =
  AnalyzedFile(def: def, imports: imports, modules: modules)

proc def*(f: AnalyzedFile): AnalyzedDefFile = f.def
proc path*(f: AnalyzedFile): string = f.def.path
proc imports*(f: AnalyzedFile): seq[AnalyzedDefImport] = f.imports
proc modules*(f: AnalyzedFile): seq[AnalyzedModule] = f.modules
