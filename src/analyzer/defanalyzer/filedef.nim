## Phase-A `AnalyzedDefFile` — per-file bundle of the file's
## analyzed imports + defined types, the identity-keyed
## ResolvedFileContext (`scope`), and a local-only definedTypeIndex
## (`ResolvedType → AnalyzedType`) behind `findType` /
## `findModule`.
##
## The local index deliberately excludes imports — analyzeImportedType
## uses it to verify an imported name is DEFINED in its source file,
## not merely visible there. Phase-B lookups spanning imports go
## through the body layer's `AnalyzedFileContext` instead.

import strformat, tables

import ./resolver
import ./argtype
import ./filecontext
import ./types
import ./importdef
import ./moduledef

proc buildTypeIndex(types: seq[AnalyzedType]): Table[ResolvedType, AnalyzedType] =
  var typeIndex: Table[ResolvedType, AnalyzedType]
  for typ in types:
    assert(typ.resolved notin typeIndex, fmt"[BUG] - {typ.loc} duplicate defined type `{typ.name.asl}` in the file def")
    typeIndex[typ.resolved] = typ
  return typeIndex

type AnalyzedDefFile* = ref object
  resolved: ResolvedFile
  imports: seq[AnalyzedDefImport]
  types: seq[AnalyzedType]
  scope: ResolvedFileContext
  definedTypeIndex: Table[ResolvedType, AnalyzedType]

proc newAnalyzedDefFile*(resolved: ResolvedFile, imports: seq[AnalyzedDefImport], types: seq[AnalyzedType], scope: ResolvedFileContext): AnalyzedDefFile =
  let definedTypeIndex = buildTypeIndex(types)
  AnalyzedDefFile(resolved: resolved, imports: imports, types: types, scope: scope, definedTypeIndex: definedTypeIndex)

proc resolved*(f: AnalyzedDefFile): ResolvedFile = f.resolved
proc path*(f: AnalyzedDefFile): string = f.resolved.path
proc imports*(f: AnalyzedDefFile): seq[AnalyzedDefImport] = f.imports
proc types*(f: AnalyzedDefFile): seq[AnalyzedType] = f.types
proc scope*(f: AnalyzedDefFile): ResolvedFileContext = f.scope

# Identity lookups — phase A analyzed every type DEFINED in this
# file (local-only by design: analyzeImportedType uses findType to
# verify an imported name is defined in its source file), so a miss
# is a compiler bug.
proc findType*(fileDef: AnalyzedDefFile, typ: ResolvedType): AnalyzedType =
  assert(typ in fileDef.definedTypeIndex, fmt"[BUG] - {typ.loc} type `{typ.name.asl}` missing from the file def")
  fileDef.definedTypeIndex[typ]

proc findModule*(fileDef: AnalyzedDefFile, module: ResolvedModule): AnalyzedDefModule =
  let foundType = fileDef.findType(newResolvedType(module))
  assert(foundType.kind == atkModule, fmt"[BUG] - {module.loc} `{module.name.asl}` was analyzed as a module in phase A")
  foundType.module

proc defaultLiteralType*(fileDef: AnalyzedDefFile, literal: ResolvedLiteral): AnalyzedArgumentType =
  ## The resolver bound `literal.default` through this file's scope
  ## (resolveLiteral), so the identity lookup cannot miss.
  newAnalyzedArgumentType(fileDef.scope.findModule(literal.default))