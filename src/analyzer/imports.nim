## Analyzed imports — verifies each imported name resolves to a
## defined type in its source file, and bundles the per-file imports
## into an AnalyzedImport.

import results, strformat, options

import parser
import resolver

type AnalyzedImportedType* = ref object
  resolved: ResolvedImportedType
  definedType: ResolvedDefinedType

proc newAnalyzedImportedType*(resolved: ResolvedImportedType, definedType: ResolvedDefinedType): AnalyzedImportedType =
  AnalyzedImportedType(resolved: resolved, definedType: definedType)

proc binding*(impType: AnalyzedImportedType): Identifier = impType.resolved.binding
proc definedType*(impType: AnalyzedImportedType): ResolvedDefinedType = impType.definedType

proc analyzeImportedType*(app: ResolvedApp, impFile: ResolvedFile, impType: ResolvedImportedType): Result[AnalyzedImportedType, string] =
  let maybeImportedType = impFile.findDefinedType(impType.definedType.name)
  if maybeImportedType.isErr:
    err(fmt"{impType.loc} type `{impType.definedType.name.asl}` is not defined in the file")
  else:
    ok(newAnalyzedImportedType(impType, maybeImportedType.get))

type AnalyzedImport* = ref object
  resolved: ResolvedImport
  importedTypes: seq[AnalyzedImportedType]

proc newAnalyzeImport*(resolved: ResolvedImport, importedTypes: seq[AnalyzedImportedType]): AnalyzedImport =
  AnalyzedImport(resolved: resolved, importedTypes: importedTypes)

proc importedTypes*(imp: AnalyzedImport): seq[AnalyzedImportedType] = imp.importedTypes

proc analyzeImport*(app: ResolvedApp, file: ResolvedFile, imp: ResolvedImport): Result[AnalyzedImport, string] =
  let maybeImportedFile = app.findFile(imp.parsed)
  if maybeImportedFile.isNone:
    err(fmt"{imp.loc} UNREACHABLE: file `{imp.parsed.path}` does not exist")
  else:
    let analyzedImpFile = maybeImportedFile.get
    var importedTypes: seq[AnalyzedImportedType]
    for impType in imp.importedTypes:
      let analyzedImportedType = ? analyzeImportedType(app, analyzedImpFile, impType)
      importedTypes.add(analyzedImportedType)
    ok(newAnalyzeImport(imp, importedTypes))
