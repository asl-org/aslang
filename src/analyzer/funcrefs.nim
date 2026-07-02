## Body-level scopes and the helpers the body walker consumes:
##   - AnalyzedDefinedTypeScope (module/generic lookup by Identifier)
##   - AnalyzedFunctionScope    (variable -> AnalyzedArgumentType)
## plus `findDefinedType`, `findModuleDef`, `extractDataBlock`,
## `extractStructFor`, `extractUnionFor`, `clone`.
##
## The funcref validation that used to live here
## (AnalyzedFunctionRef + analyzeFunctionRef) is inlined into
## analyzeFunctionCall now that FunctionCall carries just an
## Identifier root.

import results, tables, strformat, options

import tokenizer
import parser
import argtypes
import data
import modules

type AnalyzedDefinedTypeScope* = Table[Identifier, AnalyzedDefinedType]

proc findDefinedType*(defScope: AnalyzedDefinedTypeScope, name: Identifier, loc: Location): Result[AnalyzedDefinedType, string] =
  if name notin defScope:
    err(fmt"{loc} UNREACHABLE: type `{name.asl}` is not defined")
  else:
    ok(defScope[name])

proc findModuleDef*(defScope: AnalyzedDefinedTypeScope, name: Identifier, loc: Location): Result[AnalyzedModuleDefinition, string] =
  let entry = ? defScope.findDefinedType(name, loc)
  case entry.kind:
  of adtkModule: ok(entry.module)
  of adtkGeneric:
    err(fmt"{loc} UNREACHABLE: scope entry `{name.asl}` is a generic but caller expected module")

proc findModuleDef*(defScope: AnalyzedDefinedTypeScope, argType: AnalyzedArgumentType, loc: Location): Result[AnalyzedModuleDefinition, string] =
  case argType.kind:
  of aatkGeneric:
    err(fmt"{loc} todo: analyze case blocks for generic subject type")
  of aatkModule:
    let moduleArgType = argType.module
    if moduleArgType.name notin defScope:
      err(fmt"{loc} UNREACHABLE: module `{moduleArgType.name.asl}` is not defined")
    else:
      let entry = defScope[moduleArgType.name]
      case entry.kind:
      of adtkModule: ok(entry.module)
      of adtkGeneric:
        err(fmt"{loc} UNREACHABLE: scope entry `{moduleArgType.name.asl}` is a generic but argType claims module")

proc extractDataBlock*(defScope: AnalyzedDefinedTypeScope, module: AnalyzedModuleDefinition, loc: Location): Result[AnalyzedData, string] =
  if module.data.isNone:
    err(fmt"{loc} UNREACHABLE: expression does not return a data type")
  else:
    ok(module.data.get)

proc extractDataBlock*(defScope: AnalyzedDefinedTypeScope, argType: AnalyzedArgumentType, loc: Location): Result[AnalyzedData, string] =
  let argModule = ? defScope.findModuleDef(argType, loc)
  defScope.extractDataBlock(argModule, loc)

proc extractStructFor*(defScope: AnalyzedDefinedTypeScope, argType: AnalyzedArgumentType, loc: Location): Result[AnalyzedStructDef, string] =
  let argModule = ? defScope.findModuleDef(argType, loc)
  let dataBlock = ? defScope.extractDataBlock(argModule, loc)
  case dataBlock.kind:
  of adkStruct: ok(dataBlock.struct)
  of adkUnion: err(fmt"{loc} expected module `{argModule.name.asl}` to have a struct block but found union")
  of adkLiteral: err(fmt"{loc} expected module `{argModule.name.asl}` to have a struct block but found literal")

proc extractUnionFor*(defScope: AnalyzedDefinedTypeScope, argType: AnalyzedArgumentType, loc: Location): Result[AnalyzedUnionDef, string] =
  let argModule = ? defScope.findModuleDef(argType, loc)
  let dataBlock = ? defScope.extractDataBlock(argModule, loc)
  case dataBlock.kind:
  of adkUnion: ok(dataBlock.union)
  of adkStruct: err(fmt"{loc} expected module `{argModule.name.asl}` to have a union block but found struct")
  of adkLiteral: err(fmt"{loc} expected module `{argModule.name.asl}` to have a union block but found literal")

type AnalyzedFunctionScope* = Table[Identifier, AnalyzedArgumentType]

proc clone*(scope: AnalyzedFunctionScope): AnalyzedFunctionScope =
  var updated: AnalyzedFunctionScope
  for key, value in scope: updated[key] = value
  return updated
