## AnalyzedImportedTypeDef — verifies an individual imported name resolved
## to a defined type in its source file.

import ./resolver

type AnalyzedImportedTypeDef* = ref object
  resolved: ResolvedImportedType
  typ: ResolvedType

proc newAnalyzedImportedTypeDef*(resolved: ResolvedImportedType, typ: ResolvedType): AnalyzedImportedTypeDef =
  AnalyzedImportedTypeDef(resolved: resolved, typ: typ)

proc loc*(impType: AnalyzedImportedTypeDef): Location = impType.resolved.loc
proc binding*(impType: AnalyzedImportedTypeDef): Identifier = impType.resolved.binding
proc typ*(impType: AnalyzedImportedTypeDef): ResolvedType = impType.typ
