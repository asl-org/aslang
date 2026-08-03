## AnalyzedDefImportedType — verifies an individual imported name resolved
## to a defined type in its source file.

import ./resolver

type AnalyzedDefImportedType* = ref object
  resolved: ResolvedImportedType
  typ: ResolvedLocalType

proc newAnalyzedDefImportedType*(resolved: ResolvedImportedType, typ: ResolvedLocalType): AnalyzedDefImportedType =
  AnalyzedDefImportedType(resolved: resolved, typ: typ)

proc loc*(impType: AnalyzedDefImportedType): Location = impType.resolved.loc
proc binding*(impType: AnalyzedDefImportedType): Identifier = impType.resolved.binding
proc typ*(impType: AnalyzedDefImportedType): ResolvedLocalType = impType.typ
