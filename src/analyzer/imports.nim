## Phase-B `AnalyzedImport` — one `import` statement's phase-A def
## lifted to its body-level form: each imported type carries the
## source file's AnalyzedLocalType. Produced by `analyzeImport` on
## the body barrel and consumed by `newAnalyzedFileContext` when
## building the per-file AnalyzedFileContext.

import ./defanalyzer
import importedtype

type AnalyzedImport* = ref object
  def: AnalyzedDefImport
  importedTypes: seq[AnalyzedImportedType]

proc newAnalyzedImport*(def: AnalyzedDefImport, importedTypes: seq[AnalyzedImportedType]): AnalyzedImport =
  AnalyzedImport(def: def, importedTypes: importedTypes)

proc importedTypes*(imp: AnalyzedImport): seq[AnalyzedImportedType] = imp.importedTypes
proc path*(imp: AnalyzedImport): string = imp.def.path