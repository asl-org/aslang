## AnalyzedImportedType — verifies an individual imported name def
## to a defined type in its source file.

import ./defanalyzer

type AnalyzedImportedType* = ref object
  def: AnalyzedImportedTypeDef
  typ: AnalyzedDefinedType

proc newAnalyzedImportedType*(def: AnalyzedImportedTypeDef, typ: AnalyzedDefinedType): AnalyzedImportedType =
  AnalyzedImportedType(def: def, typ: typ)

proc loc*(impType: AnalyzedImportedType): Location = impType.def.loc
proc binding*(impType: AnalyzedImportedType): Identifier = impType.def.binding
proc typ*(impType: AnalyzedImportedType): AnalyzedDefinedType = impType.typ
