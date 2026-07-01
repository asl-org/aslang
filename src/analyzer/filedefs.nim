## File / App + the public analyze* entry point. AnalyzedDefinedType
## and analyzeDefinedType live in modules.nim alongside their arms.

import results, tables, strformat

import parser
import resolver

import imports
import argtypes
import funcrefs
import modules

# AnalyzedFileDefinition
type AnalyzedFileDefinition* = ref object
  resolved: ResolvedFile
  imports: seq[AnalyzedImportDefinition]
  definedTypes: seq[AnalyzedDefinedType]
  scope: ResolvedFileScope
  definedTypeIndex: AnalyzedDefinedTypeScope

proc newAnalyzedFileDefinition*(resolved: ResolvedFile, imports: seq[AnalyzedImportDefinition], definedTypes: seq[AnalyzedDefinedType], scope: ResolvedFileScope): AnalyzedFileDefinition =
  var definedTypeIndex: AnalyzedDefinedTypeScope
  for definedType in definedTypes:
    definedTypeIndex[definedType.name] = definedType
  AnalyzedFileDefinition(resolved: resolved, imports: imports, definedTypes: definedTypes, scope: scope, definedTypeIndex: definedTypeIndex)

proc resolved*(f: AnalyzedFileDefinition): ResolvedFile = f.resolved
proc path*(f: AnalyzedFileDefinition): string = f.resolved.path
proc imports*(f: AnalyzedFileDefinition): seq[AnalyzedImportDefinition] = f.imports
proc definedTypes*(f: AnalyzedFileDefinition): seq[AnalyzedDefinedType] = f.definedTypes
proc scope*(f: AnalyzedFileDefinition): ResolvedFileScope = f.scope
proc definedTypeIndex*(f: AnalyzedFileDefinition): AnalyzedDefinedTypeScope = f.definedTypeIndex

proc findDefinedType*(fileDef: AnalyzedFileDefinition, name: Identifier): Result[AnalyzedDefinedType, string] =
  if name notin fileDef.definedTypeIndex:
    err(fmt"{name.loc} file `{fileDef.path}` does not defined a type named `{name.asl}`")
  else:
    ok(fileDef.definedTypeIndex[name])

proc analyzeFileDefinition*(app: ResolvedApp, file: ResolvedFile): Result[AnalyzedFileDefinition, string] =
  var fileScope: ResolvedFileScope
  var analyzedImports: seq[AnalyzedImportDefinition]
  for imp in file.imports:
    let analyzedImport = ? analyzeImportDefinition(app, file, imp)
    analyzedImports.add(analyzedImport)
    for impType in analyzedImport.importedTypes:
      fileScope[impType.binding] = impType.definedType

  var analyzedDefinedTypes: seq[AnalyzedDefinedType]
  for aslType in file.definedTypes:
    let analyzedDefinedType = ? analyzeDefinedType(app, file, fileScope, aslType)
    analyzedDefinedTypes.add(analyzedDefinedType)
  ok(newAnalyzedFileDefinition(file, analyzedImports, analyzedDefinedTypes, fileScope))
