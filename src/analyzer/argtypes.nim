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

# ResolvedFileScope — Identifier (binding name) → ResolvedDefinedType.
# Doubles as the defined-type lookup scope for the body walker
# (imports contribute per-binding entries; file's local defined types
# are inserted at the analyzer entry point).
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
    err(fmt"{genericArgType.loc} generic `{genericArgType.parsed.name.asl}` does not exist in the file `{file.path}` scope")
  else:
    ok(newAnalyzedGenericArgumentType(genericArg, genericArgType.loc))

proc analyzeGenericArgumentType*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, genericArgType: ResolvedGenericArgumentType): Result[AnalyzedGenericArgumentType, string] =
  ## Resolves the generic by checking the current file's own generics
  ## first, then falling back to the file scope for imported names.
  ## Mirrors the resolver's `findArgTypeGeneric` (see below): a
  ## `ResolvedGenericArgumentType` whose `.parsed` refers to an imported
  ## generic still needs its ResolvedGeneric surfaced so downstream code
  ## can look up its constraint-carrying funcDefs.
  let maybeGenericArg = file.findGeneric(genericArgType.parsed.name)
  if maybeGenericArg.isOk:
    ok(newAnalyzedGenericArgumentType(maybeGenericArg.get, genericArgType.loc))
  elif genericArgType.parsed.name in fileScope:
    let definedType = fileScope[genericArgType.parsed.name]
    case definedType.kind:
    of rdtkGeneric:
      ok(newAnalyzedGenericArgumentType(definedType.generic, genericArgType.loc))
    of rdtkModule:
      err(fmt"{genericArgType.loc} [UNREACHABLE] expected `{genericArgType.parsed.name.asl}` to be a generic but found module")
  else:
    err(fmt"{genericArgType.loc} generic `{genericArgType.parsed.name.asl}` is neither defined nor imported")

# Mutually-recursive cluster: AnalyzedModuleArgumentType's impls
# field references AnalyzedArgumentType, which case-dispatches back
# into AnalyzedModuleArgumentType. One `type:` block. Flat
# two-variant tagged union mirrors the resolver-side flatten —
# imported types resolve through fileScope and surface as ordinary
# `aatkModule`/`aatkGeneric` values just like local types.
type
  GenericImplMap* = Table[ResolvedGeneric, AnalyzedArgumentType]

  AnalyzedModuleArgumentType* = ref object
    resolved: ResolvedModuleArgumentType
    module: ResolvedModule
    impls: seq[AnalyzedArgumentType]

  AnalyzedArgumentTypeKind* = enum
    aatkModule, aatkGeneric

  AnalyzedArgumentType* = ref object
    case kind: AnalyzedArgumentTypeKind
    of aatkModule: module: AnalyzedModuleArgumentType
    of aatkGeneric: generic: AnalyzedGenericArgumentType

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

proc newAnalyzedArgumentType*(module: AnalyzedModuleArgumentType): AnalyzedArgumentType =
  AnalyzedArgumentType(kind: aatkModule, module: module)

proc newAnalyzedArgumentType*(generic: AnalyzedGenericArgumentType): AnalyzedArgumentType =
  AnalyzedArgumentType(kind: aatkGeneric, generic: generic)

proc kind*(a: AnalyzedArgumentType): AnalyzedArgumentTypeKind = a.kind

proc module*(a: AnalyzedArgumentType): AnalyzedModuleArgumentType =
  assert a.kind == aatkModule,
    fmt"AnalyzedArgumentType.module accessed but kind is {a.kind}"
  a.module

proc generic*(a: AnalyzedArgumentType): AnalyzedGenericArgumentType =
  assert a.kind == aatkGeneric,
    fmt"AnalyzedArgumentType.generic accessed but kind is {a.kind}"
  a.generic

proc name*(argType: AnalyzedArgumentType): Identifier =
  case argType.kind:
  of aatkModule: argType.module.name
  of aatkGeneric: argType.generic.name

proc loc*(argType: AnalyzedArgumentType): Location =
  case argType.kind:
  of aatkModule: argType.module.loc
  of aatkGeneric: argType.generic.loc

proc self*(argType: AnalyzedArgumentType): ResolvedArgumentType =
  case argType.kind:
  of aatkModule: newResolvedArgumentType(argType.module.self)
  of aatkGeneric:
    # TODO: Fix this dummy location
    let dummyLocation = newLocation()
    newResolvedArgumentType(newResolvedGenericArgumentType(argType.generic.resolved.self, dummyLocation))

proc asl*(argType: AnalyzedArgumentType): string =
  case argType.kind:
  of aatkModule: argType.module.asl
  of aatkGeneric: argType.generic.asl

proc hash*(m: AnalyzedArgumentType): Hash =
  case m.kind:
  of aatkModule: m.module.hash
  of aatkGeneric: m.generic.hash

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
  of aatkModule:
    let moduleArgType = argType.module
    var concreteImpls: seq[AnalyzedArgumentType]
    for impl in moduleArgType.impls:
      let concreteImpl = impl.concrete(implMap)
      concreteImpls.add(concreteImpl)
    let concreteModuleArgType = newAnalyzedModuleArgumentType(moduleArgType.resolved, moduleArgType.module, concreteImpls)
    return newAnalyzedArgumentType(concreteModuleArgType)
  of aatkGeneric:
    let genericArgType = argType.generic
    return implMap.getOrDefault(genericArgType.resolved, argType)

proc concrete*(argType: AnalyzedArgumentType, impls: seq[AnalyzedArgumentType], genericTypeIndex: Table[ResolvedGenericArgumentType, int]): AnalyzedArgumentType =
  ## Positional generic substitution. The `genericTypeIndex` maps each
  ## generic that a struct/union/variant's field types touch to its
  ## position in the impl list — this is a resolver-side table
  ## (`ResolvedStructDef.genericTypeIndex`,
  ## `ResolvedUnionDef.genericTypeIndex`), so the analyzer-side generic
  ## argType is translated back through its underlying parser Generic
  ## to hit the same table entry (both types hash by parser Generic
  ## identity).
  case argType.kind:
  of aatkModule:
    let moduleArgType = argType.module
    var concreteImpls: seq[AnalyzedArgumentType]
    for impl in moduleArgType.impls:
      let concreteImpl = impl.concrete(impls, genericTypeIndex)
      concreteImpls.add(concreteImpl)
    let concreteModuleArgType = newAnalyzedModuleArgumentType(moduleArgType.resolved, moduleArgType.module, concreteImpls)
    return newAnalyzedArgumentType(concreteModuleArgType)
  of aatkGeneric:
    let key = newResolvedGenericArgumentType(argType.generic.resolved.self, argType.generic.loc)
    if key in genericTypeIndex:
      return impls[genericTypeIndex[key]]
    else:
      return argType

proc findArgTypeModule(file: ResolvedFile, fileScope: ResolvedFileScope, argType: ResolvedModuleArgumentType): Result[ResolvedModule, string] =
  # TODO(task 6b): now that `argType.resolvedModule` already carries
  # the resolved module directly, this lookup is redundant. Task 6b
  # will drop `findArgTypeModule` in favour of `argType.resolvedModule`.
  let maybeTypeModule = file.findModule(argType.name)
  if maybeTypeModule.isErr:
    if argType.name notin fileScope:
      err(fmt"{argType.loc} module `{argType.name.asl}` is neither defined nor imported")
    else:
      let importedDefinedType = fileScope[argType.name]
      case importedDefinedType.kind:
      of rdtkGeneric: err(fmt"{argType.loc} [UNREACHABLE] expected `{argType.name.asl}` to be a module but found generic.")
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
  of aatkGeneric:
    let maybeConcreteFuncDef = implType.generic.resolved.findFunctionDef(funcDef)
    if maybeConcreteFuncDef.isNone:
      err(fmt"{implType.loc} generic `{implType.name.asl}` does not implement function `{funcDef.name.asl}` to support `{baseType.name.asl}`")
    else:
      ok()
  of aatkModule:
    let maybeConcreteFuncDef = implType.module.module.findFunctionDef(funcDef)
    if maybeConcreteFuncDef.isNone:
      err(fmt"{implType.loc} module `{implType.name.asl}` does not implement function `{funcDef.name.asl}` to support `{baseType.name.asl}`")
    else:
      ok()

proc analyzeModuleArgumentType*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, argType: ResolvedModuleArgumentType): Result[AnalyzedModuleArgumentType, string] =
  var typeModule = ? file.findArgTypeModule(fileScope, argType)

  if typeModule.requires.len != argType.impls.len:
    if typeModule.requires.len == 0:
      err(fmt"{argType.loc} module `{argType.name.asl}` does not require any impl types")
    else:
      err(fmt"{argType.loc} module `{argType.name.asl}` requires `{typeModule.requires.len}` impl types but found `{argType.impls.len}`")
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
      err(fmt"{argType.loc} module `{argType.name.asl}` does not require any impl types")
    else:
      err(fmt"{argType.loc} module `{argType.name.asl}` requires `{typeModule.requires.len}` impl types but found `{argType.impls.len}`")
  else:
    var analyzedImpls: seq[AnalyzedArgumentType]
    for (baseType, implType) in zip(typeModule.requires, argType.impls):
      let resolvedBaseGeneric = ? file.findArgTypeGeneric(fileScope, baseType)
      let analyzedImplArgType = ? analyzeArgumentType(app, file, fileScope, generic, implType)
      for funcDef in resolvedBaseGeneric.concreteImpls(analyzedImplArgType.self):
        ? analyzeModuleArgumentTypeImpls(resolvedBaseGeneric, analyzedImplArgType, funcDef)
        analyzedImpls.add(analyzedImplArgType)
    ok(newAnalyzedModuleArgumentType(argType, typeModule, analyzedImpls))

proc analyzeArgumentType*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, argType: ResolvedArgumentType): Result[AnalyzedArgumentType, string] =
  case argType.kind:
  of ratkGeneric:
    let analyzedArgType = ? analyzeGenericArgumentType(app, file, fileScope, module, argType.generic)
    ok(newAnalyzedArgumentType(analyzedArgType))
  of ratkModule:
    let analyzedArgType = ? analyzeModuleArgumentType(app, file, fileScope, module, argType.module)
    ok(newAnalyzedArgumentType(analyzedArgType))

proc analyzeArgumentType*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, generic: ResolvedGeneric, argType: ResolvedArgumentType): Result[AnalyzedArgumentType, string] =
  case argType.kind:
  of ratkGeneric:
    let analyzedArgType = ? analyzeGenericArgumentType(app, file, generic, argType.generic)
    ok(newAnalyzedArgumentType(analyzedArgType))
  of ratkModule:
    let analyzedArgType = ? analyzeModuleArgumentType(app, file, fileScope, generic, argType.module)
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