import results, strformat, options

import parser, resolver

proc analyzeImport*(app: ResolvedApp, file: ResolvedFile, imp: ResolvedImport): Result[void, string] =
  err(fmt"todo: analyze import")

proc analyzeRequire*(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, generic: Generic): Result[void, string] =
  err(fmt"todo: analyze required generic")

proc analyzeLiteralBlock*(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, literal: ResolvedLiteralType): Result[void, string] =
  ok()

proc analyzeData*(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, data: ResolvedData): Result[void, string] =
  case data.kind:
  of rdkLiteral: analyzeLiteralBlock(app, file, module, data.literal)
  of rdkStruct: err(fmt"todo: analyze struct block")
  of rdkUnion: err(fmt"todo: analyze union block")

proc analyzeModuleArgumentType*(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, argType: ResolvedModuleArgumentType): Result[void, string] =
  let resolvedDefinedType: ResolvedDefinedType = ? file.findModule(argType.module.name)
  case resolvedDefinedType.kind:
  of rdtkGeneric: err(fmt"todo: analyze defined generic arg type")
  of rdtkModule:
    let typeModule = resolvedDefinedType.module
    if typeModule.requires.len == 0:
      if argType.impls.len == 0:
        ok()
      else:
        err(fmt"{argType.loc} module `{argType.module.name.asl}` does not require any impl types")
    else:
      err(fmt"{argType.loc} todo: analyze defined module arg type")

proc analyzeDefinedArgumentType*(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, argType: ResolvedDefinedArgumentType): Result[void, string] =
  case argType.kind:
  of rdatkGeneric: err(fmt"todo: analyze defined generic arg type")
  of rdatkModule: analyzeModuleArgumentType(app, file, module, argType.module)

proc analyzeArgumentType*(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, argType: ResolvedArgumentType): Result[void, string] =
  case argType.kind:
  of ratkImported: err(fmt"todo: analyze imported argument type")
  of ratkDefined: analyzeDefinedArgumentType(app, file, module, argType.definedType)

proc analyzeArgumentDefinition*(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, argDef: ResolvedArgumentDefinition): Result[void, string] =
  analyzeArgumentType(app, file, module, argDef.argType)

proc analyzeFunctionDefinition*(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, funcDef: ResolvedFunctionDefinition): Result[void, string] =
  for arg in funcDef.args:
    ? analyzeArgumentDefinition(app, file, module, arg)

  analyzeArgumentType(app, file, module, funcDef.returns)

proc analyzeExternFunction*(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, function: ResolvedExternFunction): Result[void, string] =
  analyzeFunctionDefinition(app, file, module, function.def)

proc analyzeFunction*(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, function: ResolvedFunction): Result[void, string] =
  case function.kind:
  of rfkExtern: analyzeExternFunction(app, file, module, function.extern)
  of rfkUser: err(fmt"todo: analyze user function")

proc analyzeModule*(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule): Result[void, string] =
  for generic in module.requires:
    ? analyzeRequire(app, file, module, generic)

  if module.data.isSome:
    ? analyzeData(app, file, module, module.data.get)

  for function in module.functions:
    ? analyzeFunction(app, file, module, function)

  err(fmt"todo: analyze defined module")

proc analyzeDefinedType*(app: ResolvedApp, file: ResolvedFile, definedType: ResolvedDefinedType): Result[void, string] =
  case definedType.kind:
  of rdtkGeneric: err(fmt"todo: analyze defined generic type")
  of rdtkModule: analyzeModule(app, file, definedType.module)

proc analyzeFile*(app: ResolvedApp, file: ResolvedFile): Result[void, string] =
  for imp in file.imports:
    ? analyzeImport(app, file, imp)

  for definedType in file.definedTypes:
    ? analyzeDefinedType(app, file, definedType)
  err(fmt"todo: analyze file")

proc analyze*(app: ResolvedApp): Result[void, string] =
  for file in app.files:
    let maybeAnalyzedFile = analyzeFile(app, file)
    if maybeAnalyzedFile.isErr:
      return err(fmt"{file.path}:{maybeAnalyzedFile.error}")
  err(fmt"todo: analyze app")