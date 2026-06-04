## Analyzed argument-type cluster.
##
## Mirrors the resolver's argtypes layout: AnalyzedGenericArgumentType,
## AnalyzedModuleArgumentType, AnalyzedDefinedArgumentType, and
## AnalyzedArgumentType live here together because they cycle through
## one another (a module's `impls` is a seq of argument types). Both
## context overloads (module ctx with AnalyzedFileScope, generic ctx)
## of analyzeGenericArgumentType / analyzeModuleArgumentType /
## analyzeDefinedArgumentType / analyzeArgumentType live here too.

import results, strformat, options, sequtils, tables

import tokenizer
import parser
import resolver

# AnalyzedFileScope — Identifier (binding name) → ResolvedDefinedType
# (the imported defined type pulled in from the source file).
type AnalyzedFileScope* = Table[Identifier, ResolvedDefinedType]

# AnalyzedGenericArgumentType — wraps a ResolvedGeneric with the
# use-site location so analyzer diagnostics can point precisely.
type AnalyzedGenericArgumentType* = ref object
  resolved: ResolvedGeneric
  loc: Location

proc newAnalyzedGenericArgumentType*(resolved: ResolvedGeneric, loc: Location): AnalyzedGenericArgumentType =
  AnalyzedGenericArgumentType(resolved: resolved, loc: loc)

proc resolved*(g: AnalyzedGenericArgumentType): ResolvedGeneric = g.resolved
proc loc*(g: AnalyzedGenericArgumentType): Location = g.loc

proc analyzeGenericArgumentType*(app: ResolvedApp, file: ResolvedFile, generic: ResolvedGeneric, genericArgType: ResolvedGenericArgumentType): Result[AnalyzedGenericArgumentType, string] =
  let genericArg = ? file.findGeneric(genericArgType.parsed.name)
  if genericArg != generic:
    err(fmt"{genericArgType.loc} generic `{genericArgType.parsed.name.asl}` does not exists in the file `{file.path}` scope")
  else:
    ok(newAnalyzedGenericArgumentType(genericArg, genericArgType.loc))

proc analyzeGenericArgumentType*(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, genericArgType: ResolvedGenericArgumentType): Result[AnalyzedGenericArgumentType, string] =
  let maybeGenericArg = file.findGeneric(genericArgType.parsed.name)
  if maybeGenericArg.isErr:
    err(fmt"{genericArgType.loc} analyze imported generic `{genericArgType.parsed.name.asl}`")
  else:
    let genericArg = maybeGenericArg.get
    ok(newAnalyzedGenericArgumentType(genericArg, genericArgType.loc))

# Mutually-recursive cluster: AnalyzedModuleArgumentType's impls
# field references AnalyzedArgumentType, which case-dispatches into
# AnalyzedDefinedArgumentType, which case-dispatches back into
# AnalyzedModuleArgumentType. One `type:` block.
type
  AnalyzedModuleArgumentType* = ref object
    resolved: ResolvedModuleArgumentType
    module: ResolvedModule
    impls: seq[AnalyzedArgumentType]

  AnalyzedDefinedArgumentTypeKind* = enum
    adatkModule, adatkGeneric

  AnalyzedDefinedArgumentType* = ref object
    case kind: AnalyzedDefinedArgumentTypeKind
    of adatkModule: module: AnalyzedModuleArgumentType
    of adatkGeneric: generic: AnalyzedGenericArgumentType

  AnalyzedArgumentTypeKind* = enum
    aatkImported, aatkDefined

  AnalyzedArgumentType* = ref object
    case kind: AnalyzedArgumentTypeKind
    of aatkImported: discard
    of aatkDefined: definedType: AnalyzedDefinedArgumentType

# Forward declarations for the dual-context overloads — both arities
# of analyzeArgumentType need to be visible inside
# analyzeModuleArgumentType.
proc analyzeArgumentType*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, argType: ResolvedArgumentType): Result[AnalyzedArgumentType, string]
proc analyzeArgumentType*(app: ResolvedApp, file: ResolvedFile, generic: ResolvedGeneric, argType: ResolvedArgumentType): Result[AnalyzedArgumentType, string]

# Constructors + accessors + self for the cluster.
proc newAnalyzedModuleArgumentType*(resolved: ResolvedModuleArgumentType, module: ResolvedModule, impls: seq[AnalyzedArgumentType]): AnalyzedModuleArgumentType =
  AnalyzedModuleArgumentType(resolved: resolved, module: module, impls: impls)

proc newAnalyzedModuleArgumentType*(resolved: ResolvedModuleArgumentType, module: ResolvedModule): AnalyzedModuleArgumentType =
  newAnalyzedModuleArgumentType(resolved, module, @[])

proc loc*(m: AnalyzedModuleArgumentType): Location = m.resolved.loc
proc module*(m: AnalyzedModuleArgumentType): ResolvedModule = m.module
proc impls*(m: AnalyzedModuleArgumentType): seq[AnalyzedArgumentType] = m.impls
proc name*(m: AnalyzedModuleArgumentType): Identifier = m.module.name

proc self(argType: AnalyzedModuleArgumentType): ResolvedModuleArgumentType = argType.module.self

proc newAnalyzedDefinedArgumentType*(module: AnalyzedModuleArgumentType): AnalyzedDefinedArgumentType =
  AnalyzedDefinedArgumentType(kind: adatkModule, module: module)

proc newAnalyzedDefinedArgumentType*(generic: AnalyzedGenericArgumentType): AnalyzedDefinedArgumentType =
  AnalyzedDefinedArgumentType(kind: adatkGeneric, generic: generic)

proc kind*(d: AnalyzedDefinedArgumentType): AnalyzedDefinedArgumentTypeKind = d.kind
proc module*(d: AnalyzedDefinedArgumentType): AnalyzedModuleArgumentType = d.module
proc generic*(d: AnalyzedDefinedArgumentType): AnalyzedGenericArgumentType = d.generic
proc loc*(m: AnalyzedDefinedArgumentType): Location =
  case m.kind:
  of adatkModule: m.module.loc
  of adatkGeneric: m.generic.loc

proc self(argType: AnalyzedDefinedArgumentType): ResolvedDefinedArgumentType =
  case argType.kind:
  of adatkModule: newResolvedDefinedArgumentType(argType.module.self)
  of adatkGeneric:
    # TODO: Fix this dummy location
    let dummyLocation = newLocation()
    newResolvedDefinedArgumentType(newResolvedGenericArgumentType(argType.generic.resolved.self, dummyLocation))

proc newAnalyzedArgumentType*(definedType: AnalyzedDefinedArgumentType): AnalyzedArgumentType =
  AnalyzedArgumentType(kind: aatkDefined, definedType: definedType)

proc kind*(a: AnalyzedArgumentType): AnalyzedArgumentTypeKind = a.kind
proc definedType*(a: AnalyzedArgumentType): AnalyzedDefinedArgumentType = a.definedType

proc loc*(argType: AnalyzedArgumentType): Location =
  case argType.kind:
  of aatkImported: assert(false, "TODO: support analyzed argument type location")
  of aatkDefined: return argType.definedType.loc

proc self(argType: AnalyzedArgumentType): ResolvedArgumentType =
  case argType.kind:
  of aatkImported: assert(false, "TODO: support analyzed argument type self construction")
  of aatkDefined: return newResolvedArgumentType(argType.definedType.self)

proc analyzeModuleArgumentType*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, argType: ResolvedModuleArgumentType): Result[AnalyzedModuleArgumentType, string] =
  var typeModule: ResolvedModule
  let maybeTypeModule = file.findModule(argType.module.name)
  if maybeTypeModule.isErr:
    if argType.module.name notin fileScope:
      return err(fmt"{argType.loc} module `{argType.module.name.asl}` is neither defined nor imported")
    else:
      let importedDefinedType = fileScope[argType.module.name]
      case importedDefinedType.kind:
      of rdtkModule:
        typeModule = importedDefinedType.module
      of rdtkGeneric:
        return err(fmt"[UNREACHABLE] {argType.loc} expected `{argType.module.name.asl}` to be a module but found generic.")
  else:
    typeModule = maybeTypeModule.value

  if typeModule.requires.len != argType.impls.len:
    if typeModule.requires.len == 0:
      err(fmt"{argType.loc} module `{argType.module.name.asl}` does not require any impl types")
    else:
      err(fmt"{argType.loc} module `{argType.module.name.asl}` requires `{typeModule.requires.len}` impl types but found `{argType.impls.len}`")
  else:
    var analyzedImpls: seq[AnalyzedArgumentType]
    for (requiredImpl, targetImpl) in zip(typeModule.requires, argType.impls):
      var resolvedGeneric: ResolvedGeneric
      let maybeResolvedGeneric = file.findGeneric(requiredImpl.name)
      if maybeResolvedGeneric.isErr:
        if requiredImpl.name notin fileScope:
          return err(fmt"{argType.loc} analyze imported generic")
        else:
          let definedImportedGeneric = fileScope[requiredImpl.name]
          case definedImportedGeneric.kind:
          of rdtkModule:
            return err(fmt"[UNREACHABLE] {targetImpl.loc} expected `{requiredImpl.name.asl}` to be a generic but found module.")
          of rdtkGeneric:
            resolvedGeneric = definedImportedGeneric.generic
      else:
        resolvedGeneric = maybeResolvedGeneric.value

      let analyzedImpl = ? analyzeArgumentType(app, file, fileScope, module, targetImpl)
      let funcDefs = resolvedGeneric.concreteImpls(analyzedImpl.self)
      for funcDef in funcDefs:
        case analyzedImpl.kind:
        of aatkImported:
          return err(fmt"{targetImpl.loc} todo: analyze imported impl type")
        of aatkDefined:
          case analyzedImpl.definedType.kind:
          of adatkGeneric:
            let maybeConcreteFuncDef = analyzedImpl.definedType.generic.resolved.findFunctionDef(funcDef)
            if maybeConcreteFuncDef.isNone:
              return err(fmt"{targetImpl.loc} type `{targetImpl.name.asl}` does not implement function `{funcDef.name.asl}` to support `{resolvedGeneric.name.asl}`")
            else:
              analyzedImpls.add(analyzedImpl)
          of adatkModule:
            let maybeConcreteFuncDef = analyzedImpl.definedType.module.module.findFunctionDef(funcDef)
            if maybeConcreteFuncDef.isNone:
              return err(fmt"{targetImpl.loc} type `{targetImpl.name.asl}` does not implement function `{funcDef.name.asl}` to support `{resolvedGeneric.name.asl}`")
            else:
              analyzedImpls.add(analyzedImpl)
    ok(newAnalyzedModuleArgumentType(argType, typeModule, analyzedImpls))

proc analyzeModuleArgumentType*(app: ResolvedApp, file: ResolvedFile, generic: ResolvedGeneric, argType: ResolvedModuleArgumentType): Result[AnalyzedModuleArgumentType, string] =
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
      let analyzedImpl = ? analyzeArgumentType(app, file, generic, targetImpl)
      let funcDefs = resolvedGeneric.concreteImpls(analyzedImpl.self)
      for funcDef in funcDefs:
        case analyzedImpl.kind:
        of aatkImported:
          return err(fmt"{targetImpl.loc} todo: analyze imported impl type")
        of aatkDefined:
          case analyzedImpl.definedType.kind:
          of adatkGeneric:
            return err(fmt"{targetImpl.loc} todo: analyze defined generic impl type 2")
          of adatkModule:
            let maybeConcreteFuncDef = analyzedImpl.definedType.module.module.findFunctionDef(funcDef)
            if maybeConcreteFuncDef.isNone:
              return err(fmt"{targetImpl.loc} type `{targetImpl.name.asl}` does not implement function `{funcDef.name.asl}` to support `{resolvedGeneric.name.asl}`")
            else:
              analyzedImpls.add(analyzedImpl)
    ok(newAnalyzedModuleArgumentType(argType, typeModule, analyzedImpls))

proc analyzeDefinedArgumentType*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, argType: ResolvedDefinedArgumentType): Result[AnalyzedDefinedArgumentType, string] =
  case argType.kind:
  of rdatkGeneric:
    let analyzedArgType = ? analyzeGenericArgumentType(app, file, module, argType.generic)
    ok(newAnalyzedDefinedArgumentType(analyzedArgType))
  of rdatkModule:
    let analyzedArgType = ? analyzeModuleArgumentType(app, file, fileScope, module, argType.module)
    ok(newAnalyzedDefinedArgumentType(analyzedArgType))

proc analyzeDefinedArgumentType*(app: ResolvedApp, file: ResolvedFile, generic: ResolvedGeneric, argType: ResolvedDefinedArgumentType): Result[AnalyzedDefinedArgumentType, string] =
  case argType.kind:
  of rdatkGeneric:
    let analyzedArgType = ? analyzeGenericArgumentType(app, file, generic, argType.generic)
    ok(newAnalyzedDefinedArgumentType(analyzedArgType))
  of rdatkModule:
    let analyzedArgType = ? analyzeModuleArgumentType(app, file, generic, argType.module)
    ok(newAnalyzedDefinedArgumentType(analyzedArgType))

proc analyzeArgumentType*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, argType: ResolvedArgumentType): Result[AnalyzedArgumentType, string] =
  case argType.kind:
  of ratkImported: err(fmt"todo: analyze imported argument type")
  of ratkDefined:
    let analyzedArgType = ? analyzeDefinedArgumentType(app, file, fileScope, module, argType.definedType)
    ok(newAnalyzedArgumentType(analyzedArgType))

proc analyzeArgumentType*(app: ResolvedApp, file: ResolvedFile, generic: ResolvedGeneric, argType: ResolvedArgumentType): Result[AnalyzedArgumentType, string] =
  case argType.kind:
  of ratkImported:
    err(fmt"todo: analyze imported argument type")
  of ratkDefined:
    let analyzedArgType = ? analyzeDefinedArgumentType(app, file, generic, argType.definedType)
    ok(newAnalyzedArgumentType(analyzedArgType))
