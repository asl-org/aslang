## Phase-B `AnalyzedImport` — one `import` statement's phase-A def
## lifted to its body-level form: each imported type carries the
## source file's AnalyzedDefinedType. Produced by `analyzeImport` on
## the body barrel and consumed by `newAnalyzedFileScope` when
## building the per-file AnalyzedFileScope.

import ./defanalyzer
import importedtype

type AnalyzedImport* = ref object
  def: AnalyzedImportDefinition
  importedTypes: seq[AnalyzedImportedType]

proc newAnalyzedImport*(def: AnalyzedImportDefinition, importedTypes: seq[AnalyzedImportedType]): AnalyzedImport =
  AnalyzedImport(def: def, importedTypes: importedTypes)

proc importedTypes*(imp: AnalyzedImport): seq[AnalyzedImportedType] = imp.importedTypes
proc path*(imp: AnalyzedImport): string = imp.def.path