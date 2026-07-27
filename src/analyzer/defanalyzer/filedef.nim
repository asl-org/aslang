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
import ./moduledef

type AnalyzedFileDefinition* = ref object
  resolved: ResolvedFile
  imports: seq[AnalyzedImportDefinition]
  types: seq[AnalyzedDefinedType]
  scope: ResolvedFileScope
  definedTypeIndex: Table[ResolvedType, AnalyzedDefinedType]

proc newAnalyzedFileDefinition*(resolved: ResolvedFile,
    imports: seq[AnalyzedImportDefinition],
    types: seq[AnalyzedDefinedType],
    scope: ResolvedFileScope): AnalyzedFileDefinition =
  var definedTypeIndex: Table[ResolvedType, AnalyzedDefinedType]
  for definedType in types:
    definedTypeIndex[definedType.resolved] = definedType
  AnalyzedFileDefinition(resolved: resolved, imports: imports,
    types: types, scope: scope, definedTypeIndex: definedTypeIndex)

proc resolved*(f: AnalyzedFileDefinition): ResolvedFile = f.resolved
proc path*(f: AnalyzedFileDefinition): string = f.resolved.path
proc imports*(f: AnalyzedFileDefinition): seq[AnalyzedImportDefinition] = f.imports
proc types*(f: AnalyzedFileDefinition): seq[AnalyzedDefinedType] = f.types
proc scope*(f: AnalyzedFileDefinition): ResolvedFileScope = f.scope

proc findType*(fileDef: AnalyzedFileDefinition, typ: ResolvedType, loc: Location): Result[AnalyzedDefinedType, string] =
  if typ in fileDef.definedTypeIndex: ok(fileDef.definedTypeIndex[typ])
  else: err(fmt"{loc} type `{typ.name.asl}` does not exist")

proc findModule*(fileDef: AnalyzedFileDefinition, module: ResolvedModule, loc: Location): Result[AnalyzedModuleDefinition, string] =
  let typ = newResolvedType(module)
  let foundType = ? fileDef.findType(typ, loc)
  case foundType.kind:
  of adtkModule: ok(foundType.module)
  of adtkGeneric: err(fmt"{loc} expected `{foundType.name.asl}` to be a module but found generic")