## Phase-A `AnalyzedFileDefinition` — per-file bundle of the file's
## analyzed imports + defined types, plus the fileScope
## (Identifier → ResolvedType) and definedTypeIndex (Identifier →
## AnalyzedDefinedType).
##
## Phase B consumes `definedTypeIndex` as the per-file defScope,
## augments it with cross-file imports at analyzeFile time, and
## dispatches call-site lookups against the analyzed module/generic
## defs.

import results, strformat, tables

import ./resolver
import ./filescope
import ./definedtype
import ./importdef

type AnalyzedFileDefinition* = ref object
  resolved: ResolvedFile
  imports: seq[AnalyzedImportDefinition]
  types: seq[AnalyzedDefinedType]
  scope: ResolvedFileScope
  definedTypeIndex: AnalyzedDefinedTypeScope

proc newAnalyzedFileDefinition*(resolved: ResolvedFile,
    imports: seq[AnalyzedImportDefinition],
    types: seq[AnalyzedDefinedType],
    scope: ResolvedFileScope): AnalyzedFileDefinition =
  var definedTypeIndex: AnalyzedDefinedTypeScope
  for definedType in types:
    definedTypeIndex[definedType.name] = definedType
  AnalyzedFileDefinition(resolved: resolved, imports: imports,
    types: types, scope: scope, definedTypeIndex: definedTypeIndex)

proc resolved*(f: AnalyzedFileDefinition): ResolvedFile = f.resolved
proc path*(f: AnalyzedFileDefinition): string = f.resolved.path
proc imports*(f: AnalyzedFileDefinition): seq[AnalyzedImportDefinition] = f.imports
proc types*(f: AnalyzedFileDefinition): seq[AnalyzedDefinedType] = f.types
proc scope*(f: AnalyzedFileDefinition): ResolvedFileScope = f.scope
proc definedTypeIndex*(f: AnalyzedFileDefinition): AnalyzedDefinedTypeScope =
  f.definedTypeIndex

proc findDefinedType*(fileDef: AnalyzedFileDefinition, name: Identifier): Result[AnalyzedDefinedType, string] =
  if name notin fileDef.definedTypeIndex:
    err(fmt"{name.loc} file `{fileDef.path}` does not define a type named `{name.asl}`")
  else:
    ok(fileDef.definedTypeIndex[name])
