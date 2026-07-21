## AnalyzedImportDef — bundles the analyzed imported types from one
## `import` statement together with the source-file back-ref.

import ./resolver
import importedtype

type AnalyzedImportDef* = ref object
  resolved: ResolvedImport
  importedTypes: seq[AnalyzedImportedType]

proc newAnalyzedImportDef*(resolved: ResolvedImport, importedTypes: seq[AnalyzedImportedType]): AnalyzedImportDef =
  AnalyzedImportDef(resolved: resolved, importedTypes: importedTypes)

proc importedTypes*(imp: AnalyzedImportDef): seq[AnalyzedImportedType] = imp.importedTypes
proc path*(imp: AnalyzedImportDef): string = imp.resolved.impFile.path
