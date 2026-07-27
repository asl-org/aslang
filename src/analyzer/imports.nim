## Phase-A `AnalyzedImport` — bundles the analyzed imported
## types from one `import` statement together with the source-file
## back-ref. Produced by `analyzeImportDefinition` on the facade and
## consumed by both phase-B `AnalyzedFile` (for downstream lookup) and
## phase-A `AnalyzedFileDefinition` (for building the fileScope).

import ./defanalyzer
import importedtype

type AnalyzedImport* = ref object
  def: AnalyzedImportDefinition
  importedTypes: seq[AnalyzedImportedType]

proc newAnalyzedImport*(def: AnalyzedImportDefinition, importedTypes: seq[AnalyzedImportedType]): AnalyzedImport =
  AnalyzedImport(def: def, importedTypes: importedTypes)

proc importedTypes*(imp: AnalyzedImport): seq[AnalyzedImportedType] = imp.importedTypes
proc path*(imp: AnalyzedImport): string = imp.def.path