## DefinedType / File / App + the public analyze* entry point.

import strformat, results, tables

import parser
import resolver
import imports
import argtypes
import modules

# AnalyzedDefinedType
type
  AnalyzedDefinedTypeKind* = enum
    adtkModule, adtkGeneric
  AnalyzedDefinedType* = ref object
    case kind: AnalyzedDefinedTypeKind
    of adtkModule: module: AnalyzedModuleDefinition
    of adtkGeneric: generic: AnalyzedGeneric

proc newAnalyzedDefinedType*(module: AnalyzedModuleDefinition): AnalyzedDefinedType =
  AnalyzedDefinedType(kind: adtkModule, module: module)

proc newAnalyzedDefinedType*(generic: AnalyzedGeneric): AnalyzedDefinedType =
  AnalyzedDefinedType(kind: adtkGeneric, generic: generic)

proc kind*(d: AnalyzedDefinedType): AnalyzedDefinedTypeKind = d.kind
proc module*(d: AnalyzedDefinedType): AnalyzedModuleDefinition = d.module
proc generic*(d: AnalyzedDefinedType): AnalyzedGeneric = d.generic
proc name(d: AnalyzedDefinedType): Identifier =
  case d.kind:
  of adtkModule: d.module.name
  of adtkGeneric: d.generic.name

proc analyzeDefinedType*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, definedType: ResolvedDefinedType): Result[AnalyzedDefinedType, string] =
  case definedType.kind:
  of rdtkGeneric:
    let analyzedGeneric = ? analyzeGeneric(app, file, definedType.generic)
    ok(newAnalyzedDefinedType(analyzedGeneric))
  of rdtkModule:
    let analyzedModule = ? analyzeModuleDefinition(app, file, fileScope, definedType.module)
    ok(newAnalyzedDefinedType(analyzedModule))

proc analyzeExpression(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: Table[Identifier, AnalyzedModuleDefinition]): Result[void, string] =
  err("{module.loc} analyze expression")

# AnalyzedFile
type AnalyzedFile* = ref object
  imports: seq[AnalyzedImport]
  definedTypes: seq[AnalyzedDefinedType]

proc newAnalyzedFile*(imports: seq[AnalyzedImport], definedTypes: seq[AnalyzedDefinedType]): AnalyzedFile =
  AnalyzedFile(imports: imports, definedTypes: definedTypes)

proc imports*(f: AnalyzedFile): seq[AnalyzedImport] = f.imports
proc definedTypes*(f: AnalyzedFile): seq[AnalyzedDefinedType] = f.definedTypes

proc analyzeFile*(app: ResolvedApp, file: ResolvedFile): Result[AnalyzedFile, string] =
  var fileScope: AnalyzedFileScope
  var analyzedImports: seq[AnalyzedImport]
  for imp in file.imports:
    let analyzedImport = ? analyzeImport(app, file, imp)
    analyzedImports.add(analyzedImport)
    for impType in analyzedImport.importedTypes:
      fileScope[impType.binding] = impType.definedType

  var analyzedDefinedTypes: seq[AnalyzedDefinedType]
  var analyzedFileScope: Table[Identifier, AnalyzedModuleDefinition]
  for aslType in file.definedTypes:
    let analyzedDefinedType = ? analyzeDefinedType(app, file, fileScope, aslType)
    analyzedDefinedTypes.add(analyzedDefinedType)

    case analyzedDefinedType.kind:
    of adtkGeneric: discard
    of adtkModule: analyzedFileScope[analyzedDefinedType.name] = analyzedDefinedType.module

  for aslType in file.definedTypes:
    case aslType.kind:
    of rdtkGeneric: discard # generics are already resolved since it is only a definition type
    of rdtkModule:
      ? analyzeExpression(app, file, fileScope, aslType.module, analyzedFileScope)
  ok(newAnalyzedFile(analyzedImports, analyzedDefinedTypes))

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
