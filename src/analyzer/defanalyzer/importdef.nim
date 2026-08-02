## Phase-A `AnalyzedDefImport` — bundles the analyzed imported
## types from one `import` statement together with the source-file
## back-ref. Produced by `analyzeImportDefinition` on the facade and
## consumed by both phase-B `AnalyzedFile` (for downstream lookup) and
## phase-A `AnalyzedDefFile` (for building the fileCtx).

import ./resolver
import importedtypedef

type AnalyzedDefImport* = ref object
  resolved: ResolvedImport
  importedTypes: seq[AnalyzedDefImportedType]

proc newAnalyzedDefImport*(resolved: ResolvedImport, importedTypes: seq[AnalyzedDefImportedType]): AnalyzedDefImport =
  AnalyzedDefImport(resolved: resolved, importedTypes: importedTypes)

proc importedTypes*(imp: AnalyzedDefImport): seq[AnalyzedDefImportedType] = imp.importedTypes
proc path*(imp: AnalyzedDefImport): string = imp.resolved.impFile.path
