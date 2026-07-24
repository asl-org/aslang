## Phase-A `AnalyzedFileDefinition` — per-file bundle of the file's
## analyzed imports + defined types, plus the per-file fileScope
## (name-keyed, for initial name lookups) and a name-keyed
## definedTypeIndex used only for the local `findDefinedType(name)`
## path.
##
## Cross-file / identity-based lookups go through
## `AnalyzedAppDefinition.findDefinedType(ResolvedType)` at the app
## level — this per-file index only serves the "user typed this name
## in *this* file" query.

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
  definedTypeIndex: Table[Identifier, AnalyzedDefinedType]

proc newAnalyzedFileDefinition*(resolved: ResolvedFile,
    imports: seq[AnalyzedImportDefinition],
    types: seq[AnalyzedDefinedType],
    scope: ResolvedFileScope): AnalyzedFileDefinition =
  var definedTypeIndex: Table[Identifier, AnalyzedDefinedType]
  for definedType in types:
    definedTypeIndex[definedType.name] = definedType
  AnalyzedFileDefinition(resolved: resolved, imports: imports,
    types: types, scope: scope, definedTypeIndex: definedTypeIndex)

proc resolved*(f: AnalyzedFileDefinition): ResolvedFile = f.resolved
proc path*(f: AnalyzedFileDefinition): string = f.resolved.path
proc imports*(f: AnalyzedFileDefinition): seq[AnalyzedImportDefinition] = f.imports
proc types*(f: AnalyzedFileDefinition): seq[AnalyzedDefinedType] = f.types
proc scope*(f: AnalyzedFileDefinition): ResolvedFileScope = f.scope

proc findDefinedType*(fileDef: AnalyzedFileDefinition, name: Identifier): Result[AnalyzedDefinedType, string] =
  if name notin fileDef.definedTypeIndex:
    err(fmt"{name.loc} file `{fileDef.path}` does not define a type named `{name.asl}`")
  else:
    ok(fileDef.definedTypeIndex[name])
