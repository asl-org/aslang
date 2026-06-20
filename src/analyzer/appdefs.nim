## File / App + the public analyze* entry point. AnalyzedDefinedType
## and analyzeDefinedType live in modules.nim alongside their arms.

import results
import resolver
import funcs
import modules
import filedefs

# AnalyzedAppDefinition + entry
type AnalyzedAppDefinition* = ref object
  resolved: ResolvedApp
  files: seq[AnalyzedFileDefinition]

proc newAnalyzedAppDefinition*(resolved: ResolvedApp, files: seq[AnalyzedFileDefinition]): AnalyzedAppDefinition =
  AnalyzedAppDefinition(resolved: resolved, files: files)

proc resolved*(a: AnalyzedAppDefinition): ResolvedApp = a.resolved
proc fileDefs*(a: AnalyzedAppDefinition): seq[AnalyzedFileDefinition] = a.files

proc analyzeAppDefinition*(app: ResolvedApp): Result[AnalyzedAppDefinition, string] =
  var analyzedFileDefinitions: seq[AnalyzedFileDefinition]
  for file in app.files:
    let analyzedFileDefinition = ? analyzeFileDefinition(app, file)
    analyzedFileDefinitions.add(analyzedFileDefinition)
  ok(newAnalyzedAppDefinition(app, analyzedFileDefinitions))

proc analyzeFile(appDef: AnalyzedAppDefinition, fileDef: AnalyzedFileDefinition): Result[void, string] =
  var defScope = fileDef.definedTypeIndex
  # TODO: Insert imported types in the definition scope
  for imp in fileDef.imports:
    discard

  var analyzedModules: seq[AnalyzedModule]
  for definedType in fileDef.definedTypes:
    case definedType.kind:
    of adtkGeneric: discard # generics are already resolved since it is only a definition type
    of adtkModule:
      let analyzedModule = ? analyzeModule(appDef.resolved, fileDef.resolved, fileDef.scope, definedType.module, defScope)
      analyzedModules.add(analyzedModule)
  ok()

proc analyze*(app: ResolvedApp): Result[void, string] =
  let analyzedAppDef = ? app.analyzeAppDefinition()
  for fileDef in analyzedAppDef.fileDefs:
    ? analyzedAppDef.analyzeFile(fileDef)
  ok()