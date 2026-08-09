## Phase-A `AnalyzedDefFile` — per-file bundle of the file's
## analyzed imports + defined types, the identity-keyed
## ResolvedFileContext (`scope`), and a local-only definedTypeIndex
## (`ResolvedLocalType → AnalyzedLocalType`) behind `findType` /
## `findModule`.
##
## The local index deliberately excludes imports — analyzeImportedType
## uses it to verify an imported name is DEFINED in its source file,
## not merely visible there. Phase-B lookups spanning imports go
## through the body layer's `AnalyzedFileContext` instead.

import sequtils, strformat, tables

import ./resolver
import ./context
import ./types
import ./importdef

proc buildTypeIndex(types: seq[AnalyzedLocalType]): Table[ResolvedLocalType, AnalyzedLocalType] =
  var typeIndex: Table[ResolvedLocalType, AnalyzedLocalType]
  for typ in types:
    assert(typ.resolved notin typeIndex, fmt"[BUG] - {typ.loc} duplicate defined type `{typ.name.asl}` in the file def")
    typeIndex[typ.resolved] = typ
  return typeIndex

type AnalyzedDefFile* = ref object
  resolved: ResolvedFile
  imports: seq[AnalyzedDefImport]
  types: seq[AnalyzedLocalType]
  scope: ResolvedFileContext
  definedTypeIndex: Table[ResolvedLocalType, AnalyzedLocalType]

proc newAnalyzedDefFile*(resolved: ResolvedFile, imports: seq[AnalyzedDefImport], types: seq[AnalyzedLocalType], scope: ResolvedFileContext): AnalyzedDefFile =
  let definedTypeIndex = buildTypeIndex(types)
  AnalyzedDefFile(resolved: resolved, imports: imports, types: types, scope: scope, definedTypeIndex: definedTypeIndex)

proc path*(f: AnalyzedDefFile): string = f.resolved.path
proc imports*(f: AnalyzedDefFile): seq[AnalyzedDefImport] = f.imports
proc types*(f: AnalyzedDefFile): seq[AnalyzedLocalType] = f.types
proc modules*(file: AnalyzedDefFile): seq[AnalyzedDefModule] =
  file.types.filterIt(it.kind == altkModule).mapIt(it.module)

# Identity lookups — phase A analyzed every type DEFINED in this
# file (local-only by design: analyzeImportedType uses findType to
# verify an imported name is defined in its source file), so a miss
# is a compiler bug.
proc findType*(fileDef: AnalyzedDefFile, typ: ResolvedLocalType): AnalyzedLocalType =
  assert(typ in fileDef.definedTypeIndex, fmt"[BUG] - {typ.loc} type `{typ.name.asl}` missing from the file def")
  fileDef.definedTypeIndex[typ]

proc findModule*(fileDef: AnalyzedDefFile, module: ResolvedModule): AnalyzedDefModule =
  let foundType = fileDef.findType(newResolvedLocalType(module))
  assert(foundType.kind == altkModule, fmt"[BUG] - {module.loc} `{module.name.asl}` was analyzed as a module in phase A")
  foundType.module
