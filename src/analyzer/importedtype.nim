## AnalyzedImportedType — verifies an individual imported name resolved
## to a defined type in its source file.

import ./resolver

type AnalyzedImportedType* = ref object
  resolved: ResolvedImportedType
  typ: ResolvedType

proc newAnalyzedImportedType*(resolved: ResolvedImportedType, typ: ResolvedType): AnalyzedImportedType =
  AnalyzedImportedType(resolved: resolved, typ: typ)

proc loc*(impType: AnalyzedImportedType): Location = impType.resolved.loc
proc binding*(impType: AnalyzedImportedType): Identifier = impType.resolved.binding
proc typ*(impType: AnalyzedImportedType): ResolvedType = impType.typ
