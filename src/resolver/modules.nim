## Resolution of module and generic top-level blocks.

import results, options, strformat

import tokenizer
import parser
import argtypes
import funcdefs
import data
import funcs

# ResolvedModule
type ResolvedModule* = ref object
  name: Identifier
  requires: seq[Generic]
  data: Option[ResolvedData]
  functions: seq[ResolvedFunction]
  loc: Location

proc newResolvedModule*(name: Identifier, requires: seq[Generic], data: Option[ResolvedData], functions: seq[ResolvedFunction], loc: Location): ResolvedModule =
  ResolvedModule(name: name, requires: requires, data: data, functions: functions, loc: loc)

proc name*(module: ResolvedModule): Identifier = module.name
proc requires*(module: ResolvedModule): seq[Generic] = module.requires
proc data*(module: ResolvedModule): Option[ResolvedData] = module.data
proc functions*(module: ResolvedModule): seq[ResolvedFunction] = module.functions
proc loc*(module: ResolvedModule): Location = module.loc

proc resolveModule*(app: App, file: parser.File, fileScope: FileScope,
    module: Module): Result[ResolvedModule, string] =
  if module.decorators.len > 0:
    return err("todo: resolve decorators")

  var resolvedRequires: seq[Generic]
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
          resolvedRequires.add(definedType.generic)

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

  ok(newResolvedModule(module.name, resolvedRequires, resolvedData, resolvedFunctions, module.loc))

# ResolvedGeneric
type ResolvedGeneric* = ref object
  public: bool
  name: Identifier
  funcDefs: seq[ResolvedFunctionDefinition]
  loc: Location

proc newResolvedGeneric*(public: bool, name: Identifier, funcDefs: seq[ResolvedFunctionDefinition], loc: Location): ResolvedGeneric =
  ResolvedGeneric(public: public, name: name, funcDefs: funcDefs)

proc public*(generic: ResolvedGeneric): bool = generic.public
proc name*(generic: ResolvedGeneric): Identifier = generic.name
proc funcDefs*(generic: ResolvedGeneric): seq[ResolvedFunctionDefinition] = generic.funcDefs
proc loc*(generic: ResolvedGeneric): Location = generic.loc

proc resolveGeneric*(app: App, file: parser.File,
    generic: Generic): Result[ResolvedGeneric, string] =
  if generic.decorators.len > 0:
    return err(fmt"{generic.loc} todo: resolve generic decorators")

  var resolvedFunctionDefs: seq[ResolvedFunctionDefinition]
  for funcDef in generic.funcDefs:
    let resolvedFunctionDefinition = ? resolveFunctionDefinition(app, file,
      generic, funcDef)
    resolvedFunctionDefs.add(resolvedFunctionDefinition)

  ok(newResolvedGeneric(generic.public, generic.name, resolvedFunctionDefs, generic.loc))
