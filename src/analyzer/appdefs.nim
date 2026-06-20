## File / App + the public analyze* entry point. AnalyzedDefinedType
## and analyzeDefinedType live in modules.nim alongside their arms.

import results, tables, strformat

import resolver
import funcs
import imports
import modules
import filedefs

# AnalyzedAppDefinition + entry
type AnalyzedAppDefinition* = ref object
  resolved: ResolvedApp
  fileDefs: seq[AnalyzedFileDefinition]
  fileDefIndex: Table[string, int]

proc newAnalyzedAppDefinition*(resolved: ResolvedApp, fileDefs: seq[AnalyzedFileDefinition]): AnalyzedAppDefinition =
  var fileDefIndex: Table[string, int]
  for index, fileDef in fileDefs:
    fileDefIndex[fileDef.path] = index
  AnalyzedAppDefinition(resolved: resolved, fileDefs: fileDefs, fileDefIndex: fileDefIndex)

proc resolved*(a: AnalyzedAppDefinition): ResolvedApp = a.resolved
proc fileDefs*(a: AnalyzedAppDefinition): seq[AnalyzedFileDefinition] = a.fileDefs

proc findFileDef(appDef: AnalyzedAppDefinition, path: string): Result[AnalyzedFileDefinition, string] =
  if path notin appDef.fileDefIndex:
    err(fmt"file `{path}` not found")
  else:
    ok(appDef.fileDefs[appDef.fileDefIndex[path]])

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
    let impFileDef = ? appDef.findFileDef(imp.path)
    for impType in imp.importedTypes:
      defScope[impType.binding] = ? impFileDef.findDefinedType(impType.definedType.name)

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