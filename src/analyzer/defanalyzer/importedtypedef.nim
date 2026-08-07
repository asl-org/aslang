## AnalyzedDefImportedType — verifies an individual imported name resolved
## to a defined type in its source file. Carries the source's
## ResolvedFile (`impFile`) so the constraint hop can look up a
## contract generic in the DEFINING file's scope — a resolver-rung
## value, deliberately: capturing AnalyzedDefFile or
## ResolvedFileContext here would cycle (both sit above this module).

import ./resolver

type AnalyzedDefImportedType* = ref object
  resolved: ResolvedImportedType
  impFile: ResolvedFile
  typ: ResolvedLocalType

proc newAnalyzedDefImportedType*(resolved: ResolvedImportedType, impFile: ResolvedFile, typ: ResolvedLocalType): AnalyzedDefImportedType =
  AnalyzedDefImportedType(resolved: resolved, impFile: impFile, typ: typ)

proc impFile*(impType: AnalyzedDefImportedType): ResolvedFile = impType.impFile
proc typ*(impType: AnalyzedDefImportedType): ResolvedLocalType = impType.typ
