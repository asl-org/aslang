## Analyzed argument-type cluster.
##
## Mirrors the resolver's argtypes layout: AnalyzedGenericArgumentType,
## AnalyzedModuleArgumentType, AnalyzedDefinedArgumentType, and
## AnalyzedArgumentType live here together because they cycle through
## one another (a module's `impls` is a seq of argument types). Both
## context overloads (module ctx with ResolvedFileScope, generic ctx)
## of analyzeGenericArgumentType / analyzeModuleArgumentType /
## analyzeDefinedArgumentType / analyzeArgumentType live here too.

import results, strformat, options, sequtils, strutils, tables, hashes

import tokenizer
import parser
import resolver

# ResolvedFileScope — Identifier (binding name) → ResolvedDefinedType
# (the imported defined type pulled in from the source file).
type ResolvedFileScope* = Table[Identifier, ResolvedDefinedType]

# AnalyzedGenericArgumentType — wraps a ResolvedGeneric with the
# use-site location so analyzer diagnostics can point precisely.
type AnalyzedGenericArgumentType* = ref object
  resolved: ResolvedGeneric
  loc: Location

proc newAnalyzedGenericArgumentType*(resolved: ResolvedGeneric, loc: Location): AnalyzedGenericArgumentType =
  AnalyzedGenericArgumentType(resolved: resolved, loc: loc)

proc resolved*(g: AnalyzedGenericArgumentType): ResolvedGeneric = g.resolved
proc loc*(g: AnalyzedGenericArgumentType): Location = g.loc
proc name*(g: AnalyzedGenericArgumentType): Identifier = g.resolved.name
proc hash*(g: AnalyzedGenericArgumentType): Hash = g.resolved.hash
proc `==`*(a, b: AnalyzedGenericArgumentType): bool = a.hash == b.hash
proc asl*(argType: AnalyzedGenericArgumentType): string =
  argType.resolved.name.asl

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
  GenericImplMap* = Table[ResolvedGeneric, AnalyzedArgumentType]

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
proc hash*(m: AnalyzedArgumentType): Hash
proc asl*(argType: AnalyzedArgumentType): string
proc analyzeArgumentType*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, argType: ResolvedArgumentType): Result[AnalyzedArgumentType, string]
proc analyzeArgumentType*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, generic: ResolvedGeneric, argType: ResolvedArgumentType): Result[AnalyzedArgumentType, string]

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
proc hash*(m: AnalyzedModuleArgumentType): Hash =
  var acc = m.module.hash
  for impl in m.impls:
    acc = acc !& impl.hash
  return acc
proc `==`*(a, b: AnalyzedModuleArgumentType): bool = a.hash == b.hash
proc asl*(argType: AnalyzedModuleArgumentType): string =
  if argType.impls.len == 0:
    fmt"{argType.module.name.asl}"
  else:
    var impls: seq[string]
    for impl in argType.impls:
      impls.add(impl.asl)
    let implChildren = impls.join(", ")
    fmt"{argType.module.name.asl}[{implChildren}]"

proc newAnalyzedDefinedArgumentType*(module: AnalyzedModuleArgumentType): AnalyzedDefinedArgumentType =
  AnalyzedDefinedArgumentType(kind: adatkModule, module: module)

proc newAnalyzedDefinedArgumentType*(generic: AnalyzedGenericArgumentType): AnalyzedDefinedArgumentType =
  AnalyzedDefinedArgumentType(kind: adatkGeneric, generic: generic)

proc kind*(d: AnalyzedDefinedArgumentType): AnalyzedDefinedArgumentTypeKind = d.kind
proc module*(d: AnalyzedDefinedArgumentType): AnalyzedModuleArgumentType =
  assert d.kind == adatkModule,
    fmt"AnalyzedDefinedArgumentType.module accessed but kind is {d.kind}"
  d.module
proc generic*(d: AnalyzedDefinedArgumentType): AnalyzedGenericArgumentType =
  assert d.kind == adatkGeneric,
    fmt"AnalyzedDefinedArgumentType.generic accessed but kind is {d.kind}"
  d.generic
proc loc*(m: AnalyzedDefinedArgumentType): Location =
  case m.kind:
  of adatkModule: m.module.loc
  of adatkGeneric: m.generic.loc

proc name*(m: AnalyzedDefinedArgumentType): Identifier =
  case m.kind:
  of adatkModule: m.module.name
  of adatkGeneric: m.generic.name

proc self(argType: AnalyzedDefinedArgumentType): ResolvedDefinedArgumentType =
  case argType.kind:
  of adatkModule: newResolvedDefinedArgumentType(argType.module.self)
  of adatkGeneric:
    # TODO: Fix this dummy location
    let dummyLocation = newLocation()
    newResolvedDefinedArgumentType(newResolvedGenericArgumentType(argType.generic.resolved.self, dummyLocation))

proc hash*(m: AnalyzedDefinedArgumentType): Hash =
  case m.kind:
  of adatkModule: m.module.hash
  of adatkGeneric: m.generic.hash
proc `==`*(a, b: AnalyzedDefinedArgumentType): bool = a.hash == b.hash
proc asl*(argType: AnalyzedDefinedArgumentType): string =
  case argType.kind:
  of adatkGeneric: argType.generic.asl
  of adatkModule: argType.module.asl

proc newAnalyzedArgumentType*(definedType: AnalyzedDefinedArgumentType): AnalyzedArgumentType =
  AnalyzedArgumentType(kind: aatkDefined, definedType: definedType)

proc kind*(a: AnalyzedArgumentType): AnalyzedArgumentTypeKind = a.kind
proc definedType*(a: AnalyzedArgumentType): AnalyzedDefinedArgumentType =
  assert a.kind == aatkDefined,
    fmt"AnalyzedArgumentType.definedType accessed but kind is {a.kind}"
  a.definedType

proc name*(argType: AnalyzedArgumentType): Identifier =
  case argType.kind:
  of aatkImported: assert(false, "TODO: support analyzed argument type name")
  of aatkDefined: return argType.definedType.name

proc loc*(argType: AnalyzedArgumentType): Location =
  case argType.kind:
  of aatkImported: assert(false, "TODO: support analyzed argument type location")
  of aatkDefined: return argType.definedType.loc

proc self*(argType: AnalyzedArgumentType): ResolvedArgumentType =
  case argType.kind:
  of aatkImported: assert(false, "TODO: support analyzed argument type self construction")
  of aatkDefined: return newResolvedArgumentType(argType.definedType.self)

proc asl*(argType: AnalyzedArgumentType): string =
  case argType.kind:
  of aatkImported: assert(false, "TODO: support analyzed argument type asl")
  of aatkDefined: return argType.definedType.asl

proc hash*(m: AnalyzedArgumentType): Hash =
  case m.kind:
  of aatkImported: assert(false, "TODO: support analyzed argument type hash")
  of aatkDefined: return m.definedType.hash
proc `==`*(a, b: AnalyzedArgumentType): bool = a.hash == b.hash

# TODO(union-inference): `==` is only correct when both sides are
# ground. Under leave-as-is, a value's type can carry free generics in
# impl positions (e.g. Box[u8, Sample]). Assignability against an
# expected type (Box[u8, MyImpl]) is unification, not equality. Audit
# every callsite of AnalyzedArgumentType `==` used for assignability
# (value-type vs expected-type matches in arg checks, return checks,
# kwarg checks) and route through analyzeValueTypeAgainstDefinitionType
# / GenericImplMap merge instead. Pure type-identity uses
# (deduplication, table keying) stay as-is.

proc concrete*(argType: AnalyzedArgumentType, implMap: GenericImplMap): AnalyzedArgumentType =
  # TODO(union-inference): handle substitution chains. A single use
  # site can produce an implMap with both `Sample → K` and `K → u8`
  # (e.g. `func f(a: Box[u8, K], b: K)` called as
  # `f(boxFirst, u8 5)`). Today getOrDefault returns the immediate
  # map value, so `Sample` rewrites to `K`, not `u8`. Prefer eager
  # chain-collapsing in `merge` (cheaper, single pass) — see the TODO
  # there — over recursive lookup here.
  case argType.kind:
  of aatkImported: assert(false, "TODO: support analyzed argument type concretization")
  of aatkDefined:
    case argType.definedType.kind:
    of adatkModule:
      let moduleArgType = argType.definedType.module
      var concreteImpls: seq[AnalyzedArgumentType]
      for impl in moduleArgType.impls:
        let concreteImpl = impl.concrete(implMap)
        concreteImpls.add(concreteImpl)
      let concreteModuleArgType = newAnalyzedModuleArgumentType(moduleArgType.resolved, moduleArgType.module, concreteImpls)
      return newAnalyzedArgumentType(newAnalyzedDefinedArgumentType(concreteModuleArgType))
    of adatkGeneric:
      let genericArgType = argType.definedType.generic
      return implMap.getOrDefault(genericArgType.resolved, argType)

proc concrete*(argType: AnalyzedArgumentType, impls: seq[AnalyzedArgumentType], genericTypeIndex: Table[AnalyzedGenericArgumentType, int]): AnalyzedArgumentType =
  # TODO(union-inference): handle substitution chains. A single use
  # site can produce an implMap with both `Sample → K` and `K → u8`
  # (e.g. `func f(a: Box[u8, K], b: K)` called as
  # `f(boxFirst, u8 5)`). Today getOrDefault returns the immediate
  # map value, so `Sample` rewrites to `K`, not `u8`. Prefer eager
  # chain-collapsing in `merge` (cheaper, single pass) — see the TODO
  # there — over recursive lookup here.
  case argType.kind:
  of aatkImported: assert(false, "TODO: support analyzed argument type concretization")
  of aatkDefined:
    case argType.definedType.kind:
    of adatkModule:
      return argType
    of adatkGeneric:
      if argType.definedType.generic in genericTypeIndex:
        return impls[genericTypeIndex[argType.definedType.generic]]
      else:
        return argType

proc findArgTypeModule(file: ResolvedFile, fileScope: ResolvedFileScope, argType: ResolvedModuleArgumentType): Result[ResolvedModule, string] =
  let maybeTypeModule = file.findModule(argType.module.name)
  if maybeTypeModule.isErr:
    if argType.module.name notin fileScope:
      err(fmt"{argType.loc} module `{argType.module.name.asl}` is neither defined nor imported")
    else:
      let importedDefinedType = fileScope[argType.module.name]
      case importedDefinedType.kind:
      of rdtkGeneric: err(fmt"{argType.loc} [UNREACHABLE] expected `{argType.module.name.asl}` to be a module but found generic.")
      of rdtkModule: ok(importedDefinedType.module)
  else:
    ok(maybeTypeModule.value)

proc findArgTypeGeneric(file: ResolvedFile, fileScope: ResolvedFileScope, argType: ResolvedGenericArgumentType): Result[ResolvedGeneric, string] =
  let maybeResolvedGeneric = file.findGeneric(argType.name)
  if maybeResolvedGeneric.isErr:
    if argType.name notin fileScope:
      err(fmt"{argType.loc} generic `{argType.name.asl}` is neither defined nor imported")
    else:
      let definedImportedGeneric = fileScope[argType.name]
      case definedImportedGeneric.kind:
      of rdtkModule: err(fmt"[UNREACHABLE] {argType.loc} expected `{argType.name.asl}` to be a generic but found module.")
      of rdtkGeneric: ok(definedImportedGeneric.generic)
  else:
    ok(maybeResolvedGeneric.value)

proc analyzeModuleArgumentTypeImpls(baseType: ResolvedGeneric, implType: AnalyzedArgumentType, funcDef: ResolvedFunctionDefinition): Result[void, string] =
  case implType.kind:
  of aatkImported:
    err(fmt"{implType.loc} todo: analyze imported impl type")
  of aatkDefined:
    case implType.definedType.kind:
    of adatkGeneric:
      let maybeConcreteFuncDef = implType.definedType.generic.resolved.findFunctionDef(funcDef)
      if maybeConcreteFuncDef.isNone:
        err(fmt"{implType.loc} generic `{implType.name.asl}` does not implement function `{funcDef.name.asl}` to support `{baseType.name.asl}`")
      else:
        ok()
    of adatkModule:
      let maybeConcreteFuncDef = implType.definedType.module.module.findFunctionDef(funcDef)
      if maybeConcreteFuncDef.isNone:
        err(fmt"{implType.loc} module `{implType.name.asl}` does not implement function `{funcDef.name.asl}` to support `{baseType.name.asl}`")
      else:
        ok()

proc analyzeModuleArgumentType*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, argType: ResolvedModuleArgumentType): Result[AnalyzedModuleArgumentType, string] =
  var typeModule = ? file.findArgTypeModule(fileScope, argType)

  if typeModule.requires.len != argType.impls.len:
    if typeModule.requires.len == 0:
      err(fmt"{argType.loc} module `{argType.module.name.asl}` does not require any impl types")
    else:
      err(fmt"{argType.loc} module `{argType.module.name.asl}` requires `{typeModule.requires.len}` impl types but found `{argType.impls.len}`")
  else:
    var analyzedImpls: seq[AnalyzedArgumentType]
    for (baseType, implType) in zip(typeModule.requires, argType.impls):
      let resolvedBaseGeneric = ? file.findArgTypeGeneric(fileScope, baseType)
      let analyzedImplArgType = ? analyzeArgumentType(app, file, fileScope, module, implType)
      for funcDef in resolvedBaseGeneric.concreteImpls(analyzedImplArgType.self):
        ? analyzeModuleArgumentTypeImpls(resolvedBaseGeneric, analyzedImplArgType, funcDef)
      analyzedImpls.add(analyzedImplArgType)
    ok(newAnalyzedModuleArgumentType(argType, typeModule, analyzedImpls))

proc analyzeModuleArgumentType*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, generic: ResolvedGeneric, argType: ResolvedModuleArgumentType): Result[AnalyzedModuleArgumentType, string] =
  let typeModule = ? file.findArgTypeModule(fileScope, argType)

  if typeModule.requires.len != argType.impls.len:
    if typeModule.requires.len == 0:
      err(fmt"{argType.loc} module `{argType.module.name.asl}` does not require any impl types")
    else:
      err(fmt"{argType.loc} module `{argType.module.name.asl}` requires `{typeModule.requires.len}` impl types but found `{argType.impls.len}`")
  else:
    var analyzedImpls: seq[AnalyzedArgumentType]
    for (baseType, implType) in zip(typeModule.requires, argType.impls):
      let resolvedBaseGeneric = ? file.findArgTypeGeneric(fileScope, baseType)
      let analyzedImplArgType = ? analyzeArgumentType(app, file, fileScope, generic, implType)
      for funcDef in resolvedBaseGeneric.concreteImpls(analyzedImplArgType.self):
        ? analyzeModuleArgumentTypeImpls(resolvedBaseGeneric, analyzedImplArgType, funcDef)
        analyzedImpls.add(analyzedImplArgType)
    ok(newAnalyzedModuleArgumentType(argType, typeModule, analyzedImpls))

proc analyzeDefinedArgumentType*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, argType: ResolvedDefinedArgumentType): Result[AnalyzedDefinedArgumentType, string] =
  case argType.kind:
  of rdatkGeneric:
    # echo fmt"BEFORE ANALYZED GENERIC: {argType.generic.asl}"
    let analyzedArgType = ? analyzeGenericArgumentType(app, file, module, argType.generic)
    # echo fmt"AFTER ANALYZED GENERIC: {analyzedArgType.asl}"
    ok(newAnalyzedDefinedArgumentType(analyzedArgType))
  of rdatkModule:
    # echo fmt"BEFORE ANALYZED MODULE: {argType.module.asl}"
    let analyzedArgType = ? analyzeModuleArgumentType(app, file, fileScope, module, argType.module)
    # echo fmt"BEFORE ANALYZED MODULE: {analyzedArgType.asl}"
    ok(newAnalyzedDefinedArgumentType(analyzedArgType))

proc analyzeDefinedArgumentType*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, generic: ResolvedGeneric, argType: ResolvedDefinedArgumentType): Result[AnalyzedDefinedArgumentType, string] =
  case argType.kind:
  of rdatkGeneric:
    let analyzedArgType = ? analyzeGenericArgumentType(app, file, generic, argType.generic)
    ok(newAnalyzedDefinedArgumentType(analyzedArgType))
  of rdatkModule:
    let analyzedArgType = ? analyzeModuleArgumentType(app, file, fileScope, generic, argType.module)
    ok(newAnalyzedDefinedArgumentType(analyzedArgType))

proc analyzeArgumentType*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, argType: ResolvedArgumentType): Result[AnalyzedArgumentType, string] =
  case argType.kind:
  of ratkImported: err(fmt"todo: analyze imported argument type")
  of ratkDefined:
    let analyzedArgType = ? analyzeDefinedArgumentType(app, file, fileScope, module, argType.definedType)
    # echo fmt"ANALYZED DEFINED: {analyzedArgType.asl}"
    ok(newAnalyzedArgumentType(analyzedArgType))

proc analyzeArgumentType*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, generic: ResolvedGeneric, argType: ResolvedArgumentType): Result[AnalyzedArgumentType, string] =
  case argType.kind:
  of ratkImported:
    err(fmt"todo: analyze imported argument type")
  of ratkDefined:
    let analyzedArgType = ? analyzeDefinedArgumentType(app, file, fileScope, generic, argType.definedType)
    ok(newAnalyzedArgumentType(analyzedArgType))

# ------------------------------ GenericImplMap -----------------------------
proc merge*(global: var GenericImplMap, local: GenericImplMap): Result[GenericImplMap, string] =
  # TODO(union-inference): eagerly collapse substitution chains.
  # When inserting `K → u8`, also rewrite any existing values in the
  # map that mention K as a free generic (e.g. an earlier
  # `Sample → K` becomes `Sample → u8`). This keeps `concrete()` a
  # single-pass lookup and prevents free generics from getting stuck
  # half-resolved when one use site binds another generic that they
  # depend on. Also: the `!=` conflict check on the next line needs
  # to become a unification check once free generics can appear on
  # either side (a bound u8 vs a free K should not "conflict" — K
  # should unify to u8).
  for generic, impl in local:
    if generic in global and global[generic] != impl:
      return err(fmt"{impl.loc} generic `{generic.name.asl}` already bound to `{global[generic].asl}` (at {global[generic].loc}) but here resolves to `{impl.asl}` — one generic binds to one concrete type per construction; declare a second generic if you need independent types")
    else:
      global[generic] = impl
  ok(global)