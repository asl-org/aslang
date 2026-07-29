## Phase-A `AnalyzedDefFile` — per-file bundle of the file's
## analyzed imports + defined types, the identity-keyed
## ResolvedFileScope (`scope`), and a local-only definedTypeIndex
## (`ResolvedType → AnalyzedType`) behind `findType` /
## `findModule`.
##
## The local index deliberately excludes imports — analyzeImportedType
## uses it to verify an imported name is DEFINED in its source file,
## not merely visible there. Phase-B lookups spanning imports go
## through the body layer's `AnalyzedFileScope` instead.

import results, strformat, tables

import ./resolver
import ./argtype
import ./filescope
import ./types
import ./importdef
import ./moduledef

type AnalyzedDefFile* = ref object
  resolved: ResolvedFile
  imports: seq[AnalyzedDefImport]
  types: seq[AnalyzedType]
  scope: ResolvedFileScope
  definedTypeIndex: Table[ResolvedType, AnalyzedType]

proc newAnalyzedDefFile*(resolved: ResolvedFile,
    imports: seq[AnalyzedDefImport],
    types: seq[AnalyzedType],
    scope: ResolvedFileScope): AnalyzedDefFile =
  var definedTypeIndex: Table[ResolvedType, AnalyzedType]
  for definedType in types:
    definedTypeIndex[definedType.resolved] = definedType
  AnalyzedDefFile(resolved: resolved, imports: imports,
    types: types, scope: scope, definedTypeIndex: definedTypeIndex)

proc resolved*(f: AnalyzedDefFile): ResolvedFile = f.resolved
proc path*(f: AnalyzedDefFile): string = f.resolved.path
proc imports*(f: AnalyzedDefFile): seq[AnalyzedDefImport] = f.imports
proc types*(f: AnalyzedDefFile): seq[AnalyzedType] = f.types
proc scope*(f: AnalyzedDefFile): ResolvedFileScope = f.scope

proc findType*(fileDef: AnalyzedDefFile, typ: ResolvedType, loc: Location): Result[AnalyzedType, string] =
  if typ in fileDef.definedTypeIndex: ok(fileDef.definedTypeIndex[typ])
  else: err(fmt"{loc} type `{typ.name.asl}` does not exist")

proc findModule*(fileDef: AnalyzedDefFile, module: ResolvedModule, loc: Location): Result[AnalyzedDefModule, string] =
  let typ = newResolvedType(module)
  let foundType = ? fileDef.findType(typ, loc)
  case foundType.kind:
  of atkModule: ok(foundType.module)
  of atkGeneric: err(fmt"{loc} expected `{foundType.name.asl}` to be a module but found generic")

proc defaultLiteralType*(fileDef: AnalyzedDefFile, literal: ResolvedLiteral): Result[AnalyzedArgumentType, string] =
  let maybeResolvedLiteralModule = fileDef.scope.findModule(literal.default, literal.loc)
  if maybeResolvedLiteralModule.isErr:
    err(fmt"{literal.loc} bare literal defaults to `{literal.default.name.asl}` but it is not in scope; ensure `@std` auto-injection or an explicit import brings it in")
  else:
    ok(newAnalyzedArgumentType(maybeResolvedLiteralModule.get))