## Phase-A import cluster — `AnalyzedDefImportedType` (an individual
## imported name verified to resolve to a defined type in its source
## file) and `AnalyzedDefImport` (one `import` statement's analyzed
## types + the source-file back-ref). Produced by the facade and
## consumed by phase-A `AnalyzedDefFile` and phase-B `AnalyzedFile`.

import ../resolver/index as resolver

# ---- AnalyzedDefImportedType ----
# Carries the source's ResolvedFile (`impFile`) so the constraint hop
# can look up a contract generic in the DEFINING file's scope — a
# resolver-rung value, deliberately: capturing AnalyzedDefFile or
# ResolvedFileContext here would cycle (both sit above this module).

type AnalyzedDefImportedType* = ref object
  resolved: ResolvedImportedType
  impFile: ResolvedFile
  typ: ResolvedLocalType

proc newAnalyzedDefImportedType*(resolved: ResolvedImportedType, impFile: ResolvedFile, typ: ResolvedLocalType): AnalyzedDefImportedType =
  AnalyzedDefImportedType(resolved: resolved, impFile: impFile, typ: typ)

proc impFile*(impType: AnalyzedDefImportedType): ResolvedFile = impType.impFile
proc typ*(impType: AnalyzedDefImportedType): ResolvedLocalType = impType.typ

# ---- AnalyzedDefImport ----

type AnalyzedDefImport* = ref object
  resolved: ResolvedImport
  importedTypes: seq[AnalyzedDefImportedType]

proc newAnalyzedDefImport*(resolved: ResolvedImport, importedTypes: seq[AnalyzedDefImportedType]): AnalyzedDefImport =
  AnalyzedDefImport(resolved: resolved, importedTypes: importedTypes)

proc importedTypes*(imp: AnalyzedDefImport): seq[AnalyzedDefImportedType] = imp.importedTypes
proc path*(imp: AnalyzedDefImport): string = imp.resolved.file.path
