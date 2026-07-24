## Phase-A `AnalyzedImportDefinition` — bundles the analyzed imported
## types from one `import` statement together with the source-file
## back-ref. Produced by `analyzeImportDefinition` on the facade and
## consumed by both phase-B `AnalyzedFile` (for downstream lookup) and
## phase-A `AnalyzedFileDefinition` (for building the fileScope).

import ./resolver
import importedtype

type AnalyzedImportDefinition* = ref object
  resolved: ResolvedImport
  importedTypes: seq[AnalyzedImportedType]

proc newAnalyzedImportDefinition*(resolved: ResolvedImport, importedTypes: seq[AnalyzedImportedType]): AnalyzedImportDefinition =
  AnalyzedImportDefinition(resolved: resolved, importedTypes: importedTypes)

proc importedTypes*(imp: AnalyzedImportDefinition): seq[AnalyzedImportedType] = imp.importedTypes
proc path*(imp: AnalyzedImportDefinition): string = imp.resolved.impFile.path
