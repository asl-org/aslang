## Phase-A `AnalyzedAppDefinition` — the top-level phase-A result.
## Bundles the resolved app + every file's AnalyzedFileDefinition,
## indexed by absolute path for cross-file `findFileDef` queries.
##
## One identity-keyed index carries the phase-B lookup weight:
## `definedTypeIndex` (`ResolvedType → AnalyzedDefinedType`) —
## app-wide identity lookup used by `findDefinedType`. Every caller
## with a ResolvedType in hand (from `fileScope.findType`, an
## argType's carried module, etc.) reaches the analyzed
## module/generic without going through name-keyed per-file scopes;
## pre-analyzed funcDef signatures are then read off the result via
## `findFunctionDefs`. Immune to aliased-import name mismatch.

import results, strformat, tables

import ./resolver
import ./filedef
import ./definedtype
import ./moduledef
import ./generic

type AnalyzedAppDefinition* = ref object
  resolved: ResolvedApp
  fileDefs: seq[AnalyzedFileDefinition]
  fileDefIndex: Table[string, int]
  definedTypeIndex: Table[ResolvedType, AnalyzedDefinedType]

proc buildDefinedTypeIndex(fileDefs: seq[AnalyzedFileDefinition]): Table[ResolvedType, AnalyzedDefinedType] =
  ## Walk every file → every defined type, indexing by the underlying
  ## ResolvedType (which knows its ResolvedModule or ResolvedGeneric).
  ## Used by `findDefinedType` to bridge resolver-side type references
  ## (e.g. `fileScope.findType` results) to the analyzer-side
  ## AnalyzedDefinedType with its pre-analyzed funcDefs.
  for fileDef in fileDefs:
    for definedType in fileDef.types:
      let resolved =
        case definedType.kind:
        of adtkModule: newResolvedType(definedType.module.resolved)
        of adtkGeneric: newResolvedType(definedType.generic.resolved)
      result[resolved] = definedType

proc newAnalyzedAppDefinition*(resolved: ResolvedApp,
    fileDefs: seq[AnalyzedFileDefinition]): AnalyzedAppDefinition =
  var fileDefIndex: Table[string, int]
  for index, fileDef in fileDefs:
    fileDefIndex[fileDef.path] = index
  let definedTypeIndex = buildDefinedTypeIndex(fileDefs)
  AnalyzedAppDefinition(resolved: resolved, fileDefs: fileDefs, fileDefIndex: fileDefIndex, definedTypeIndex: definedTypeIndex)

proc resolved*(a: AnalyzedAppDefinition): ResolvedApp = a.resolved
proc fileDefs*(a: AnalyzedAppDefinition): seq[AnalyzedFileDefinition] = a.fileDefs

proc findFileDef*(appDef: AnalyzedAppDefinition, path: string): Result[AnalyzedFileDefinition, string] =
  if path notin appDef.fileDefIndex:
    err(fmt"file `{path}` not found")
  else:
    ok(appDef.fileDefs[appDef.fileDefIndex[path]])

proc findDefinedType*(appDef: AnalyzedAppDefinition, resolvedType: ResolvedType): Result[AnalyzedDefinedType, string] =
  ## Given a resolver-side ResolvedType (typically from
  ## fileScope.findType), return the pre-analyzed
  ## AnalyzedDefinedType. Callers reach `findFunctionDefs` on the
  ## result to consume pre-analyzed funcDef signatures.
  if resolvedType notin appDef.definedTypeIndex:
    err(fmt"{resolvedType.loc} UNREACHABLE: type `{resolvedType.name.asl}` not indexed in phase-A output")
  else:
    ok(appDef.definedTypeIndex[resolvedType])
