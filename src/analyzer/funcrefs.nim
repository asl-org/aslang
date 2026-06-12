## Function references for call-site analysis: given an analyzed
## ArgumentType + (name, arity), look up candidate function
## definitions inside the target generic or module. The analyzer
## collects candidates and refines them with overload selection
## downstream (in body.nim).
##
## Also owns the body-level scopes:
##   - AnalyzedDefinedTypeScope (module/generic lookup by Identifier)
##   - AnalyzedFunctionScope    (variable -> AnalyzedArgumentType)
## plus the helpers (`findModuleDef`, `extractDataBlock`,
## `extractStructFor`, `extractUnionFor`, `clone`) that the body
## cluster consumes.

import results, tables, strformat, options

import tokenizer
import parser
import resolver
import argtypes
import data
import funcdefs
import modules

type AnalyzedDefinedTypeScope* = Table[Identifier, AnalyzedDefinedType]

proc findModuleDef*(defScope: AnalyzedDefinedTypeScope, name: Identifier, loc: Location): Result[AnalyzedModuleDefinition, string] =
  if name notin defScope:
    err(fmt"{loc} UNREACHABLE: module `{name.asl}` is not defined")
  else:
    let entry = defScope[name]
    case entry.kind:
    of adtkModule: ok(entry.module)
    of adtkGeneric:
      err(fmt"{loc} UNREACHABLE: scope entry `{name.asl}` is a generic but caller expected module")

proc findModuleDef*(defScope: AnalyzedDefinedTypeScope, argType: AnalyzedArgumentType, loc: Location): Result[AnalyzedModuleDefinition, string] =
  case argType.kind:
  of aatkImported:
    err(fmt"{loc} todo: analyze case blocks for imported subject type")
  of aatkDefined:
    let definedArgType = argType.definedType
    case definedArgType.kind:
    of adatkGeneric:
      err(fmt"{loc} todo: analyze case blocks for generic subject type")
    of adatkModule:
      let moduleArgType = definedArgType.module
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

proc extractStructFor*(defScope: AnalyzedDefinedTypeScope, argType: AnalyzedArgumentType, loc: Location): Result[AnalyzedStruct, string] =
  let argModule = ? defScope.findModuleDef(argType, loc)
  let dataBlock = ? defScope.extractDataBlock(argModule, loc)
  case dataBlock.kind:
  of adkStruct: ok(dataBlock.struct)
  of adkUnion: err(fmt"{loc} expected module `{argModule.name.asl}` to have a struct block but found union")
  of adkLiteral: err(fmt"{loc} expected module `{argModule.name.asl}` to have a struct block but found literal")

proc extractUnionFor*(defScope: AnalyzedDefinedTypeScope, argType: AnalyzedArgumentType, loc: Location): Result[AnalyzedUnion, string] =
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

type AnalyzedFunctionRef* = ref object
  resolved: ResolvedFunctionRef
  argType: AnalyzedArgumentType
  funcDefs: seq[AnalyzedFunctionDefinition]

proc newAnalyzedFunctionRef*(resolved: ResolvedFunctionRef, argType: AnalyzedArgumentType, funcDefs: seq[AnalyzedFunctionDefinition]): AnalyzedFunctionRef =
  AnalyzedFunctionRef(resolved: resolved, argType: argType, funcDefs: funcDefs)

proc resolved*(fnref: AnalyzedFunctionRef): ResolvedFunctionRef = fnref.resolved
proc loc*(fnref: AnalyzedFunctionRef): Location = fnref.resolved.loc
proc name*(fnref: AnalyzedFunctionRef): Identifier = fnref.resolved.name
proc arity*(fnref: AnalyzedFunctionRef): int = fnref.resolved.arity
proc argType*(fnref: AnalyzedFunctionRef): AnalyzedArgumentType = fnref.argType
proc funcDefs*(fnref: AnalyzedFunctionRef): seq[AnalyzedFunctionDefinition] = fnref.funcDefs

proc analyzeFunctionRef*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, fnref: ResolvedFunctionRef): Result[AnalyzedFunctionRef, string] =
  let argType = ? analyzeArgumentType(app, file, fileScope, module, fnref.argType)
  case argType.kind:
  of aatkImported: err(fmt"{fnref.loc} todo: analyze imported type function ref")
  of aatkDefined:
    let definedType = argType.definedType
    case definedType.kind:
    of adatkGeneric:
      let genericType = definedType.generic
      if genericType.name notin defScope:
        err(fmt"{fnref.loc} [UNREACHABLE] module `{genericType.name.asl}` does not exist in scope")
      else:
        let genericDef = defScope[genericType.name].generic
        # NOTE: if the function call is to other module then only it should have public accessor
        let funcDefs = ? genericDef.findFunctionDefs(fnref.name, fnref.arity)
        ok(newAnalyzedFunctionRef(fnref, argType, funcDefs))
    of adatkModule:
      let moduleType = definedType.module
      if moduleType.module.name notin defScope:
        err(fmt"{fnref.loc} [UNREACHABLE] module `{moduleType.module.name.asl}` does not exist in scope")
      else:
        let moduleDef = defScope[moduleType.module.name].module
        # NOTE: if the function call is to other module then only it should have public accessor
        let funcDefs = ? moduleDef.findFunctionDefs(fnref.name, fnref.arity, module != moduleDef.resolved)
        ok(newAnalyzedFunctionRef(fnref, argType, funcDefs))
