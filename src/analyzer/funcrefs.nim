## Body-level scopes and the helpers the body walker consumes:
##   - AnalyzedFunctionScope    (variable -> AnalyzedArgumentType)
## plus `findModuleDef`, `extractDataBlock`, `extractStructFor`,
## `extractUnionFor`, `clone`.
##
## Defined-type lookup by Identifier lives directly on
## `ResolvedFileScope` (see argtypes.nim) — post-6c retirement there is
## no separate `AnalyzedDefinedTypeScope`, since every defined type
## carried by the scope is already a `ResolvedDefinedType`.

import results, tables, strformat, options

import parser
import resolver
import argtypes

proc findDefinedType*(fileScope: ResolvedFileScope, name: Identifier, loc: Location): Result[ResolvedDefinedType, string] =
  if name notin fileScope:
    err(fmt"{loc} UNREACHABLE: type `{name.asl}` is not defined")
  else:
    ok(fileScope[name])

proc findModuleDef*(fileScope: ResolvedFileScope, name: Identifier, loc: Location): Result[ResolvedModule, string] =
  let entry = ? fileScope.findDefinedType(name, loc)
  case entry.kind:
  of rdtkModule: ok(entry.module)
  of rdtkGeneric:
    err(fmt"{loc} UNREACHABLE: scope entry `{name.asl}` is a generic but caller expected module")

proc findModuleDef*(fileScope: ResolvedFileScope, argType: AnalyzedArgumentType, loc: Location): Result[ResolvedModule, string] =
  case argType.kind:
  of aatkGeneric:
    err(fmt"{loc} todo: analyze case blocks for generic subject type")
  of aatkModule:
    ok(argType.module.module)

proc extractDataBlock*(fileScope: ResolvedFileScope, module: ResolvedModule, loc: Location): Result[ResolvedData, string] =
  if module.data.isNone:
    err(fmt"{loc} UNREACHABLE: expression does not return a data type")
  else:
    ok(module.data.get)

proc extractDataBlock*(fileScope: ResolvedFileScope, argType: AnalyzedArgumentType, loc: Location): Result[ResolvedData, string] =
  let argModule = ? fileScope.findModuleDef(argType, loc)
  fileScope.extractDataBlock(argModule, loc)

proc extractStructFor*(fileScope: ResolvedFileScope, argType: AnalyzedArgumentType, loc: Location): Result[ResolvedStructDef, string] =
  let argModule = ? fileScope.findModuleDef(argType, loc)
  let dataBlock = ? fileScope.extractDataBlock(argModule, loc)
  case dataBlock.kind:
  of rdkStruct: ok(dataBlock.struct)
  of rdkUnion: err(fmt"{loc} expected module `{argModule.name.asl}` to have a struct block but found union")
  of rdkLiteral: err(fmt"{loc} expected module `{argModule.name.asl}` to have a struct block but found literal")

proc extractUnionFor*(fileScope: ResolvedFileScope, argType: AnalyzedArgumentType, loc: Location): Result[ResolvedUnionDef, string] =
  let argModule = ? fileScope.findModuleDef(argType, loc)
  let dataBlock = ? fileScope.extractDataBlock(argModule, loc)
  case dataBlock.kind:
  of rdkUnion: ok(dataBlock.union)
  of rdkStruct: err(fmt"{loc} expected module `{argModule.name.asl}` to have a union block but found struct")
  of rdkLiteral: err(fmt"{loc} expected module `{argModule.name.asl}` to have a union block but found literal")

type AnalyzedFunctionScope* = Table[Identifier, AnalyzedArgumentType]

proc clone*(scope: AnalyzedFunctionScope): AnalyzedFunctionScope =
  var updated: AnalyzedFunctionScope
  for key, value in scope: updated[key] = value
  return updated
