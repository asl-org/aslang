## Phase-A `AnalyzedAppDefinition` — the top-level phase-A result.
## Bundles the resolved app + every file's AnalyzedFileDefinition,
## indexed by absolute path for cross-file `findFileDef` queries.
##
## Two identity-keyed indices carry the phase-B lookup weight:
##  - `funcDefIndex`: `ResolvedFunctionDef → AnalyzedFunctionDefinition`.
##    Phase-B overload resolution hands back the resolver-side
##    ResolvedFunctionDef; this index gets the pre-analyzed form
##    (args + return type already lifted through analyzeArgumentType)
##    in O(1), avoiding per-call-site re-analysis.
##  - `definedTypeIndex`: `ResolvedType → AnalyzedDefinedType`.
##    App-wide identity lookup used by `findDefinedType`. Every
##    caller with a ResolvedType in hand (from `app.findType`, from
##    an argType's carried module, etc.) reaches the analyzed
##    module/generic without going through name-keyed per-file
##    scopes. Immune to aliased-import name mismatch.

import results, strformat, tables

import ./resolver
import ./filedef
import ./definedtype
import ./moduledef
import ./generic
import ./funcdef

type AnalyzedAppDefinition* = ref object
  resolved: ResolvedApp
  fileDefs: seq[AnalyzedFileDefinition]
  fileDefIndex: Table[string, int]
  funcDefIndex: Table[ResolvedFunctionDef, AnalyzedFunctionDefinition]
  definedTypeIndex: Table[ResolvedType, AnalyzedDefinedType]

proc buildFuncDefIndex(fileDefs: seq[AnalyzedFileDefinition]): Table[ResolvedFunctionDef, AnalyzedFunctionDefinition] =
  ## Walk every file → every defined type → every module or generic →
  ## every funcDef, indexing by the underlying ResolvedFunctionDef.
  ## Used by `findFunctionDef` on the app-level lookup for phase B.
  for fileDef in fileDefs:
    for definedType in fileDef.types:
      case definedType.kind:
      of adtkModule:
        for funcDef in definedType.module.funcDefs:
          result[funcDef.resolved] = funcDef
      of adtkGeneric:
        for funcDef in definedType.generic.funcDefs:
          result[funcDef.resolved] = funcDef

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
  AnalyzedAppDefinition(resolved: resolved, fileDefs: fileDefs,
    fileDefIndex: fileDefIndex,
    funcDefIndex: buildFuncDefIndex(fileDefs),
    definedTypeIndex: buildDefinedTypeIndex(fileDefs))

proc resolved*(a: AnalyzedAppDefinition): ResolvedApp = a.resolved
proc fileDefs*(a: AnalyzedAppDefinition): seq[AnalyzedFileDefinition] = a.fileDefs

proc findFileDef*(appDef: AnalyzedAppDefinition, path: string): Result[AnalyzedFileDefinition, string] =
  if path notin appDef.fileDefIndex:
    err(fmt"file `{path}` not found")
  else:
    ok(appDef.fileDefs[appDef.fileDefIndex[path]])

proc findFunctionDef*(appDef: AnalyzedAppDefinition, funcDef: ResolvedFunctionDef): Result[AnalyzedFunctionDefinition, string] =
  ## Given a ResolvedFunctionDef (what overload resolution hands
  ## back from ResolvedModule.findFunctionDefs), return the
  ## pre-analyzed AnalyzedFunctionDefinition — no re-analysis of arg
  ## types or return type. Used by analyzeArgumentList to consume
  ## phase-A results.
  if funcDef notin appDef.funcDefIndex:
    err(fmt"{funcDef.loc} UNREACHABLE: funcDef `{funcDef.name.asl}` not indexed in phase-A output")
  else:
    ok(appDef.funcDefIndex[funcDef])

proc findDefinedType*(appDef: AnalyzedAppDefinition, resolvedType: ResolvedType): Result[AnalyzedDefinedType, string] =
  ## Given a resolver-side ResolvedType (typically from
  ## fileScope.findType), return the pre-analyzed
  ## AnalyzedDefinedType. Callers reach `findFunctionDefs` on the
  ## result to consume pre-analyzed funcDef signatures.
  if resolvedType notin appDef.definedTypeIndex:
    err(fmt"{resolvedType.loc} UNREACHABLE: type `{resolvedType.name.asl}` not indexed in phase-A output")
  else:
    ok(appDef.definedTypeIndex[resolvedType])
