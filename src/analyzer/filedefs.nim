## File / App + the public analyze* entry point. AnalyzedDefinedType
## and analyzeDefinedType live in modules.nim alongside their arms.

import results, tables

import funcs
import parser
import resolver
import imports
import argtypes
import modules
import funcrefs

# AnalyzedFileDefinition
type AnalyzedFileDefinition* = ref object
  resolved: ResolvedFile
  imports: seq[AnalyzedImport]
  definedTypes: seq[AnalyzedDefinedType]
  modules: seq[AnalyzedModule]

proc newAnalyzedFileDefinition*(resolved: ResolvedFile, imports: seq[AnalyzedImport], definedTypes: seq[AnalyzedDefinedType], modules: seq[AnalyzedModule]): AnalyzedFileDefinition =
  AnalyzedFileDefinition(resolved: resolved, imports: imports, definedTypes: definedTypes, modules: modules)

proc resolved*(f: AnalyzedFileDefinition): ResolvedFile = f.resolved
proc path*(f: AnalyzedFileDefinition): string = f.resolved.path
proc imports*(f: AnalyzedFileDefinition): seq[AnalyzedImport] = f.imports
proc definedTypes*(f: AnalyzedFileDefinition): seq[AnalyzedDefinedType] = f.definedTypes
proc modules*(f: AnalyzedFileDefinition): seq[AnalyzedModule] = f.modules

proc analyzeFileDefinition*(app: ResolvedApp, file: ResolvedFile): Result[AnalyzedFileDefinition, string] =
  var fileScope: ResolvedFileScope
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
  for definedType in analyzedDefinedTypes:
    case definedType.kind:
    of adtkGeneric: discard # generics are already resolved since it is only a definition type
    of adtkModule:
      let analyzedModule = ? analyzeModule(app, file, fileScope, definedType.module, analyzedDefinedTypeScope)
      analyzedModules.add(analyzedModule)
  ok(newAnalyzedFileDefinition(file, analyzedImports, analyzedDefinedTypes, analyzedModules))
