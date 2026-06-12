## File / App + the public analyze* entry point. AnalyzedDefinedType
## and analyzeDefinedType live in modules.nim alongside their arms.

import strformat, results, tables

import funcs
import parser
import resolver
import imports
import argtypes
import modules
import funcrefs

# AnalyzedFile
type AnalyzedFile* = ref object
  resolved: ResolvedFile
  imports: seq[AnalyzedImport]
  definedTypes: seq[AnalyzedDefinedType]
  modules: seq[AnalyzedModule]

proc newAnalyzedFile*(resolved: ResolvedFile, imports: seq[AnalyzedImport], definedTypes: seq[AnalyzedDefinedType], modules: seq[AnalyzedModule]): AnalyzedFile =
  AnalyzedFile(resolved: resolved, imports: imports, definedTypes: definedTypes, modules: modules)

proc resolved*(f: AnalyzedFile): ResolvedFile = f.resolved
proc path*(f: AnalyzedFile): string = f.resolved.path
proc imports*(f: AnalyzedFile): seq[AnalyzedImport] = f.imports
proc definedTypes*(f: AnalyzedFile): seq[AnalyzedDefinedType] = f.definedTypes
proc modules*(f: AnalyzedFile): seq[AnalyzedModule] = f.modules

proc analyzeFile*(app: ResolvedApp, file: ResolvedFile): Result[AnalyzedFile, string] =
  var fileScope: AnalyzedFileScope
  var analyzedImports: seq[AnalyzedImport]
  for imp in file.imports:
    let analyzedImport = ? analyzeImport(app, file, imp)
    analyzedImports.add(analyzedImport)
    for impType in analyzedImport.importedTypes:
      fileScope[impType.binding] = impType.definedType

  var analyzedDefinedTypes: seq[AnalyzedDefinedType]
  var analyzedDefinedTypeScope: AnalyzedDefinedTypeScope
  for aslType in file.definedTypes:
    let analyzedDefinedType = ? analyzeDefinedType(app, file, fileScope, aslType)
    analyzedDefinedTypes.add(analyzedDefinedType)
    analyzedDefinedTypeScope[analyzedDefinedType.name] = analyzedDefinedType

  var analyzedModules: seq[AnalyzedModule]
  for aslType in file.definedTypes:
    case aslType.kind:
    of rdtkGeneric: discard # generics are already resolved since it is only a definition type
    of rdtkModule:
      let analyzedModule = ? analyzeModule(app, file, fileScope, aslType.module, analyzedDefinedTypeScope)
      analyzedModules.add(analyzedModule)
  ok(newAnalyzedFile(file, analyzedImports, analyzedDefinedTypes, analyzedModules))

# AnalyzedApp + entry
type AnalyzedApp* = ref object
  resolved: ResolvedApp
  files: seq[AnalyzedFile]

proc newAnalyzedApp*(resolved: ResolvedApp, files: seq[AnalyzedFile]): AnalyzedApp =
  AnalyzedApp(resolved: resolved, files: files)

proc resolved*(a: AnalyzedApp): ResolvedApp = a.resolved
proc files*(a: AnalyzedApp): seq[AnalyzedFile] = a.files

proc analyze*(app: ResolvedApp): Result[AnalyzedApp, string] =
  var analyzedFiles: seq[AnalyzedFile]
  for file in app.files:
    let maybeAnalyzedFile = analyzeFile(app, file)
    if maybeAnalyzedFile.isErr:
      return err(fmt"{file.path}:{maybeAnalyzedFile.error}")
    else:
      analyzedFiles.add(maybeAnalyzedFile.get)
  ok(newAnalyzedApp(app, analyzedFiles))
