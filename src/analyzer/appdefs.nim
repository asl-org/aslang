## AnalyzedApp / AnalyzedFile + the public `analyze` entry point.
##
## Post-6c the analyzer has no separate def-level pass — every
## definition-level index and accessor is carried directly on the
## resolver's ResolvedApp / ResolvedFile / ResolvedModule / ResolvedGeneric
## / ResolvedStructDef / ResolvedUnionDef / ResolvedVariant. `analyze`
## walks the app tree file-by-file, seeds each file's scope from
## imports + local defined types, and drives per-module body analysis
## via `analyzeModule`. Extern functions have no body to analyze — the
## walker skips them at the funcs.nim layer.

import results, tables

import resolver
import argtypes
import imports
import funcs

type AnalyzedFile* = ref object
  resolved: ResolvedFile
  imports: seq[AnalyzedImportDef]
  modules: seq[AnalyzedModule]

proc newAnalyzedFile*(resolved: ResolvedFile, imports: seq[AnalyzedImportDef], modules: seq[AnalyzedModule]): AnalyzedFile =
  AnalyzedFile(resolved: resolved, imports: imports, modules: modules)

proc resolved*(f: AnalyzedFile): ResolvedFile = f.resolved
proc path*(f: AnalyzedFile): string = f.resolved.path
proc imports*(f: AnalyzedFile): seq[AnalyzedImportDef] = f.imports
proc modules*(f: AnalyzedFile): seq[AnalyzedModule] = f.modules

type AnalyzedApp* = ref object
  resolved: ResolvedApp
  files: seq[AnalyzedFile]

proc newAnalyzedApp*(resolved: ResolvedApp, files: seq[AnalyzedFile]): AnalyzedApp =
  AnalyzedApp(resolved: resolved, files: files)

proc resolved*(a: AnalyzedApp): ResolvedApp = a.resolved
proc files*(a: AnalyzedApp): seq[AnalyzedFile] = a.files

proc analyzeFile(app: ResolvedApp, file: ResolvedFile): Result[AnalyzedFile, string] =
  ## Build the fileScope from imports (name → resolved defined type in
  ## the imported file) + this file's own defined types, then drive
  ## per-module body analysis.
  var fileScope: ResolvedFileScope
  var analyzedImports: seq[AnalyzedImportDef]
  for imp in file.imports:
    let analyzedImport = ? analyzeImportDef(app, file, imp)
    analyzedImports.add(analyzedImport)
    for impType in analyzedImport.importedTypes:
      fileScope[impType.binding] = impType.definedType

  for definedType in file.types:
    fileScope[definedType.name] = definedType

  var analyzedModules: seq[AnalyzedModule]
  for definedType in file.types:
    case definedType.kind:
    of rdtkGeneric: discard # generics are already resolved since it is only a definition type
    of rdtkModule:
      let analyzedModule = ? analyzeModule(app, file, fileScope, definedType.module)
      analyzedModules.add(analyzedModule)
  ok(newAnalyzedFile(file, analyzedImports, analyzedModules))

proc analyze*(app: ResolvedApp): Result[AnalyzedApp, string] =
  var analyzedFiles: seq[AnalyzedFile]
  for file in app.files:
    let analyzedFile = ? analyzeFile(app, file)
    analyzedFiles.add(analyzedFile)
  ok(newAnalyzedApp(app, analyzedFiles))
