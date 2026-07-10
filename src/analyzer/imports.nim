## Analyzed imports — verifies each imported name resolves to a
## defined type in its source file, and bundles the per-file imports
## into an AnalyzedImportDef.

import results, strformat, options

import ./resolver

type AnalyzedImportedType* = ref object
  resolved: ResolvedImportedType
  typ: ResolvedType

proc newAnalyzedImportedType*(resolved: ResolvedImportedType, typ: ResolvedType): AnalyzedImportedType =
  AnalyzedImportedType(resolved: resolved, typ: typ)

proc binding*(impType: AnalyzedImportedType): Identifier = impType.resolved.binding
proc typ*(impType: AnalyzedImportedType): ResolvedType = impType.typ

proc analyzeImportedType*(app: ResolvedApp, impFile: ResolvedFile, impType: ResolvedImportedType): Result[AnalyzedImportedType, string] =
  let maybeImportedType = impFile.findType(impType.typ.name)
  if maybeImportedType.isErr:
    err(fmt"{impType.loc} type `{impType.typ.name.asl}` is not defined in the file")
  else:
    ok(newAnalyzedImportedType(impType, maybeImportedType.get))

type AnalyzedImportDef* = ref object
  resolved: ResolvedImport
  importedTypes: seq[AnalyzedImportedType]

proc newAnalyzedImportDef*(resolved: ResolvedImport, importedTypes: seq[AnalyzedImportedType]): AnalyzedImportDef =
  AnalyzedImportDef(resolved: resolved, importedTypes: importedTypes)

proc importedTypes*(imp: AnalyzedImportDef): seq[AnalyzedImportedType] = imp.importedTypes
proc path*(imp: AnalyzedImportDef): string = imp.resolved.impFile.path

proc analyzeImportDef*(app: ResolvedApp, file: ResolvedFile, imp: ResolvedImport): Result[AnalyzedImportDef, string] =
  let maybeImportedFile = app.findFile(imp.impFile)
  if maybeImportedFile.isNone:
    err(fmt"{imp.loc} UNREACHABLE: file `{imp.impFile.path}` does not exist")
  else:
    let analyzedImpFile = maybeImportedFile.get
    var importedTypes: seq[AnalyzedImportedType]
    for impType in imp.importedTypes:
      let analyzedImportedType = ? analyzeImportedType(app, analyzedImpFile, impType)
      importedTypes.add(analyzedImportedType)
    ok(newAnalyzedImportDef(imp, importedTypes))
