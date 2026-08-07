## AnalyzedImportedType — verifies an individual imported name def
## to a defined type in its source file.

import ./defanalyzer

type AnalyzedImportedType* = ref object
  def: AnalyzedDefImportedType
  typ: AnalyzedLocalType

proc newAnalyzedImportedType*(def: AnalyzedDefImportedType, typ: AnalyzedLocalType): AnalyzedImportedType =
  AnalyzedImportedType(def: def, typ: typ)

proc typ*(impType: AnalyzedImportedType): AnalyzedLocalType = impType.typ
