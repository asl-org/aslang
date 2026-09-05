## Phase-B import cluster — `AnalyzedImportedType` (an imported name
## lifted to its body-level AnalyzedLocalType) and `AnalyzedImport` (one
## `import` statement's imported types). Produced by `analyzeImport` on
## the body barrel and consumed by `newAnalyzedFileContext`.

import ../defanalyzer/index as defanalyzer

# ---- AnalyzedImportedType ----

type AnalyzedImportedType* = ref object
  def: AnalyzedDefImportedType
  typ: AnalyzedLocalType

proc newAnalyzedImportedType*(def: AnalyzedDefImportedType, typ: AnalyzedLocalType): AnalyzedImportedType =
  AnalyzedImportedType(def: def, typ: typ)

proc typ*(impType: AnalyzedImportedType): AnalyzedLocalType = impType.typ

# ---- AnalyzedImport ----

type AnalyzedImport* = ref object
  def: AnalyzedDefImport
  importedTypes: seq[AnalyzedImportedType]

proc newAnalyzedImport*(def: AnalyzedDefImport, importedTypes: seq[AnalyzedImportedType]): AnalyzedImport =
  AnalyzedImport(def: def, importedTypes: importedTypes)

proc importedTypes*(imp: AnalyzedImport): seq[AnalyzedImportedType] = imp.importedTypes