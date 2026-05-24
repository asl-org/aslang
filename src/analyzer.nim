import results, strformat, options, sequtils, tables

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

type
  AnalyzedModuleArgumentType = ref object
    module: ResolvedModule
    impls: seq[AnalyzedArgumentType]

  AnalyzedDefinedArgumentTypeKind = enum
    adatkModule, adatkGeneric

  AnalyzedDefinedArgumentType = ref object
    case kind: AnalyzedDefinedArgumentTypeKind
    of adatkModule: module: AnalyzedModuleArgumentType
    of adatkGeneric: generic: ResolvedGeneric

  AnalyzedArgumentTypeKind = enum
    aatkImported, aatkDefined

  AnalyzedArgumentType = ref object
    case kind: AnalyzedArgumentTypeKind
    of aatkImported: discard
    of aatkDefined: definedType: AnalyzedDefinedArgumentType

proc analyzeArgumentType*(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, argType: ResolvedArgumentType): Result[AnalyzedArgumentType, string]

proc newAnalyzedModuleArgumentType(module: ResolvedModule, impls: seq[AnalyzedArgumentType]): AnalyzedModuleArgumentType =
  AnalyzedModuleArgumentType(module: module, impls: impls)

proc newAnalyzedModuleArgumentType(module: ResolvedModule): AnalyzedModuleArgumentType =
  newAnalyzedModuleArgumentType(module, @[])

proc self(argType: AnalyzedModuleArgumentType): ResolvedModuleArgumentType = argType.module.self

proc newAnalyzedDefinedArgumentType(module: AnalyzedModuleArgumentType): AnalyzedDefinedArgumentType =
  AnalyzedDefinedArgumentType(kind: adatkModule, module: module)

proc newAnalyzedDefinedArgumentType(generic: ResolvedGeneric): AnalyzedDefinedArgumentType =
  AnalyzedDefinedArgumentType(kind: adatkGeneric, generic: generic)

proc self(argType: AnalyzedDefinedArgumentType): ResolvedDefinedArgumentType =
  case argType.kind:
  of adatkModule: newResolvedDefinedArgumentType(argType.module.self)
  of adatkGeneric: newResolvedDefinedArgumentType(argType.generic.self)

proc newAnalyzedArgumentType(definedType: AnalyzedDefinedArgumentType): AnalyzedArgumentType =
  AnalyzedArgumentType(kind: aatkDefined, definedType: definedType)

proc self(argType: AnalyzedArgumentType): ResolvedArgumentType =
  case argType.kind:
  of aatkImported: assert(false, "TODO: support analyzed argument type self construction")
  of aatkDefined: return newResolvedArgumentType(argType.definedType.self)

proc analyzeModuleArgumentType*(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, argType: ResolvedModuleArgumentType): Result[AnalyzedModuleArgumentType, string] =
  let typeModule = ? file.findModule(argType.module.name)
  if typeModule.requires.len != argType.impls.len:
    if typeModule.requires.len == 0:
      err(fmt"{argType.loc} module `{argType.module.name.asl}` does not require any impl types")
    else:
      err(fmt"{argType.loc} module `{argType.module.name.asl}` requires `{typeModule.requires.len}` impl types but found `{argType.impls.len}`")
  else:
    var analyzedImpls: seq[AnalyzedArgumentType]
    for (requiredImpl, targetImpl) in zip(typeModule.requires, argType.impls):
      let resolvedGeneric = ? file.findGeneric(requiredImpl.name)
      let analyzedImpl = ? analyzeArgumentType(app, file, module, targetImpl)
      let funcDefs = resolvedGeneric.concreteImpls(analyzedImpl.self)
      for funcDef in funcDefs:
        case analyzedImpl.kind:
        of aatkImported:
          return err(fmt"{targetImpl.loc} todo: analyze imported impl type")
        of aatkDefined:
          case analyzedImpl.definedType.kind:
          of adatkGeneric:
            return err(fmt"{targetImpl.loc} todo: analyze defined generic impl type")
          of adatkModule:
            let maybeConcreteFuncDef = analyzedImpl.definedType.module.module.findFunctionDef(funcDef)
            if maybeConcreteFuncDef.isNone:
              return err(fmt"{targetImpl.loc} type `{targetImpl.name.asl}` does not implement function `{funcDef.name.asl}` to support `{resolvedGeneric.name.asl}`")
            else:
              analyzedImpls.add(analyzedImpl)
    ok(newAnalyzedModuleArgumentType(typeModule, analyzedImpls))

proc analyzeDefinedArgumentType*(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, argType: ResolvedDefinedArgumentType): Result[AnalyzedDefinedArgumentType, string] =
  case argType.kind:
  of rdatkGeneric:
    err(fmt"todo: analyze defined generic arg type")
  of rdatkModule:
    let analyzedArgType = ? analyzeModuleArgumentType(app, file, module, argType.module)
    ok(newAnalyzedDefinedArgumentType(analyzedArgType))

proc analyzeArgumentType*(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, argType: ResolvedArgumentType): Result[AnalyzedArgumentType, string] =
  case argType.kind:
  of ratkImported: err(fmt"todo: analyze imported argument type")
  of ratkDefined:
    let analyzedArgType = ? analyzeDefinedArgumentType(app, file, module, argType.definedType)
    ok(newAnalyzedArgumentType(analyzedArgType))

type AnalyzedArgumentDefinition = ref object
  argType: AnalyzedArgumentType
  name: Identifier

proc newAnalyzedArgumentDefinition(argType: AnalyzedArgumentType, name: Identifier): AnalyzedArgumentDefinition =
  AnalyzedArgumentDefinition(argType: argType, name: name)

proc analyzeArgumentDefinition*(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, argDef: ResolvedArgumentDefinition): Result[AnalyzedArgumentDefinition, string] =
  let analyzedArgType = ? analyzeArgumentType(app, file, module, argDef.argType)
  ok(newAnalyzedArgumentDefinition(analyzedArgType, argDef.name))

type AnalyzedFunctionDefinition = ref object
  name: Identifier
  args: seq[AnalyzedArgumentDefinition]
  returns: AnalyzedArgumentType

proc newAnalyzedFunctionDefinition(name: Identifier, args: seq[AnalyzedArgumentDefinition], returns: AnalyzedArgumentType): AnalyzedFunctionDefinition =
  AnalyzedFunctionDefinition(name: name, args: args, returns: returns)

proc analyzeFunctionDefinition*(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, funcDef: ResolvedFunctionDefinition): Result[AnalyzedFunctionDefinition, string] =
  var analyzedArgDefs: seq[AnalyzedArgumentDefinition]
  for arg in funcDef.args:
    let analyzedArgDef = ? analyzeArgumentDefinition(app, file, module, arg)
    analyzedArgDefs.add(analyzedArgDef)

  let analyzedReturns = ? analyzeArgumentType(app, file, module, funcDef.returns)
  ok(newAnalyzedFunctionDefinition(funcDef.name, analyzedArgDefs, analyzedReturns))

type AnalyzedExternFunction = ref object
  funcDef: AnalyzedFunctionDefinition
  ffi: string

proc newAnalyzedExternFunction(funcDef: AnalyzedFunctionDefinition, ffi: string): AnalyzedExternFunction =
  AnalyzedExternFunction(funcDef: funcDef, ffi: ffi)

proc analyzeExternFunction*(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, function: ResolvedExternFunction): Result[AnalyzedExternFunction, string] =
  let analyzedFuncDef = ? analyzeFunctionDefinition(app, file, module, function.def)
  ok(newAnalyzedExternFunction(analyzedFuncDef, function.ffi))

proc analyzeFunctionRef(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, funcRef: ResolvedFunctionRef): Result[void, string] =
  err(fmt"{funcRef.loc} todo: analyze function ref")

proc analyzeExpression(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, scope: Table[Identifier, AnalyzedArgumentDefinition], expression: ResolvedExpression): Result[void, string]

proc analyzeFunctionCall(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, scope: Table[Identifier, AnalyzedArgumentDefinition], fncall: ResolvedFunctionCall): Result[void, string] =
  ? analyzeFunctionRef(app, file, module, fncall.funcRef)
  for arg in fncall.args:
    ? analyzeExpression(app, file, module, scope, arg)
  err(fmt"{fncall.loc} todo: analyze function call")

proc analyzeExpression(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, scope: Table[Identifier, AnalyzedArgumentDefinition], expression: ResolvedExpression): Result[void, string] =
  case expression.kind:
  of rekGetter: err(fmt"{expression.loc} todo: analyze getter")
  of rekInitializer: err(fmt"{expression.loc} todo: analyze initializer")
  of rekVariable: err(fmt"{expression.loc} todo: analyze variable")
  of rekLiteral: err(fmt"{expression.loc} todo: analyze literal")
  of rekMatchExpr: err(fmt"{expression.loc} todo: analyze match block")
  of rekFunctionCall: analyzeFunctionCall(app, file, module, scope, expression.fncall)

proc analyzeStatement(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, scope: Table[Identifier, AnalyzedArgumentDefinition], statement: ResolvedStatement): Result[void, string] =
  case statement.kind:
  of rskAssignment: err(fmt"{statement.loc} todo: analyze assignment")
  of rskMutation: err(fmt"{statement.loc} todo: analyze mutation")
  of rskExpr: analyzeExpression(app, file, module, scope, statement.expression)

proc analyzeUserFunction(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, function: ResolvedUserFunction): Result[void, string] =
  let analyzedFuncDef = ? analyzeFunctionDefinition(app, file, module, function.def)
  var scope: Table[Identifier, AnalyzedArgumentDefinition]
  for arg in analyzedFuncDef.args:
    assert(arg.name notin scope, "UNREACHABLE: function definition can not have same param name in different positions")
    scope[arg.name] = arg
  for statement in function.statements:
    ? analyzeStatement(app, file, module, scope, statement)
  ok()

type
  AnalyzedFunctionKind = enum
    afkExtern, afkUser
  AnalyzedFunction = ref object
    case kind: AnalyzedFunctionKind
    of afkExtern: extern: AnalyzedExternFunction
    of afkUser: discard

proc newAnalyzedFunction(extern: AnalyzedExternFunction): AnalyzedFunction =
  AnalyzedFunction(kind: afkExtern, extern: extern)

proc analyzeFunction*(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, function: ResolvedFunction): Result[AnalyzedFunction, string] =
  case function.kind:
  of rfkExtern:
    let analyzedExternFn = ? analyzeExternFunction(app, file, module, function.extern)
    ok(newAnalyzedFunction(analyzedExternFn))
  of rfkUser:
    ? analyzeUserFunction(app, file, module, function.user)
    err(fmt"REMOVE THIS LATER")

type AnalyzedModule = ref object
  functions: seq[AnalyzedFunction]

proc newAnalyzedModule(functions: seq[AnalyzedFunction]): AnalyzedModule =
  AnalyzedModule(functions: functions)

proc analyzeModule*(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule): Result[AnalyzedModule, string] =
  for generic in module.requires:
    ? analyzeRequire(app, file, module, generic)

  if module.data.isSome:
    ? analyzeData(app, file, module, module.data.get)

  var analyzedFunctions: seq[AnalyzedFunction]
  for function in module.functions:
    let analyzedFn = ? analyzeFunction(app, file, module, function)
    analyzedFunctions.add(analyzedFn)

  ok(newAnalyzedModule(analyzedFunctions))

type
  AnalyzedDefinedTypeKind = enum
    adtkModule, adtkGeneric
  AnalyzedDefinedType = ref object
    case kind: AnalyzedDefinedTypeKind
    of adtkModule: module: AnalyzedModule
    of adtkGeneric: discard

proc newAnalyzedDefinedType(module: AnalyzedModule): AnalyzedDefinedType =
  AnalyzedDefinedType(kind: adtkModule, module: module)

proc analyzeDefinedType*(app: ResolvedApp, file: ResolvedFile, definedType: ResolvedType): Result[AnalyzedDefinedType, string] =
  case definedType.kind:
  of rtkGeneric: err(fmt"todo: analyze defined generic type")
  of rtkModule:
    let analyzedModule = ? analyzeModule(app, file, definedType.module)
    ok(newAnalyzedDefinedType(analyzedModule))

proc analyzeFile*(app: ResolvedApp, file: ResolvedFile): Result[void, string] =
  for imp in file.imports:
    ? analyzeImport(app, file, imp)

  var analyzedDefinedTypes: seq[AnalyzedDefinedType]
  for aslType in file.aslTypes:
    let analyzedDefinedType = ? analyzeDefinedType(app, file, aslType)
    analyzedDefinedTypes.add(analyzedDefinedType)
  err(fmt"todo: analyze file")

proc analyze*(app: ResolvedApp): Result[void, string] =
  for file in app.files:
    let maybeAnalyzedFile = analyzeFile(app, file)
    if maybeAnalyzedFile.isErr:
      return err(fmt"{file.path}:{maybeAnalyzedFile.error}")
  err(fmt"todo: analyze app")