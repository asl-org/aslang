## Resolution of module and generic top-level blocks.

import results, options, strformat, tables, options

import tokenizer
import parser
import argtypes
import funcdefs
import data
import funcs

# ResolvedModule
type ResolvedModule* = ref object
  parsed: Module
  requires: seq[ResolvedGenericArgumentType]
  data: Option[ResolvedData]
  funcDefIndex: Table[ResolvedFunctionDefinition, int]
  functions: seq[ResolvedFunction]
  loc: Location

proc newResolvedModule*(parsed: Module, requires: seq[ResolvedGenericArgumentType], data: Option[ResolvedData], functions: seq[ResolvedFunction], loc: Location): ResolvedModule =
  var funcDefIndex: Table[ResolvedFunctionDefinition, int]
  for id, function in functions:
    assert(function.def notin funcDefIndex, "NOTE: should be unreachable")
    funcDefIndex[function.def] = id
  ResolvedModule(parsed: parsed, requires: requires, data: data, funcDefIndex: funcDefIndex, functions: functions, loc: loc)

proc name*(module: ResolvedModule): Identifier = module.parsed.name
proc requires*(module: ResolvedModule): seq[ResolvedGenericArgumentType] = module.requires
proc data*(module: ResolvedModule): Option[ResolvedData] = module.data
proc functions*(module: ResolvedModule): seq[ResolvedFunction] = module.functions
proc loc*(module: ResolvedModule): Location = module.loc
proc self*(module: ResolvedModule): ResolvedModuleArgumentType =
  var impls: seq[ResolvedArgumentType]
  for generic in module.requires:
    # TODO: Fix this dummy location
    let dummyLocation = newLocation()
    let definedType = newResolvedDefinedArgumentType(generic)
    let argType = newResolvedArgumentType(definedType)
    impls.add(argType)
  newResolvedModuleArgumentType(module.parsed, impls, newLocation())

proc findFunctionDef*(module: ResolvedModule, funcDef: ResolvedFunctionDefinition): Option[ResolvedFunctionDefinition] =
  if funcDef notin module.funcDefIndex:
    none(ResolvedFunctionDefinition)
  else:
    some(module.functions[module.funcDefIndex[funcDef]].def)

proc resolveModule*(app: App, file: parser.File, fileScope: FileScope,
    module: Module): Result[ResolvedModule, string] =
  if module.decorators.len > 0:
    return err("todo: resolve decorators")

  var resolvedRequires: seq[ResolvedGenericArgumentType]
  if module.requires.isSome:
    for generic in module.requires.get.generics:
      let dataType = ? file.findType(generic)
      case dataType.kind:
      of tkImported:
        return err("todo: resolve imported type in requires block")
      of tkDefined:
        let definedType = dataType.definedType
        case definedType.kind:
        of dtkModule:
          return err(fmt"{generic.loc} type `{generic.asl}` is a module but expected generic")
        of dtkGeneric:
          resolvedRequires.add(newResolvedGenericArgumentType(definedType.generic, generic.loc))

  var resolvedData: Option[ResolvedData]
  if module.data.isSome:
    let resolvedDataBlock = ? resolveDataBlock(app, file, fileScope, module,
      module.data.get)
    resolvedData = some(resolvedDataBlock)

  # NOTE: Infer requires list if not explicitly mentioned.
  if module.requires.isNone and resolvedData.isSome:
    resolvedRequires = resolvedData.get.requires

  var resolvedFunctions: seq[ResolvedFunction]
  for function in module.functions:
    let resolvedFunction = ? resolveFunction(app, file, fileScope, module,
      function)
    resolvedFunctions.add(resolvedFunction)

  ok(newResolvedModule(module, resolvedRequires, resolvedData, resolvedFunctions, module.loc))

# ResolvedGeneric
type ResolvedGeneric* = ref object
  parsed: Generic
  funcDefs: seq[ResolvedFunctionDefinition]

proc newResolvedGeneric*(parsed: Generic, funcDefs: seq[ResolvedFunctionDefinition]): ResolvedGeneric =
  ResolvedGeneric(parsed: parsed, funcDefs: funcDefs)

proc self*(generic: ResolvedGeneric): Generic = generic.parsed
proc public*(generic: ResolvedGeneric): bool = generic.parsed.public
proc name*(generic: ResolvedGeneric): Identifier = generic.parsed.name
proc funcDefs*(generic: ResolvedGeneric): seq[ResolvedFunctionDefinition] = generic.funcDefs
proc loc*(generic: ResolvedGeneric): Location = generic.parsed.loc
proc concreteImpls*(generic: ResolvedGeneric, concrete: ResolvedArgumentType): seq[ResolvedFunctionDefinition] =
  var concreteFuncDefs: seq[ResolvedFunctionDefinition]
  for def in generic.funcDefs:
    concreteFuncDefs.add(def.concreteFunctionDefinition(concrete, generic.parsed))
  return concreteFuncDefs

proc resolveGeneric*(app: App, file: parser.File,
    generic: Generic): Result[ResolvedGeneric, string] =
  if generic.decorators.len > 0:
    return err(fmt"{generic.loc} todo: resolve generic decorators")

  var resolvedFunctionDefs: seq[ResolvedFunctionDefinition]
  for funcDef in generic.funcDefs:
    let resolvedFunctionDefinition = ? resolveFunctionDefinition(app, file,
      generic, funcDef)
    resolvedFunctionDefs.add(resolvedFunctionDefinition)

  ok(newResolvedGeneric(generic, resolvedFunctionDefs))
