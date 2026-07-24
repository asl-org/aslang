# ============================================================
# PORT REFERENCE — do not consume directly.
# ============================================================
#
# This file is the old analyzer preserved for the two-pass recovery
# port. See plans/plan_analyzer_two_pass.md.
#
# Renames already applied to make this compile-adjacent to the
# current resolver:
#   ResolvedDefinedType          → ResolvedType
#   ResolvedFunctionDefinition   → ResolvedFunctionDef
#   ResolvedArgumentDefinition   → ResolvedArgumentDef
#   ResolvedLiteralType          → ResolvedLiteralDef
#   ResolvedStruct               → ResolvedStructDef
#   ResolvedUnion                → ResolvedUnionDef
#   ResolvedMutation             → ResolvedSetter
#   findDefinedType              → findType
#   definedTypes                 → types
# Import block also flattened from `tokenizer / parser / resolver` to
# a single `./analyzer/resolver` re-export.
#
# Renames STILL to figure out during the port (spot at first compile
# error; look at the underlying type shape in the current resolver
# for the equivalent):
#   ResolvedDefinedArgumentType  — merged into ResolvedArgumentType
#                                  (the tagged-union layer collapsed).
#   ResolvedFileScope            — old was Table[Id, ResolvedType];
#                                  new resolver FileScope is
#                                  Table[Id, parser.Type]. Different
#                                  underlying value type.
#   accessor renames             — e.g. ResolvedImportedType.definedType
#                                  is now .typ.
#
# This file is NOT built. Its content is being ported piece-by-piece
# into src/analyzer/*.nim per the W1-W7 work items in the plan.
# Deletes at W10 once the port is complete.
# ============================================================

import parseutils, results, strformat, strscans, options, sequtils, strutils, tables, hashes, sets, math

import ./analyzer/resolver
export resolver

# ResolvedFileScope — Identifier (binding name) → ResolvedType
# (the imported defined type pulled in from the source file).
type ResolvedFileScope* = Table[Identifier, ResolvedType]

type AnalyzedImportedType* = ref object
  resolved: ResolvedImportedType
  definedType: ResolvedType

proc newAnalyzedImportedType*(resolved: ResolvedImportedType, definedType: ResolvedType): AnalyzedImportedType =
  AnalyzedImportedType(resolved: resolved, definedType: definedType)

proc binding*(impType: AnalyzedImportedType): Identifier = impType.resolved.binding
proc definedType*(impType: AnalyzedImportedType): ResolvedType = impType.definedType

proc analyzeImportedType*(app: ResolvedApp, impFile: ResolvedFile, impType: ResolvedImportedType): Result[AnalyzedImportedType, string] =
  let maybeImportedType = impFile.findType(impType.definedType.name)
  if maybeImportedType.isErr:
    err(fmt"{impType.loc} type `{impType.definedType.name.asl}` is not defined in the file")
  else:
    ok(newAnalyzedImportedType(impType, maybeImportedType.get))

type AnalyzedImportDefinition* = ref object
  resolved: ResolvedImport
  importedTypes: seq[AnalyzedImportedType]

proc newAnalyzedImportDefinition*(resolved: ResolvedImport, importedTypes: seq[AnalyzedImportedType]): AnalyzedImportDefinition =
  AnalyzedImportDefinition(resolved: resolved, importedTypes: importedTypes)

proc importedTypes*(imp: AnalyzedImportDefinition): seq[AnalyzedImportedType] = imp.importedTypes
proc path*(imp: AnalyzedImportDefinition): string = imp.resolved.impFile.path

proc analyzeImportDefinition*(app: ResolvedApp, file: ResolvedFile, imp: ResolvedImport): Result[AnalyzedImportDefinition, string] =
  let maybeImportedFile = app.findFile(imp.impFile)
  if maybeImportedFile.isNone:
    err(fmt"{imp.loc} UNREACHABLE: file `{imp.impFile.path}` does not exist")
  else:
    let analyzedImpFile = maybeImportedFile.get
    var importedTypes: seq[AnalyzedImportedType]
    for impType in imp.importedTypes:
      let analyzedImportedType = ? analyzeImportedType(app, analyzedImpFile, impType)
      importedTypes.add(analyzedImportedType)
    ok(newAnalyzedImportDefinition(imp, importedTypes))

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

proc analyzeModuleArgumentTypeImpls(baseType: ResolvedGeneric, implType: AnalyzedArgumentType, funcDef: ResolvedFunctionDef): Result[void, string] =
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

# AnalyzedArgumentDefinition
type AnalyzedArgumentDefinition* = ref object
  argType: AnalyzedArgumentType
  name: Identifier

proc newAnalyzedArgumentDefinition*(argType: AnalyzedArgumentType, name: Identifier): AnalyzedArgumentDefinition =
  AnalyzedArgumentDefinition(argType: argType, name: name)

proc argType*(d: AnalyzedArgumentDefinition): AnalyzedArgumentType = d.argType
proc name*(d: AnalyzedArgumentDefinition): Identifier = d.name
proc loc*(argDef: AnalyzedArgumentDefinition): Location = argDef.name.loc
proc asl*(argDef: AnalyzedArgumentDefinition): string =
  fmt"{argDef.name.asl}: {argDef.argType.asl}"

proc concrete*(argDef: AnalyzedArgumentDefinition, implMap: GenericImplMap): AnalyzedArgumentDefinition =
  # TODO: We are copying the resolved def from the original argument definition to the concrete one
  # it may cause misdirection issues when converted to asl or accessing location. A suggestion for
  # doing this the right way is to persist both original definition along with genericImplMap and
  # concretizing it only when needed.
  let concreteArgType = argDef.argType.concrete(implMap)
  newAnalyzedArgumentDefinition(concreteArgType, argDef.name)

proc concrete*(argDef: AnalyzedArgumentDefinition, impls: seq[AnalyzedArgumentType], genericTypeIndex: Table[AnalyzedGenericArgumentType, int]): AnalyzedArgumentDefinition =
  let concreteArgType = argDef.argType.concrete(impls, genericTypeIndex)
  newAnalyzedArgumentDefinition(concreteArgType, argDef.name)

proc analyzeArgumentDefinition*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, argDef: ResolvedArgumentDef): Result[AnalyzedArgumentDefinition, string] =
  let analyzedArgType = ? analyzeArgumentType(app, file, fileScope, module, argDef.argType)
  ok(newAnalyzedArgumentDefinition(analyzedArgType, argDef.name))

proc analyzeArgumentDefinition*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, generic: ResolvedGeneric, argDef: ResolvedArgumentDef): Result[AnalyzedArgumentDefinition, string] =
  let analyzedArgType = ? analyzeArgumentType(app, file, fileScope, generic, argDef.argType)
  ok(newAnalyzedArgumentDefinition(analyzedArgType, argDef.name))

# AnalyzedFunctionDefinition
type AnalyzedFunctionDefinition* = ref object
  resolved: ResolvedFunctionDef
  args: seq[AnalyzedArgumentDefinition]
  returns: AnalyzedArgumentType

# TODO: Ensure that there are no duplicated generic fields
proc newAnalyzedFunctionDefinition*(resolved: ResolvedFunctionDef, args: seq[AnalyzedArgumentDefinition], returns: AnalyzedArgumentType): AnalyzedFunctionDefinition =
  AnalyzedFunctionDefinition(resolved: resolved, args: args, returns: returns)

proc public*(f: AnalyzedFunctionDefinition): bool = f.resolved.public
proc name*(f: AnalyzedFunctionDefinition): Identifier = f.resolved.name
proc loc*(f: AnalyzedFunctionDefinition): Location = f.resolved.loc
proc resolved*(f: AnalyzedFunctionDefinition): ResolvedFunctionDef = f.resolved
proc arity*(f: AnalyzedFunctionDefinition): int = f.args.len
proc args*(f: AnalyzedFunctionDefinition): seq[AnalyzedArgumentDefinition] = f.args
proc returns*(f: AnalyzedFunctionDefinition): AnalyzedArgumentType = f.returns
proc asl*(funcDef: AnalyzedFunctionDefinition): string =
  var args: seq[string]
  for arg in funcDef.args:
    args.add(arg.asl)
  let argsJoined = args.join(", ")
  fmt"func {funcDef.name.asl}({argsJoined}): {funcDef.returns.asl}"
proc concrete*(funcDef: AnalyzedFunctionDefinition, implMap: GenericImplMap): AnalyzedFunctionDefinition =
  var concreteArgs: seq[AnalyzedArgumentDefinition]
  for arg in funcDef.args:
    let concreteArg = arg.concrete(implMap)
    concreteArgs.add(concreteArg)
  let concreteReturns = funcDef.returns.concrete(implMap)
  # TODO: We are copying the resolved def from the original function definition to the concrete one
  # it may cause misdirection issues when converted to asl or accessing location. A suggestion for
  # doing this the right way is to persist both original definition along with genericImplMap and
  # concretizing it only when needed.
  newAnalyzedFunctionDefinition(funcDef.resolved, concreteArgs, concreteReturns)

proc analyzeFunctionDefinition*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcDef: ResolvedFunctionDef): Result[AnalyzedFunctionDefinition, string] =
  var analyzedArgDefs: seq[AnalyzedArgumentDefinition]
  for arg in funcDef.args:
    let analyzedArgDef = ? analyzeArgumentDefinition(app, file, fileScope, module, arg)
    analyzedArgDefs.add(analyzedArgDef)
  # echo fmt"BEFORE: {funcDef.returns.asl}"
  let analyzedReturns = ? analyzeArgumentType(app, file, fileScope, module, funcDef.returns)
  # echo fmt"AFTER: {analyzedReturns.asl}"
  ok(newAnalyzedFunctionDefinition(funcDef, analyzedArgDefs, analyzedReturns))

proc analyzeFunctionDefinition*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, generic: ResolvedGeneric, funcDef: ResolvedFunctionDef): Result[AnalyzedFunctionDefinition, string] =
  var analyzedArgDefs: seq[AnalyzedArgumentDefinition]
  for arg in funcDef.args:
    let analyzedArgDef = ? analyzeArgumentDefinition(app, file, fileScope, generic, arg)
    analyzedArgDefs.add(analyzedArgDef)

  let analyzedReturns = ? analyzeArgumentType(app, file, fileScope, generic, funcDef.returns)
  ok(newAnalyzedFunctionDefinition(funcDef, analyzedArgDefs, analyzedReturns))

type AnalyzedLiteralBlock* = ref object
  resolved: ResolvedLiteralDef

proc newAnalyzedLiteralBlock*(resolved: ResolvedLiteralDef): AnalyzedLiteralBlock =
  AnalyzedLiteralBlock(resolved: resolved)

proc resolved*(b: AnalyzedLiteralBlock): ResolvedLiteralDef = b.resolved

proc accumulateGenericPosition(genericTypeIndex: var Table[AnalyzedGenericArgumentType, int], field: AnalyzedArgumentDefinition) =
  ## Mirror of the resolver-side accumulator. Same name across
  ## multiple fields keeps its first position — conflicts surface at
  ## the init site via GenericImplMap.merge(), not here.
  case field.argType.kind:
  of aatkImported:
    assert(false, "todo: walk imported field type to collect nested generics")
  of aatkDefined:
    case field.argType.definedType.kind:
    of adatkModule: discard
    of adatkGeneric:
      let genericType = field.argType.definedType.generic
      if genericType notin genericTypeIndex:
        genericTypeIndex[genericType] = genericTypeIndex.len

# AnalyzedStruct
type AnalyzedStruct* = ref object
  resolved: ResolvedStructDef
  fields: seq[AnalyzedArgumentDefinition]
  fieldIndex: Table[Identifier, int]
  genericTypeIndex: Table[AnalyzedGenericArgumentType, int]

proc newAnalyzedStruct*(resolved: ResolvedStructDef, fields: seq[AnalyzedArgumentDefinition], genericTypeIndex: Table[AnalyzedGenericArgumentType, int]): AnalyzedStruct =
  var fieldIndex: Table[Identifier, int]
  for id, field in fields:
    assert(field.name notin fieldIndex, "UNREACHABLE: duplicate field name must have been caught by resolver")
    fieldIndex[field.name] = id
  AnalyzedStruct(resolved: resolved, fields: fields, fieldIndex: fieldIndex, genericTypeIndex: genericTypeIndex)

proc resolved*(s: AnalyzedStruct): ResolvedStructDef = s.resolved
proc loc*(s: AnalyzedStruct): Location = s.resolved.loc
proc fields*(s: AnalyzedStruct): seq[AnalyzedArgumentDefinition] = s.fields
proc findField*(s: AnalyzedStruct, name: Identifier): Result[AnalyzedArgumentDefinition, string] =
  if name in s.fieldIndex: ok(s.fields[s.fieldIndex[name]])
  else: err(fmt"{name.loc} field `{name.asl}` does not exist")

proc concrete*(struct: AnalyzedStruct, impls: seq[AnalyzedArgumentType]): AnalyzedStruct =
  var concreteFields: seq[AnalyzedArgumentDefinition]
  for field in struct.fields:
    let concreteField = field.concrete(impls, struct.genericTypeIndex)
    concreteFields.add(concreteField)
  newAnalyzedStruct(struct.resolved, concreteFields, struct.genericTypeIndex)

proc analyzeStruct*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, struct: ResolvedStructDef): Result[AnalyzedStruct, string] =
  var analyzedFields: seq[AnalyzedArgumentDefinition]
  var genericTypeIndex: Table[AnalyzedGenericArgumentType, int]
  for field in struct.fields:
    let analyzedField = ? analyzeArgumentDefinition(app, file, fileScope, module, field)
    genericTypeIndex.accumulateGenericPosition(analyzedField)
    analyzedFields.add(analyzedField)
  ok(newAnalyzedStruct(struct, analyzedFields, genericTypeIndex))

# AnalyzedVariant
type AnalyzedVariant* = ref object
  resolved: ResolvedVariant
  fields: seq[AnalyzedArgumentDefinition]
  fieldIndex: Table[Identifier, int]

proc newAnalyzedVariant*(resolved: ResolvedVariant, fields: seq[AnalyzedArgumentDefinition]): AnalyzedVariant =
  var fieldIndex: Table[Identifier, int]
  for id, field in fields:
    assert(field.name notin fieldIndex, "UNREACHABLE: duplicate field name must have been caught by resolver")
    fieldIndex[field.name] = id
  AnalyzedVariant(resolved: resolved, fields: fields, fieldIndex: fieldIndex)

proc name*(v: AnalyzedVariant): Identifier = v.resolved.name
proc resolved*(v: AnalyzedVariant): ResolvedVariant = v.resolved
proc fields*(v: AnalyzedVariant): seq[AnalyzedArgumentDefinition] = v.fields

proc concrete*(variant: AnalyzedVariant, impls: seq[AnalyzedArgumentType], genericTypeIndex: Table[AnalyzedGenericArgumentType, int]): AnalyzedVariant =
  var concreteFields: seq[AnalyzedArgumentDefinition]
  for field in variant.fields:
    let concreteField = field.concrete(impls, genericTypeIndex)
    concreteFields.add(concreteField)
  newAnalyzedVariant(variant.resolved, concreteFields)

proc findField*(v: AnalyzedVariant, name: Identifier): Result[AnalyzedArgumentDefinition, string] =
  if name in v.fieldIndex: ok(v.fields[v.fieldIndex[name]])
  else: err(fmt"{name.loc} field `{name.asl}` does not exist")

proc analyzeVariant(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, variant: ResolvedVariant, genericTypeIndex: var Table[AnalyzedGenericArgumentType, int]): Result[AnalyzedVariant, string] =
  var analyzedFields: seq[AnalyzedArgumentDefinition]
  for field in variant.fields:
    let analyzedField = ? analyzeArgumentDefinition(app, file, fileScope, module, field)
    genericTypeIndex.accumulateGenericPosition(analyzedField)
    analyzedFields.add(analyzedField)
  ok(newAnalyzedVariant(variant, analyzedFields))

# AnalyzedUnion
type AnalyzedUnion* = ref object
  resolved: ResolvedUnionDef
  variants: seq[AnalyzedVariant]
  variantIndex: Table[Identifier, int]
  genericTypeIndex: Table[AnalyzedGenericArgumentType, int]

proc newAnalyzedUnion*(resolved: ResolvedUnionDef, variants: seq[AnalyzedVariant], genericTypeIndex: Table[AnalyzedGenericArgumentType, int]): AnalyzedUnion =
  var variantIndex: Table[Identifier, int]
  for id, variant in variants:
    assert(variant.name notin variantIndex, "UNREACHABLE: this should have been caught in resolution")
    variantIndex[variant.name] = id
  AnalyzedUnion(resolved: resolved, variants: variants, variantIndex: variantIndex, genericTypeIndex: genericTypeIndex)

proc resolved*(u: AnalyzedUnion): ResolvedUnionDef = u.resolved
proc variants*(u: AnalyzedUnion): seq[AnalyzedVariant] = u.variants
proc genericTypeIndex*(u: AnalyzedUnion): Table[AnalyzedGenericArgumentType, int] = u.genericTypeIndex
proc concrete*(union: AnalyzedUnion, impls: seq[AnalyzedArgumentType]): AnalyzedUnion =
  var concreteVariants: seq[AnalyzedVariant]
  for variant in union.variants:
    let concreteVariant = variant.concrete(impls, union.genericTypeIndex)
    concreteVariants.add(concreteVariant)
  newAnalyzedUnion(union.resolved, concreteVariants, union.genericTypeIndex)

proc findVariant*(union: AnalyzedUnion, variant: Identifier): Result[AnalyzedVariant, string] =
  if variant in union.variantIndex: ok(union.variants[union.variantIndex[variant]])
  else: err(fmt"{variant.loc} union does not contain variant `{variant.asl}`")

proc analyzeUnion*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, union: ResolvedUnionDef): Result[AnalyzedUnion, string] =
  var analyzedVariants: seq[AnalyzedVariant]
  var genericTypeIndex: Table[AnalyzedGenericArgumentType, int]
  for variant in union.variants:
    let analyzedVariant = ? analyzeVariant(app, file, fileScope, module, variant, genericTypeIndex)
    analyzedVariants.add(analyzedVariant)
  ok(newAnalyzedUnion(union, analyzedVariants, genericTypeIndex))

# AnalyzedData
type
  AnalyzedDataKind* = enum
    adkLiteral, adkStruct, adkUnion
  AnalyzedData* = ref object
    case kind: AnalyzedDataKind
    of adkLiteral: literal: AnalyzedLiteralBlock
    of adkStruct: struct: AnalyzedStruct
    of adkUnion: union: AnalyzedUnion

proc newAnalyzedData*(literal: AnalyzedLiteralBlock): AnalyzedData =
  AnalyzedData(kind: adkLiteral, literal: literal)

proc newAnalyzedData*(struct: AnalyzedStruct): AnalyzedData =
  AnalyzedData(kind: adkStruct, struct: struct)

proc newAnalyzedData*(union: AnalyzedUnion): AnalyzedData =
  AnalyzedData(kind: adkUnion, union: union)

proc kind*(d: AnalyzedData): AnalyzedDataKind = d.kind
proc literal*(d: AnalyzedData): AnalyzedLiteralBlock =
  assert d.kind == adkLiteral,
    fmt"AnalyzedData.literal accessed but kind is {d.kind}"
  d.literal
proc struct*(d: AnalyzedData): AnalyzedStruct =
  assert d.kind == adkStruct,
    fmt"AnalyzedData.struct accessed but kind is {d.kind}"
  d.struct
proc union*(d: AnalyzedData): AnalyzedUnion =
  assert d.kind == adkUnion,
    fmt"AnalyzedData.union accessed but kind is {d.kind}"
  d.union

proc analyzeData*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, data: ResolvedData): Result[AnalyzedData, string] =
  case data.kind:
  of rdkLiteral:
    ok(newAnalyzedData(newAnalyzedLiteralBlock(data.literal)))
  of rdkStruct:
    let analyzedStruct = ? analyzeStruct(app, file, fileScope, module, data.struct)
    ok(newAnalyzedData(analyzedStruct))
  of rdkUnion:
    let analyzedUnion = ? analyzeUnion(app, file, fileScope, module, data.union)
    ok(newAnalyzedData(analyzedUnion))

# AnalyzedModuleDefinition
type AnalyzedModuleDefinition* = ref object
  resolved: ResolvedModule
  requires: seq[AnalyzedGenericArgumentType]
  data: Option[AnalyzedData]
  funcDefs: seq[AnalyzedFunctionDefinition]
  funcNameArityIndex: Table[Identifier, Table[int, seq[int]]]
  funcDefIndex: Table[ResolvedFunctionDef, int]

proc buildFuncNameArityIndex(funcDefs: seq[AnalyzedFunctionDefinition]): Table[Identifier, Table[int, seq[int]]] =
  for id, funcDef in funcDefs:
    if funcDef.name notin result:
      result[funcDef.name] = initTable[int, seq[int]]()
    if funcDef.arity notin result[funcDef.name]:
      result[funcDef.name][funcDef.arity] = newSeq[int]()
    result[funcDef.name][funcDef.arity].add(id)

proc newAnalyzedModuleDefinition*(resolved: ResolvedModule, requires: seq[AnalyzedGenericArgumentType], data: Option[AnalyzedData], funcDefs: seq[AnalyzedFunctionDefinition]): AnalyzedModuleDefinition =
  var funcDefIndex: Table[ResolvedFunctionDef, int]
  for id, funcDef in funcDefs:
    funcDefIndex[funcDef.resolved] = id
  AnalyzedModuleDefinition(resolved: resolved, requires: requires, data: data, funcDefs: funcDefs, funcNameArityIndex: buildFuncNameArityIndex(funcDefs), funcDefIndex: funcDefIndex)

proc resolved*(m: AnalyzedModuleDefinition): ResolvedModule = m.resolved
proc requires*(m: AnalyzedModuleDefinition): seq[AnalyzedGenericArgumentType] = m.requires
proc data*(m: AnalyzedModuleDefinition): Option[AnalyzedData] = m.data
proc funcDefs*(m: AnalyzedModuleDefinition): seq[AnalyzedFunctionDefinition] = m.funcDefs
proc name*(m: AnalyzedModuleDefinition): Identifier = m.resolved.name
proc loc*(m: AnalyzedModuleDefinition): Location = m.resolved.loc

proc findFunctionDefs*(module: AnalyzedModuleDefinition, name: Identifier, arity: int, public: bool): Result[seq[AnalyzedFunctionDefinition], string] =
  # TODO: Ensure public access modifier is considered while looking up the function
  if name notin module.funcNameArityIndex:
    err(fmt"{name.loc} module `{module.name.asl}` does not have a function named `{name.asl}`")
  elif arity notin module.funcNameArityIndex[name]:
    err(fmt"{name.loc} module `{module.name.asl}` does not have a function named `{name.asl}` with arity `{arity}`")
  else:
    let funcDefs = module.funcNameArityIndex[name][arity].mapIt(module.funcDefs[it])
    ok(if public: funcDefs.filterIt(it.public) else: funcDefs)

proc findFunctionDef*(module: AnalyzedModuleDefinition, funcDef: ResolvedFunctionDef): Result[AnalyzedFunctionDefinition, string] =
  if funcDef notin module.funcDefIndex:
    err(fmt"{funcDef.loc} module `{module.name.asl}` does not have a function with name `{funcDef.name.asl}`")
  else:
    ok(module.funcDefs[module.funcDefIndex[funcDef]])

proc analyzeModuleDefinition*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule): Result[AnalyzedModuleDefinition, string] =
  var requires: seq[AnalyzedGenericArgumentType]
  for genericArgType in module.requires:
    let analyzedArgType = ? analyzeGenericArgumentType(app, file, module, genericArgType)
    requires.add(analyzedArgType)

  var maybeAnalyzedData: Option[AnalyzedData]
  if module.data.isSome:
    let analyzedData = ? analyzeData(app, file, fileScope, module, module.data.get)
    maybeAnalyzedData = some(analyzedData)

  var analyzedFuncDefs: seq[AnalyzedFunctionDefinition]
  for function in module.functions:
    let analyzedFuncDef = ? analyzeFunctionDefinition(app, file, fileScope, module, function.def)
    analyzedFuncDefs.add(analyzedFuncDef)

  ok(newAnalyzedModuleDefinition(module, requires, maybeAnalyzedData, analyzedFuncDefs))

# AnalyzedGeneric
type AnalyzedGeneric* = ref object
  resolved: ResolvedGeneric
  funcDefs: seq[AnalyzedFunctionDefinition]
  funcNameArityIndex: Table[Identifier, Table[int, seq[int]]]

proc newAnalyzedGeneric*(resolved: ResolvedGeneric, funcDefs: seq[AnalyzedFunctionDefinition]): AnalyzedGeneric =
  AnalyzedGeneric(resolved: resolved, funcDefs: funcDefs, funcNameArityIndex: buildFuncNameArityIndex(funcDefs))

proc name*(g: AnalyzedGeneric): Identifier = g.resolved.name
proc resolved*(g: AnalyzedGeneric): ResolvedGeneric = g.resolved
proc funcDefs*(g: AnalyzedGeneric): seq[AnalyzedFunctionDefinition] = g.funcDefs

# NOTE: generic does not require the function defs to be marked public explicitly
proc findFunctionDefs*(generic: AnalyzedGeneric, name: Identifier, arity: int): Result[seq[AnalyzedFunctionDefinition], string] =
  if name notin generic.funcNameArityIndex:
    err(fmt"{name.loc} generic `{generic.name.asl}` does not have a function named `{name.asl}`")
  elif arity notin generic.funcNameArityIndex[name]:
    err(fmt"{name.loc} generic `{generic.name.asl}` does not have a function named `{name.asl}` with arity `{arity}`")
  else:
    let funcDefs = generic.funcNameArityIndex[name][arity].mapIt(generic.funcDefs[it])
    ok(funcDefs)

proc analyzeGeneric*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, generic: ResolvedGeneric): Result[AnalyzedGeneric, string] =
  var analyzedFuncDefs: seq[AnalyzedFunctionDefinition]
  for funcDef in generic.funcDefs:
    let analyzedFuncDef = ? analyzeFunctionDefinition(app, file, fileScope, generic, funcDef)
    analyzedFuncDefs.add(analyzedFuncDef)
  ok(newAnalyzedGeneric(generic, analyzedFuncDefs))

# AnalyzedDefinedType — umbrella over module and generic definitions.
# Lives in modules.nim (not decls.nim) so funcs.nim can use it for
# AnalyzedDefinedTypeScope without creating a circular import with decls.
type
  AnalyzedDefinedTypeKind* = enum
    adtkModule, adtkGeneric
  AnalyzedDefinedType* = ref object
    case kind: AnalyzedDefinedTypeKind
    of adtkModule: module: AnalyzedModuleDefinition
    of adtkGeneric: generic: AnalyzedGeneric

proc newAnalyzedDefinedType*(module: AnalyzedModuleDefinition): AnalyzedDefinedType =
  AnalyzedDefinedType(kind: adtkModule, module: module)

proc newAnalyzedDefinedType*(generic: AnalyzedGeneric): AnalyzedDefinedType =
  AnalyzedDefinedType(kind: adtkGeneric, generic: generic)

proc kind*(d: AnalyzedDefinedType): AnalyzedDefinedTypeKind = d.kind
proc module*(d: AnalyzedDefinedType): AnalyzedModuleDefinition =
  assert d.kind == adtkModule,
    fmt"AnalyzedDefinedType.module accessed but kind is {d.kind}"
  d.module
proc generic*(d: AnalyzedDefinedType): AnalyzedGeneric =
  assert d.kind == adtkGeneric,
    fmt"AnalyzedDefinedType.generic accessed but kind is {d.kind}"
  d.generic
proc name*(d: AnalyzedDefinedType): Identifier =
  case d.kind:
  of adtkModule: d.module.name
  of adtkGeneric: d.generic.name

proc findFunctionDefs*(definedType: AnalyzedDefinedType, name: Identifier, arity: int, public: bool): Result[seq[AnalyzedFunctionDefinition], string] =
  case definedType.kind:
  of adtkModule: definedType.module.findFunctionDefs(name, arity, public)
  of adtkGeneric: definedType.generic.findFunctionDefs(name, arity)

proc analyzeDefinedType*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, definedType: ResolvedType): Result[AnalyzedDefinedType, string] =
  case definedType.kind:
  of rdtkGeneric:
    let analyzedGeneric = ? analyzeGeneric(app, file, fileScope, definedType.generic)
    ok(newAnalyzedDefinedType(analyzedGeneric))
  of rdtkModule:
    let analyzedModule = ? analyzeModuleDefinition(app, file, fileScope, definedType.module)
    ok(newAnalyzedDefinedType(analyzedModule))

type AnalyzedDefinedTypeScope* = Table[Identifier, AnalyzedDefinedType]

proc findType*(defScope: AnalyzedDefinedTypeScope, name: Identifier, loc: Location): Result[AnalyzedDefinedType, string] =
  if name notin defScope:
    err(fmt"{loc} UNREACHABLE: type `{name.asl}` is not defined")
  else:
    ok(defScope[name])

proc findModuleDef*(defScope: AnalyzedDefinedTypeScope, name: Identifier, loc: Location): Result[AnalyzedModuleDefinition, string] =
  let entry = ? defScope.findType(name, loc)
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

# AnalyzedFileDefinition
type AnalyzedFileDefinition* = ref object
  resolved: ResolvedFile
  imports: seq[AnalyzedImportDefinition]
  types: seq[AnalyzedDefinedType]
  scope: ResolvedFileScope
  definedTypeIndex: AnalyzedDefinedTypeScope

proc newAnalyzedFileDefinition*(resolved: ResolvedFile, imports: seq[AnalyzedImportDefinition], types: seq[AnalyzedDefinedType], scope: ResolvedFileScope): AnalyzedFileDefinition =
  var definedTypeIndex: AnalyzedDefinedTypeScope
  for definedType in types:
    definedTypeIndex[definedType.name] = definedType
  AnalyzedFileDefinition(resolved: resolved, imports: imports, types: types, scope: scope, definedTypeIndex: definedTypeIndex)

proc resolved*(f: AnalyzedFileDefinition): ResolvedFile = f.resolved
proc path*(f: AnalyzedFileDefinition): string = f.resolved.path
proc imports*(f: AnalyzedFileDefinition): seq[AnalyzedImportDefinition] = f.imports
proc types*(f: AnalyzedFileDefinition): seq[AnalyzedDefinedType] = f.types
proc scope*(f: AnalyzedFileDefinition): ResolvedFileScope = f.scope
proc definedTypeIndex*(f: AnalyzedFileDefinition): AnalyzedDefinedTypeScope = f.definedTypeIndex

proc findType*(fileDef: AnalyzedFileDefinition, name: Identifier): Result[AnalyzedDefinedType, string] =
  if name notin fileDef.definedTypeIndex:
    err(fmt"{name.loc} file `{fileDef.path}` does not defined a type named `{name.asl}`")
  else:
    ok(fileDef.definedTypeIndex[name])

proc analyzeFileDefinition*(app: ResolvedApp, file: ResolvedFile): Result[AnalyzedFileDefinition, string] =
  var fileScope: ResolvedFileScope
  var analyzedImports: seq[AnalyzedImportDefinition]
  for imp in file.imports:
    let analyzedImport = ? analyzeImportDefinition(app, file, imp)
    analyzedImports.add(analyzedImport)
    for impType in analyzedImport.importedTypes:
      fileScope[impType.binding] = impType.definedType

  var analyzedDefinedTypes: seq[AnalyzedDefinedType]
  for aslType in file.types:
    let analyzedDefinedType = ? analyzeDefinedType(app, file, fileScope, aslType)
    analyzedDefinedTypes.add(analyzedDefinedType)
  ok(newAnalyzedFileDefinition(file, analyzedImports, analyzedDefinedTypes, fileScope))

# AnalyzedAppDefinition + entry
type AnalyzedAppDefinition* = ref object
  resolved: ResolvedApp
  fileDefs: seq[AnalyzedFileDefinition]
  fileDefIndex: Table[string, int]

proc newAnalyzedAppDefinition*(resolved: ResolvedApp, fileDefs: seq[AnalyzedFileDefinition]): AnalyzedAppDefinition =
  var fileDefIndex: Table[string, int]
  for index, fileDef in fileDefs:
    fileDefIndex[fileDef.path] = index
  AnalyzedAppDefinition(resolved: resolved, fileDefs: fileDefs, fileDefIndex: fileDefIndex)

proc resolved*(a: AnalyzedAppDefinition): ResolvedApp = a.resolved
proc fileDefs*(a: AnalyzedAppDefinition): seq[AnalyzedFileDefinition] = a.fileDefs

proc findFileDef(appDef: AnalyzedAppDefinition, path: string): Result[AnalyzedFileDefinition, string] =
  if path notin appDef.fileDefIndex:
    err(fmt"file `{path}` not found")
  else:
    ok(appDef.fileDefs[appDef.fileDefIndex[path]])

proc analyzeAppDefinition*(app: ResolvedApp): Result[AnalyzedAppDefinition, string] =
  var analyzedFileDefinitions: seq[AnalyzedFileDefinition]
  for file in app.files:
    let analyzedFileDefinition = ? analyzeFileDefinition(app, file)
    analyzedFileDefinitions.add(analyzedFileDefinition)
  ok(newAnalyzedAppDefinition(app, analyzedFileDefinitions))

proc genericIntScanner*[T: SomeInteger](input: string, res: var T, start: int): int =
  # 1. Compile-time branching based on whether T is signed or unsigned
  when T is SomeUnsignedInt:
    var temp: BiggestUInt
    let charsParsed = parseBiggestUInt(input, temp, start)

    # Check bounds against the exact target unsigned limits
    if charsParsed > 0 and temp <= high(T).BiggestUInt:
      res = T(temp)
      return charsParsed
  else:
    var temp: BiggestInt
    let charsParsed = parseBiggestInt(input, temp, start)

    # Check bounds against the exact target signed limits
    if charsParsed > 0 and temp >= low(T).BiggestInt and temp <= high(T).BiggestInt:
      res = T(temp)
      return charsParsed

  return 0 # Mismatch or out of bounds

# Clean generic wrapper function
proc parseInteger*[T: SomeInteger](s: string): Option[T] =
  var res: T
  if scanf(s, "${genericIntScanner}", res):
    return some(res)
  else:
    return none(T)

# True iff the syntactically-validated decimal float literal `text`
# is exactly representable as `mantissa * 2^k` for some non-negative
# integer mantissa with at most `mantissaBits` significant bits (i.e.
# `mantissa <= 2^mantissaBits`) and some integer `k`. The decision
# uses a rational-form decomposition: any literal denotes
# `M * 10^E = M * 2^E * 5^E`, so an exact binary representation
# requires that `5^E` either combine with M without overflow (E >= 0)
# or divide M cleanly (E < 0). Decimal fractions like `0.1` whose
# denominator has a 5-factor that does not cancel are rejected here.
# Used by `parseFloat[T]` to surface precision loss at the literal
# site rather than letting it slip silently into the analyzer's
# stored value.
proc isExactlyRepresentable*(text: string, mantissaBits: int): bool =
  var s = text
  if s.len > 0 and (s[0] == '+' or s[0] == '-'):
    s = s[1..^1]

  var mantText, expText: string
  let eIdx = s.find({'e', 'E'})
  if eIdx >= 0:
    mantText = s[0..<eIdx]
    expText = s[eIdx+1..^1]
  else:
    mantText = s
    expText = "0"

  var intPart, fracPart: string
  let dotIdx = mantText.find('.')
  if dotIdx >= 0:
    intPart = mantText[0..<dotIdx]
    fracPart = mantText[dotIdx+1..^1]
  else:
    intPart = mantText
    fracPart = ""

  # Trailing zeros on the fractional part don't change the value;
  # stripping them keeps E small so `5^|E|` stays in BiggestUInt.
  while fracPart.len > 0 and fracPart[^1] == '0':
    fracPart = fracPart[0..^2]
  # Leading zeros on the integer part are also value-neutral.
  while intPart.len > 1 and intPart[0] == '0':
    intPart = intPart[1..^1]

  var combined = intPart & fracPart
  if combined.len == 0: combined = "0"
  while combined.len > 1 and combined[0] == '0':
    combined = combined[1..^1]

  var M: BiggestUInt
  try:
    M = parseBiggestUInt(combined)
  except ValueError:
    return false  # mantissa string too long for our scratch integer

  if M == 0: return true

  var E: int
  try:
    E = parseInt(expText) - fracPart.len
  except ValueError:
    return false

  let maxMantissa = 1'u64 shl mantissaBits

  if E >= 0:
    # value = M * 10^E. Multiply, watching for overflow.
    var v: BiggestUInt = M
    for _ in 0..<E:
      let next = v * 10
      if next div 10 != v: return false
      v = next
    # Strip factors of 2 — they're absorbed into the binary exponent.
    while (v and 1'u64) == 0 and v != 0:
      v = v shr 1
    return v <= maxMantissa
  else:
    # value = M / 10^|E|. 10^|E| = 2^|E| * 5^|E|. For exact binary
    # representation, 5^|E| must divide M.
    let k = -E
    var fiveK: BiggestUInt = 1
    for _ in 0..<k:
      let next = fiveK * 5
      if next div 5 != fiveK: return false
      fiveK = next
    if M mod fiveK != 0: return false
    var mant: BiggestUInt = M div fiveK
    while (mant and 1'u64) == 0 and mant != 0:
      mant = mant shr 1
    return mant <= maxMantissa

# Sibling of `parseInteger` — same `Option[T]` shape, dispatched at
# compile time on T. Only the "value cannot be reduced to a finite
# T at all" failure modes surface here as `none(T)`:
#
#   - out-of-range overflow that `parseutils.parseFloat` reports as
#     0-chars-consumed (literal text too large to fit in `float`);
#   - the parsed value classifies as ±Inf or NaN — currently always
#     rejected (see TODO below);
#   - float32 targets whose narrowed value overflows to ±Inf.
#
# Exact-representability (precision loss) is deliberately NOT
# checked here — the caller (`analyzeFloatLiteral` in body.nim)
# runs `isExactlyRepresentable` after a successful parse and emits
# a warning for lossy literals, so this proc returns the closest
# representable value in every finite case.
#
# TODO(float-special-values): Inf, -Inf, and NaN are deliberately
# rejected today — there is no surface syntax to write them
# (`f64 inf` doesn't parse, since the float-literal spec requires
# digits) and the float modules in base.aslr expose no
# is_finite / is_nan classifiers, so a producer-of-Inf could only
# come from an arithmetic overflow that ASL already reroutes through
# Status[T]. When the language grows special-value literals
# (`f64.inf`, `f64.nan`) and classification predicates, this
# unconditional reject should be relaxed.
proc parseFloat*[T: SomeFloat](s: string): Option[T] =
  var temp: float
  if parseutils.parseFloat(s, temp) == 0: return none(T)
  when T is float32:
    let narrowed = temp.float32
    if narrowed.classify in {fcInf, fcNegInf, fcNan}: return none(T)
    some(narrowed)
  elif T is float64:
    if temp.classify in {fcInf, fcNegInf, fcNan}: return none(T)
    some(temp)

type AnalyzedVariantPatternScope* = ref object
  variablePatternFound: bool
  totalCases: int
  variants: HashSet[Identifier]

proc newAnalyzedVariantPatternScope*(totalCases: int): AnalyzedVariantPatternScope =
  AnalyzedVariantPatternScope(variablePatternFound: false, totalCases: totalCases, variants: initHashSet[Identifier]())

proc update*(scope: AnalyzedVariantPatternScope, id: int, pattern: ResolvedCasePattern): Result[AnalyzedVariantPatternScope, string] =
  case pattern.kind:
  of rcpkInteger:
    err(fmt"{pattern.loc} expected a union variant but found integer literal")
  of rcpkVariable:
    if id != scope.totalCases - 1:
      err(fmt"{pattern.loc} variable pattern binding is supported only in the last case block")
    else:
      scope.variablePatternFound = true
      ok(scope)
  of rcpkVariant:
    if pattern.variant.name in scope.variants:
      err(fmt"{pattern.variant.loc} found duplicate variant `{pattern.variant.name.asl}`")
    else:
      scope.variants.incl(pattern.variant.name)
      ok(scope)

# NOTE: If there is no variable pattern in union matching then all branches must be covered
proc hasUncoveredCases*(scope: AnalyzedVariantPatternScope, totalVariants: int, loc: Location): Result[void, string] =
  # TODO: improve error message by showing the uncovered variants
  if scope.variablePatternFound:
    if scope.variants.len < totalVariants: ok()
    else: err(fmt"{loc} variable binding is invalid since all the variants are already covered by the case blocks")
  else:
    if scope.variants.len == totalVariants: ok()
    else: err(fmt"{loc} case blocks do not cover all the variants")

type
  AnalyzedLiteralPatternScopeKind* = enum
    alpskU8, alpskU16, alpskU32, alpskU64,
    alpskI8, alpskI16, alpskI32, alpskI64
  AnalyzedLiteralPatternScope* = ref object
    totalCases: int
    variablePatternFound: bool
    case kind: AnalyzedLiteralPatternScopeKind
    of alpskU8: u8Values:  HashSet[uint8]
    of alpskU16: u16Values: HashSet[uint16]
    of alpskU32: u32Values: HashSet[uint32]
    of alpskU64: u64Values: HashSet[uint64]
    of alpskI8: i8Values:  HashSet[int8]
    of alpskI16: i16Values: HashSet[int16]
    of alpskI32: i32Values: HashSet[int32]
    of alpskI64: i64Values: HashSet[int64]

proc newAnalyzedLiteralPatternScope*(literal: ResolvedLiteralDef, totalCases: int): Result[AnalyzedLiteralPatternScope, string] =
  case literal:
  of rltkU8: ok(AnalyzedLiteralPatternScope(kind: alpskU8,  totalCases: totalCases, variablePatternFound: false, u8Values:  initHashSet[uint8]()))
  of rltkU16: ok(AnalyzedLiteralPatternScope(kind: alpskU16, totalCases: totalCases, variablePatternFound: false, u16Values: initHashSet[uint16]()))
  of rltkU32: ok(AnalyzedLiteralPatternScope(kind: alpskU32, totalCases: totalCases, variablePatternFound: false, u32Values: initHashSet[uint32]()))
  of rltkU64: ok(AnalyzedLiteralPatternScope(kind: alpskU64, totalCases: totalCases, variablePatternFound: false, u64Values: initHashSet[uint64]()))
  of rltkI8: ok(AnalyzedLiteralPatternScope(kind: alpskI8,  totalCases: totalCases, variablePatternFound: false, i8Values:  initHashSet[int8]()))
  of rltkI16: ok(AnalyzedLiteralPatternScope(kind: alpskI16, totalCases: totalCases, variablePatternFound: false, i16Values: initHashSet[int16]()))
  of rltkI32: ok(AnalyzedLiteralPatternScope(kind: alpskI32, totalCases: totalCases, variablePatternFound: false, i32Values: initHashSet[int32]()))
  of rltkI64: ok(AnalyzedLiteralPatternScope(kind: alpskI64, totalCases: totalCases, variablePatternFound: false, i64Values: initHashSet[int64]()))
  of rltkF32: err("match block does not support f32 values in case patterns")
  of rltkF64: err("match block does not support f64 values in case patterns")
  of rltkString: err("match block does not support string values in case patterns")
  of rltkPointer: err("match block does not support pointer values in case patterns")

proc checkDuplicate[T: SomeInteger](values: var HashSet[T], integer: IntegerLiteral, expected: string): Result[void, string] =
  let maybeInt = parseInteger[T](integer.asl)
  if maybeInt.isNone:
    err(fmt"{integer.loc} expected value to be a valid {expected}")
  elif maybeInt.get in values:
    err(fmt"{integer.loc} duplicated integer pattern encountered")
  else:
    values.incl(maybeInt.get)
    ok()

proc checkDuplicate(scope: AnalyzedLiteralPatternScope, integer: IntegerLiteral): Result[AnalyzedLiteralPatternScope, string] =
  case scope.kind:
  of alpskU8: ? checkDuplicate[uint8](scope.u8Values, integer, "valid 8-bit unsigned integer")
  of alpskU16: ? checkDuplicate[uint16](scope.u16Values, integer, "valid 16-bit unsigned integer")
  of alpskU32: ? checkDuplicate[uint32](scope.u32Values, integer, "valid 32-bit unsigned integer")
  of alpskU64: ? checkDuplicate[uint64](scope.u64Values, integer, "valid 64-bit unsigned integer")
  of alpskI8: ? checkDuplicate[int8](scope.i8Values, integer, "valid 8-bit signed integer")
  of alpskI16: ? checkDuplicate[int16](scope.i16Values, integer, "valid 16-bit signed integer")
  of alpskI32: ? checkDuplicate[int32](scope.i32Values, integer, "valid 32-bit signed integer")
  of alpskI64: ? checkDuplicate[int64](scope.i64Values, integer, "valid 64-bit signed integer")
  ok(scope)

proc update*(scope: AnalyzedLiteralPatternScope, id: int, pattern: ResolvedCasePattern): Result[AnalyzedLiteralPatternScope, string] =
  case pattern.kind:
  of rcpkVariant:
    err(fmt"{pattern.loc} expected a literal pattern but found variant pattern")
  of rcpkVariable:
    if id != scope.totalCases - 1:
      err(fmt"{pattern.loc} variable pattern binding is supported only in the last case block")
    else:
      scope.variablePatternFound = true
      ok(scope)
  of rcpkInteger:
    scope.checkDuplicate(pattern.integer)

# NOTE: If there is no variable pattern in union matching then all branches must be covered
proc hasUncoveredCases*(scope: AnalyzedLiteralPatternScope, loc: Location): Result[void, string] =
  # TODO: improve error message by showing the uncovered variants
  if scope.variablePatternFound: ok()
  else: err(fmt"{loc} variable case pattern binding is required for integer literal pattern")

type AnalyzedVariantPattern* = ref object
  resolved: VariantPattern
  variant: AnalyzedVariant
  fields: seq[AnalyzedArgumentDefinition]

proc newAnalyzedVariantPattern*(resolved: VariantPattern, variant: AnalyzedVariant, fields: seq[AnalyzedArgumentDefinition]): AnalyzedVariantPattern =
  AnalyzedVariantPattern(resolved: resolved, variant: variant, fields: fields)

proc bindings*(pattern: AnalyzedVariantPattern): seq[AnalyzedArgumentDefinition] =
  var bindings: seq[AnalyzedArgumentDefinition]
  for (field, argDef) in zip(pattern.resolved.fields, pattern.fields):
    let bindingDef = newAnalyzedArgumentDefinition(argDef.argType, field.binding)
    bindings.add(bindingDef)
  return bindings

proc analyzeVariantCasePattern*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, variantPattern: VariantPattern, union: AnalyzedUnion): Result[AnalyzedVariantPattern, string] =
  let variant = ? union.findVariant(variantPattern.name)
  var analyzedFields: seq[AnalyzedArgumentDefinition]
  for field in variantPattern.fields:
    let analyzedField = ? variant.findField(field.name)
    analyzedFields.add(analyzedField)
  ok(newAnalyzedVariantPattern(variantPattern, variant, analyzedFields))

type
  AnalyzedCasePatternKind* = enum
    acpkVariant, acpkInteger, acpkVariable
  AnalyzedCasePattern* = ref object
    case kind: AnalyzedCasePatternKind
    of acpkVariant: variant: AnalyzedVariantPattern
    of acpkInteger: integer: IntegerLiteral
    of acpkVariable: variable: AnalyzedArgumentDefinition

proc newAnalyzedCasePattern*(variant: AnalyzedVariantPattern): AnalyzedCasePattern =
  AnalyzedCasePattern(kind: acpkVariant, variant: variant)

proc newAnalyzedCasePattern*(integer: IntegerLiteral): AnalyzedCasePattern =
  AnalyzedCasePattern(kind: acpkInteger, integer: integer)

proc newAnalyzedCasePattern*(variable: AnalyzedArgumentDefinition): AnalyzedCasePattern =
  AnalyzedCasePattern(kind: acpkVariable, variable: variable)

proc bindings*(pattern: AnalyzedCasePattern): seq[AnalyzedArgumentDefinition] =
  case pattern.kind:
  of acpkVariant: pattern.variant.bindings
  of acpkVariable: @[pattern.variable]
  of acpkInteger: newSeq[AnalyzedArgumentDefinition]()

proc analyzeCasePattern*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, pattern: ResolvedCasePattern, subjectType: AnalyzedArgumentType, union: AnalyzedUnion): Result[AnalyzedCasePattern, string] =
  case pattern.kind:
  of rcpkInteger: err(fmt"{pattern.loc} UNREACHABLE: integer literals are not allowed in union case pattern")
  of rcpkVariable:
    let analyzedArgDef = newAnalyzedArgumentDefinition(subjectType, pattern.variable)
    ok(newAnalyzedCasePattern(analyzedArgDef))
  of rcpkVariant:
    let analyzedPattern = ? analyzeVariantCasePattern(app, file, fileScope, defScope, funcScope, pattern.variant, union)
    ok(newAnalyzedCasePattern(analyzedPattern))

proc analyzeCasePattern*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, pattern: ResolvedCasePattern, subjectType: AnalyzedArgumentType): Result[AnalyzedCasePattern, string] =
  case pattern.kind:
  of rcpkVariant:
    err(fmt"{pattern.loc} UNREACHABLE: union variants are not allowed in literal case pattern")
  of rcpkInteger:
    ok(newAnalyzedCasePattern(pattern.integer))
  of rcpkVariable:
    let analyzedArgDef = newAnalyzedArgumentDefinition(subjectType, pattern.variable)
    ok(newAnalyzedCasePattern(analyzedArgDef))

proc analyzeIntegerLiteral[T: SomeInteger](literal: Literal, expected: string): Result[void, string] =
  case literal.kind:
  of lkFloat: err(fmt"{literal.loc} expected a valid {expected} but found float")
  of lkString: err(fmt"{literal.loc} expected a valid {expected} but found string")
  of lkInteger:
    let maybeParsedInt = parseInteger[T](literal.asl)
    if maybeParsedInt.isSome: ok()
    else: err(fmt"{literal.loc} expected a valid {expected} but found `{literal.asl}`")

proc analyzeStringLiteral(literal: Literal): Result[void, string] =
  case literal.kind:
  of lkFloat: err(fmt"{literal.loc} expected a valid string literal but found float")
  of lkInteger: err(fmt"{literal.loc} expected a valid string literal but found integer")
  of lkString: ok()

proc analyzeFloatLiteral[T: SomeFloat](literal: Literal, expected: string): Result[void, string] =
  case literal.kind:
  of lkInteger: err(fmt"{literal.loc} expected a valid {expected} but found integer")
  of lkString: err(fmt"{literal.loc} expected a valid {expected} but found string")
  of lkFloat:
    let maybeParsedFloat = parseFloat[T](literal.asl)
    if maybeParsedFloat.isNone:
      return err(fmt"{literal.loc} expected a valid {expected} but found `{literal.asl}`")
    # Exact-representability is a warning, not an error: the closest
    # approximation stored in the parsed value is still returned as
    # the literal's value. Emit to stderr with the source location
    # so users can find and (if they choose) rewrite lossy literals
    # as runtime quotients of exact-integer literals.
    # TODO(diagnostics): thread warnings through the analyzer as a
    # collected seq rather than writing to stderr from deep inside
    # the pass.
    const mantissaBits =
      when T is float32: 24
      elif T is float64: 53
    if not isExactlyRepresentable(literal.asl, mantissaBits):
      stderr.writeLine(fmt"[WARN] {literal.loc} literal `{literal.asl}` cannot be exactly represented in {expected}; using closest approximation")
    ok()

proc analyzeLiteral(literalDef: ResolvedLiteralDef, literal: Literal): Result[void, string] =
  case literalDef:
  of rltkF32: analyzeFloatLiteral[float32](literal, "32-bit float")
  of rltkF64: analyzeFloatLiteral[float64](literal, "64-bit float")
  of rltkPointer: err(fmt"{literal.loc} todo: analyze literal Pointer literal argument")
  of rltkU8: analyzeIntegerLiteral[uint8](literal, "8-bit unsigned integer")
  of rltkU16: analyzeIntegerLiteral[uint16](literal, "16-bit unsigned integer")
  of rltkU32: analyzeIntegerLiteral[uint32](literal, "32-bit unsigned integer")
  of rltkU64: analyzeIntegerLiteral[uint64](literal, "64-bit unsigned integer")
  of rltkI8: analyzeIntegerLiteral[int8](literal, "8-bit signed integer")
  of rltkI16: analyzeIntegerLiteral[int16](literal, "16-bit signed integer")
  of rltkI32: analyzeIntegerLiteral[int32](literal, "32-bit signed integer")
  of rltkI64: analyzeIntegerLiteral[int64](literal, "64-bit signed integer")
  of rltkString: literal.analyzeStringLiteral()

# AnalyzedVariable — independent of the big cluster.
type AnalyzedVariable* = ref object
  name: Identifier
  argType: AnalyzedArgumentType

proc newAnalyzedVariable*(name: Identifier, argType: AnalyzedArgumentType): AnalyzedVariable =
  AnalyzedVariable(name: name, argType: argType)

proc loc*(variable: AnalyzedVariable): Location = variable.name.loc
proc name*(variable: AnalyzedVariable): Identifier = variable.name
proc argType*(variable: AnalyzedVariable): AnalyzedArgumentType = variable.argType

proc analyzeVariable*(scope: AnalyzedFunctionScope, variable: Identifier): Result[AnalyzedVariable, string] =
  if variable in scope: ok(newAnalyzedVariable(variable, scope[variable]))
  else: err(fmt"{variable.loc} variable `{variable.asl}` does not exist in scope")

type AnalyzedLiteralInitializer = ref object
  resolved: ResolvedLiteralInitializer
  argType: AnalyzedArgumentType

proc newAnalyzedLiteralInitializer(resolved: ResolvedLiteralInitializer, argType: AnalyzedArgumentType): AnalyzedLiteralInitializer =
  AnalyzedLiteralInitializer(resolved: resolved, argType: argType)

proc loc*(init: AnalyzedLiteralInitializer): Location = init.resolved.loc
proc argType*(init: AnalyzedLiteralInitializer): AnalyzedArgumentType = init.argType

proc analyzeLiteralInitializer*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, init: ResolvedLiteralInitializer): Result[AnalyzedLiteralInitializer, string] =
  let analyzedArgType = ? analyzeArgumentType(app, file, fileScope, moduleDef.resolved, init.argType)
  let argDefModule = ? defScope.findModuleDef(analyzedArgType, init.loc)
  let argDefData = ? defScope.extractDataBlock(argDefModule, init.loc)
  case argDefData.kind:
  of adkStruct: err(fmt"{init.loc} statement expects a literal initializer `{argDefModule.name.asl}`")
  of adkUnion: err(fmt"{init.loc} statement expects a literal initializer `{argDefModule.name.asl}`")
  of adkLiteral:
    let maybeValidLiteral = analyzeLiteral(argDefData.literal.resolved, init.literal)
    if maybeValidLiteral.isOk: ok(newAnalyzedLiteralInitializer(init, analyzedArgType))
    else: err(maybeValidLiteral.error)

# AnalyzedGetter — independent of the big cluster.
type AnalyzedGetter* = ref object
  resolved: ResolvedGetter
  source: AnalyzedArgumentType
  property: AnalyzedArgumentDefinition

proc newAnalyzedGetter*(resolved: ResolvedGetter, source: AnalyzedArgumentType, property: AnalyzedArgumentDefinition): AnalyzedGetter =
  AnalyzedGetter(resolved: resolved, source: source, property: property)

proc loc*(getter: AnalyzedGetter): Location = getter.resolved.loc
proc resolved*(getter: AnalyzedGetter): ResolvedGetter = getter.resolved
proc source*(getter: AnalyzedGetter): AnalyzedArgumentType = getter.source
proc argType*(getter: AnalyzedGetter): AnalyzedArgumentType = getter.property.argType
proc property*(getter: AnalyzedGetter): AnalyzedArgumentDefinition = getter.property

proc analyzeGetter*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, getter: ResolvedGetter): Result[AnalyzedGetter, string] =
  if getter.source notin funcScope:
    err(fmt"{getter.loc} variable `{getter.source.asl}` is not present in scope")
  else:
    let analyzedSourceArgType = funcScope[getter.source]
    let struct = ? defScope.extractStructFor(analyzedSourceArgType, getter.loc)
    let analyzedProperty = ? struct.findField(getter.property)
    # TODO: coerce the property type from the generic to concrete
    ok(newAnalyzedGetter(getter, analyzedSourceArgType, analyzedProperty))

# Mutually-recursive body-level cluster — every type that cycles
# back to AnalyzedExpression / AnalyzedStatement must live here.
type
  AnalyzedFunctionCall* = ref object
    resolved: ResolvedFunctionCall
    def: AnalyzedFunctionDefinition
    args: seq[AnalyzedExpression]
    returns: AnalyzedArgumentType

  AnalyzedKeywordArgument* = ref object
    # todo: add a concrete type
    resolved: ResolvedKeywordArgument
    field: AnalyzedArgumentDefinition
    expression: AnalyzedExpression

  AnalyzedStructRefKind* = enum
    asrkDefault, asrkImpl
  AnalyzedStructRef* = ref object
    resolved: ResolvedStructRef
    case kind: AnalyzedStructRefKind
    of asrkDefault: module: AnalyzedModuleDefinition
    of asrkImpl: argType: AnalyzedArgumentType

  AnalyzedUnionRefKind* = enum
    aurkDefault, aurkImpl
  AnalyzedUnionRef* = ref object
    resolved: ResolvedUnionRef
    case kind: AnalyzedUnionRefKind
    of aurkDefault: module: AnalyzedModuleDefinition
    of aurkImpl: argType: AnalyzedArgumentType

  AnalyzedStructInitializer* = ref object
    resolved: ResolvedStructInitializer
    structRef: AnalyzedStructRef
    argType: AnalyzedArgumentType
    kwargs: seq[AnalyzedKeywordArgument]

  AnalyzedUnionInitializer* = ref object
    resolved: ResolvedUnionInitializer
    unionRef: AnalyzedUnionRef
    argType: AnalyzedArgumentType
    variant: AnalyzedVariant
    kwargs: seq[AnalyzedKeywordArgument]

  AnalyzedInitializerKind* = enum
    aikUnion, aikStruct, aikLiteral
  AnalyzedInitializer* = ref object
    case kind: AnalyzedInitializerKind
    of aikLiteral: literal: AnalyzedLiteralInitializer
    of aikUnion: union: AnalyzedUnionInitializer
    of aikStruct: struct: AnalyzedStructInitializer

  AnalyzedCaseBlock* = ref object
    resolved: ResolvedCaseBlock
    pattern: AnalyzedCasePattern
    statements: seq[AnalyzedStatement]

  AnalyzedMatchExpression* = ref object
    resolved: ResolvedMatchExpression
    subject: AnalyzedExpression
    cases: seq[AnalyzedCaseBlock]
    returns: AnalyzedArgumentType

  AnalyzedAssignment* = ref object
    resolved: ResolvedAssignment
    expression: AnalyzedExpression

  AnalyzedMutation* = ref object
    resolved: ResolvedSetter
    getter: AnalyzedGetter
    expression: AnalyzedExpression

  AnalyzedExpressionKind* = enum
    aekVariable, aekFunctionCall, aekLiteral, aekMatchExpr, aekInitializer, aekGetter
  AnalyzedExpression* = ref object
    case kind: AnalyzedExpressionKind
    of aekVariable: variable: AnalyzedVariable
    of aekFunctionCall: fncall: AnalyzedFunctionCall
    of aekLiteral: literal: Literal
    of aekMatchExpr: match: AnalyzedMatchExpression
    of aekInitializer: init: AnalyzedInitializer
    of aekGetter: getter: AnalyzedGetter

  AnalyzedStatementKind* = enum
    askExpr, askAssignment, askMutation
  AnalyzedStatement* = ref object
    case kind: AnalyzedStatementKind
    of askExpr: expression: AnalyzedExpression
    of askAssignment: assignment: AnalyzedAssignment
    of askMutation: mutation: AnalyzedMutation

proc argType*(expression: AnalyzedExpression): Option[AnalyzedArgumentType]
proc argType*(statement: AnalyzedStatement): Option[AnalyzedArgumentType]

proc newAnalyzedFunctionCall*(resolved: ResolvedFunctionCall, def: AnalyzedFunctionDefinition, args: seq[AnalyzedExpression], returns: AnalyzedArgumentType): AnalyzedFunctionCall =
  AnalyzedFunctionCall(resolved: resolved, def: def, args: args, returns: returns)

proc loc*(fncall: AnalyzedFunctionCall): Location = fncall.resolved.loc
proc resolved*(fncall: AnalyzedFunctionCall): ResolvedFunctionCall = fncall.resolved
proc def*(fncall: AnalyzedFunctionCall): AnalyzedFunctionDefinition = fncall.def
proc args*(fncall: AnalyzedFunctionCall): seq[AnalyzedExpression] = fncall.args
proc returns*(fncall: AnalyzedFunctionCall): AnalyzedArgumentType = fncall.returns

proc newAnalyzedKeywordArgument*(resolved: ResolvedKeywordArgument, field: AnalyzedArgumentDefinition, expression: AnalyzedExpression): AnalyzedKeywordArgument =
  AnalyzedKeywordArgument(resolved: resolved, field: field, expression: expression)

proc resolved*(kwarg: AnalyzedKeywordArgument): ResolvedKeywordArgument = kwarg.resolved
proc field*(kwarg: AnalyzedKeywordArgument): AnalyzedArgumentDefinition = kwarg.field
proc expression*(kwarg: AnalyzedKeywordArgument): AnalyzedExpression = kwarg.expression

proc newAnalyzedStructRef*(resolved: ResolvedStructRef, module: AnalyzedModuleDefinition): AnalyzedStructRef =
  ## Default kind — stores the analyzed receiver module (looked up via
  ## findModuleDef, handles local and imported alike).
  AnalyzedStructRef(resolved: resolved, kind: asrkDefault, module: module)

proc newAnalyzedStructRef*(resolved: ResolvedStructRef, argType: AnalyzedArgumentType): AnalyzedStructRef =
  ## Impl kind — wraps the analyzed argument type (root + impls).
  AnalyzedStructRef(resolved: resolved, kind: asrkImpl, argType: argType)

proc resolved*(s: AnalyzedStructRef): ResolvedStructRef = s.resolved
proc kind*(s: AnalyzedStructRef): AnalyzedStructRefKind = s.kind
proc module*(s: AnalyzedStructRef): AnalyzedModuleDefinition =
  ## Returns the analyzed receiver module. Only valid for the default
  ## arm; impl-arm callers reach the module via defScope.findModuleDef
  ## with the parser-level name from `resolved.module.name`.
  assert s.kind == asrkDefault,
    fmt"AnalyzedStructRef.module accessed but kind is {s.kind}"
  s.module
proc argType*(s: AnalyzedStructRef): AnalyzedArgumentType =
  assert s.kind == asrkImpl,
    fmt"AnalyzedStructRef.argType accessed but kind is {s.kind}"
  s.argType
proc loc*(s: AnalyzedStructRef): Location = s.resolved.loc

proc newAnalyzedUnionRef*(resolved: ResolvedUnionRef, module: AnalyzedModuleDefinition): AnalyzedUnionRef =
  ## Default kind — stores the analyzed receiver module.
  AnalyzedUnionRef(resolved: resolved, kind: aurkDefault, module: module)

proc newAnalyzedUnionRef*(resolved: ResolvedUnionRef, argType: AnalyzedArgumentType): AnalyzedUnionRef =
  ## Impl kind — wraps the analyzed argument type (root + impls).
  AnalyzedUnionRef(resolved: resolved, kind: aurkImpl, argType: argType)

proc resolved*(u: AnalyzedUnionRef): ResolvedUnionRef = u.resolved
proc kind*(u: AnalyzedUnionRef): AnalyzedUnionRefKind = u.kind
proc module*(u: AnalyzedUnionRef): AnalyzedModuleDefinition =
  ## Returns the analyzed receiver module. Only valid for the default
  ## arm; impl-arm callers reach the module via defScope.findModuleDef
  ## with the parser-level name from `resolved.module.name`.
  assert u.kind == aurkDefault,
    fmt"AnalyzedUnionRef.module accessed but kind is {u.kind}"
  u.module
proc argType*(u: AnalyzedUnionRef): AnalyzedArgumentType =
  assert u.kind == aurkImpl,
    fmt"AnalyzedUnionRef.argType accessed but kind is {u.kind}"
  u.argType
proc loc*(u: AnalyzedUnionRef): Location = u.resolved.loc

proc newAnalyzedStructInitializer*(resolved: ResolvedStructInitializer, structRef: AnalyzedStructRef, argType: AnalyzedArgumentType, kwargs: seq[AnalyzedKeywordArgument]): AnalyzedStructInitializer =
  AnalyzedStructInitializer(resolved: resolved, structRef: structRef, argType: argType, kwargs: kwargs)

proc resolved*(struct: AnalyzedStructInitializer): ResolvedStructInitializer = struct.resolved
proc loc*(init: AnalyzedStructInitializer): Location = init.resolved.loc
proc structRef*(struct: AnalyzedStructInitializer): AnalyzedStructRef = struct.structRef
proc argType*(struct: AnalyzedStructInitializer): AnalyzedArgumentType = struct.argType
proc kwargs*(struct: AnalyzedStructInitializer): seq[AnalyzedKeywordArgument] = struct.kwargs

proc newAnalyzedUnionInitializer*(resolved: ResolvedUnionInitializer, unionRef: AnalyzedUnionRef, argType: AnalyzedArgumentType, variant: AnalyzedVariant, kwargs: seq[AnalyzedKeywordArgument]): AnalyzedUnionInitializer =
  AnalyzedUnionInitializer(resolved: resolved, unionRef: unionRef, argType: argType, variant: variant, kwargs: kwargs)

proc resolved*(init: AnalyzedUnionInitializer): ResolvedUnionInitializer = init.resolved
proc loc*(init: AnalyzedUnionInitializer): Location = init.resolved.loc
proc unionRef*(init: AnalyzedUnionInitializer): AnalyzedUnionRef = init.unionRef
proc module*(init: AnalyzedUnionInitializer): Module = init.resolved.module
proc argType*(init: AnalyzedUnionInitializer): AnalyzedArgumentType = init.argType
proc variant*(init: AnalyzedUnionInitializer): AnalyzedVariant = init.variant
proc kwargs*(init: AnalyzedUnionInitializer): seq[AnalyzedKeywordArgument] = init.kwargs

proc newAnalyzedInitializer*(literal: AnalyzedLiteralInitializer): AnalyzedInitializer =
  AnalyzedInitializer(kind: aikLiteral, literal: literal)

proc newAnalyzedInitializer*(union: AnalyzedUnionInitializer): AnalyzedInitializer =
  AnalyzedInitializer(kind: aikUnion, union: union)

proc newAnalyzedInitializer*(struct: AnalyzedStructInitializer): AnalyzedInitializer =
  AnalyzedInitializer(kind: aikStruct, struct: struct)

proc kind*(init: AnalyzedInitializer): AnalyzedInitializerKind = init.kind
proc union*(init: AnalyzedInitializer): AnalyzedUnionInitializer =
  assert init.kind == aikUnion,
    fmt"AnalyzedInitializer.union accessed but kind is {init.kind}"
  init.union
proc struct*(init: AnalyzedInitializer): AnalyzedStructInitializer =
  assert init.kind == aikStruct,
    fmt"AnalyzedInitializer.struct accessed but kind is {init.kind}"
  init.struct

proc argType*(init: AnalyzedInitializer): AnalyzedArgumentType =
  case init.kind:
  of aikLiteral: init.literal.argType
  of aikUnion: init.union.argType
  of aikStruct: init.struct.argType

proc loc*(init: AnalyzedInitializer): Location =
  case init.kind:
  of aikLiteral: init.literal.loc
  of aikUnion: init.union.loc
  of aikStruct: init.struct.loc

proc newAnalyzedCaseBlock*(resolved: ResolvedCaseBlock, pattern: AnalyzedCasePattern, statements: seq[AnalyzedStatement]): AnalyzedCaseBlock =
  AnalyzedCaseBlock(resolved: resolved, pattern: pattern, statements: statements)

proc loc*(caseBlock: AnalyzedCaseBlock): Location = caseBlock.resolved.loc
proc resolved*(caseBlock: AnalyzedCaseBlock): ResolvedCaseBlock = caseBlock.resolved
proc pattern*(caseBlock: AnalyzedCaseBlock): AnalyzedCasePattern = caseBlock.pattern
proc statements*(caseBlock: AnalyzedCaseBlock): seq[AnalyzedStatement] = caseBlock.statements

proc argType*(caseBlock: AnalyzedCaseBlock): Option[AnalyzedArgumentType] =
  assert(caseBlock.statements.len > 0, "UNREACHABLE: should have been caught by resolver")
  caseBlock.statements[^1].argType

proc newAnalyzedMatchExpression*(resolved: ResolvedMatchExpression, subject: AnalyzedExpression, cases: seq[AnalyzedCaseBlock], returns: AnalyzedArgumentType): AnalyzedMatchExpression =
  AnalyzedMatchExpression(resolved: resolved, subject: subject, cases: cases, returns: returns)

proc loc*(m: AnalyzedMatchExpression): Location = m.resolved.loc
proc resolved*(m: AnalyzedMatchExpression): ResolvedMatchExpression = m.resolved
proc subject*(m: AnalyzedMatchExpression): AnalyzedExpression = m.subject
proc cases*(m: AnalyzedMatchExpression): seq[AnalyzedCaseBlock] = m.cases
proc returns*(m: AnalyzedMatchExpression): AnalyzedArgumentType = m.returns

proc newAnalyzedAssignment*(resolved: ResolvedAssignment, expression: AnalyzedExpression): AnalyzedAssignment =
  AnalyzedAssignment(resolved: resolved, expression: expression)

proc loc*(assignment: AnalyzedAssignment): Location = assignment.resolved.loc
proc resolved*(assignment: AnalyzedAssignment): ResolvedAssignment = assignment.resolved
proc target*(assignment: AnalyzedAssignment): Identifier = assignment.resolved.target
proc expression*(assignment: AnalyzedAssignment): AnalyzedExpression = assignment.expression
proc argType*(assignment: AnalyzedAssignment): Option[AnalyzedArgumentType] = assignment.expression.argType

proc newAnalyzedMutation*(resolved: ResolvedSetter, getter: AnalyzedGetter, expression: AnalyzedExpression): AnalyzedMutation =
  AnalyzedMutation(resolved: resolved, getter: getter, expression: expression)

proc loc*(mutation: AnalyzedMutation): Location = mutation.resolved.loc
proc resolved*(mutation: AnalyzedMutation): ResolvedSetter = mutation.resolved
proc getter*(mutation: AnalyzedMutation): AnalyzedGetter = mutation.getter
proc expression*(mutation: AnalyzedMutation): AnalyzedExpression = mutation.expression
proc argType*(mutation: AnalyzedMutation): Option[AnalyzedArgumentType] = mutation.expression.argType

proc newAnalyzedExpression*(variable: AnalyzedVariable): AnalyzedExpression =
  AnalyzedExpression(kind: aekVariable, variable: variable)

proc newAnalyzedExpression*(fncall: AnalyzedFunctionCall): AnalyzedExpression =
  AnalyzedExpression(kind: aekFunctionCall, fncall: fncall)

proc newAnalyzedExpression*(literal: Literal): AnalyzedExpression =
  AnalyzedExpression(kind: aekLiteral, literal: literal)

proc newAnalyzedExpression*(match: AnalyzedMatchExpression): AnalyzedExpression =
  AnalyzedExpression(kind: aekMatchExpr, match: match)

proc newAnalyzedExpression*(init: AnalyzedInitializer): AnalyzedExpression =
  AnalyzedExpression(kind: aekInitializer, init: init)

proc newAnalyzedExpression*(getter: AnalyzedGetter): AnalyzedExpression =
  AnalyzedExpression(kind: aekGetter, getter: getter)

proc kind*(expression: AnalyzedExpression): AnalyzedExpressionKind = expression.kind
proc variable*(expression: AnalyzedExpression): AnalyzedVariable =
  assert expression.kind == aekVariable,
    fmt"AnalyzedExpression.variable accessed but kind is {expression.kind}"
  expression.variable
proc fncall*(expression: AnalyzedExpression): AnalyzedFunctionCall =
  assert expression.kind == aekFunctionCall,
    fmt"AnalyzedExpression.fncall accessed but kind is {expression.kind}"
  expression.fncall
proc literal*(expression: AnalyzedExpression): Literal =
  assert expression.kind == aekLiteral,
    fmt"AnalyzedExpression.literal accessed but kind is {expression.kind}"
  expression.literal
proc match*(expression: AnalyzedExpression): AnalyzedMatchExpression =
  assert expression.kind == aekMatchExpr,
    fmt"AnalyzedExpression.match accessed but kind is {expression.kind}"
  expression.match
proc init*(expression: AnalyzedExpression): AnalyzedInitializer =
  assert expression.kind == aekInitializer,
    fmt"AnalyzedExpression.init accessed but kind is {expression.kind}"
  expression.init
proc getter*(expression: AnalyzedExpression): AnalyzedGetter =
  assert expression.kind == aekGetter,
    fmt"AnalyzedExpression.getter accessed but kind is {expression.kind}"
  expression.getter

proc loc*(expression: AnalyzedExpression): Location =
  case expression.kind:
  of aekFunctionCall: expression.fncall.loc
  of aekVariable: expression.variable.loc
  of aekLiteral: expression.literal.loc
  of aekGetter: expression.getter.loc
  of aekMatchExpr: expression.match.loc
  of aekInitializer: expression.init.loc

proc argType*(expression: AnalyzedExpression): Option[AnalyzedArgumentType] =
  case expression.kind:
  of aekLiteral: none(AnalyzedArgumentType)
  of aekFunctionCall: some(expression.fncall.returns)
  of aekVariable: some(expression.variable.argType)
  of aekMatchExpr: some(expression.match.returns)
  of aekInitializer: some(expression.init.argType)
  of aekGetter: some(expression.getter.argType)

proc newAnalyzedStatement*(expression: AnalyzedExpression): AnalyzedStatement =
  AnalyzedStatement(kind: askExpr, expression: expression)

proc newAnalyzedStatement*(assignment: AnalyzedAssignment): AnalyzedStatement =
  AnalyzedStatement(kind: askAssignment, assignment: assignment)

proc newAnalyzedStatement*(mutation: AnalyzedMutation): AnalyzedStatement =
  AnalyzedStatement(kind: askMutation, mutation: mutation)

proc kind*(statement: AnalyzedStatement): AnalyzedStatementKind = statement.kind
proc expression*(statement: AnalyzedStatement): AnalyzedExpression =
  assert statement.kind == askExpr,
    fmt"AnalyzedStatement.expression accessed but kind is {statement.kind}"
  statement.expression
proc assignment*(statement: AnalyzedStatement): AnalyzedAssignment =
  assert statement.kind == askAssignment,
    fmt"AnalyzedStatement.assignment accessed but kind is {statement.kind}"
  statement.assignment
proc mutation*(statement: AnalyzedStatement): AnalyzedMutation =
  assert statement.kind == askMutation,
    fmt"AnalyzedStatement.mutation accessed but kind is {statement.kind}"
  statement.mutation

proc loc*(statement: AnalyzedStatement): Location =
  case statement.kind:
  of askExpr: statement.expression.loc
  of askAssignment: statement.assignment.loc
  of askMutation: statement.mutation.loc

proc argType*(statement: AnalyzedStatement): Option[AnalyzedArgumentType] =
  case statement.kind:
  of askExpr: statement.expression.argType
  of askAssignment: statement.assignment.argType
  of askMutation: statement.mutation.argType

proc arg*(statement: AnalyzedStatement): Option[AnalyzedArgumentDefinition] =
  let maybeArgType = statement.argType
  if maybeArgType.isNone:
    assert(maybeArgType.isSome, fmt"{statement.loc} todo: support argType for statement")
  else:
    case statement.kind:
    of askExpr: return none(AnalyzedArgumentDefinition)
    of askMutation: return none(AnalyzedArgumentDefinition)
    of askAssignment: return some(newAnalyzedArgumentDefinition(maybeArgType.get, statement.assignment.target))

# Forward declarations for the analyzeX procs in the cluster.
proc analyzeExpression*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, expression: ResolvedExpression): Result[AnalyzedExpression, string]

proc analyzeStatement*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, statement: ResolvedStatement): Result[AnalyzedStatement, string]

proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, defScope: AnalyzedDefinedTypeScope, defType: AnalyzedArgumentType, valType: AnalyzedArgumentType, loc: Location): Result[GenericImplMap, string]

proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, defScope: AnalyzedDefinedTypeScope, defType: AnalyzedModuleArgumentType, valType: AnalyzedModuleArgumentType, loc: Location): Result[GenericImplMap, string] =
  if defType.module != valType.module:
    err(fmt"{loc} expected `{defType.name.asl}` but found `{valType.name.asl}`")
  else:
    var genericImplMap: GenericImplMap
    for (defImpl, valImpl) in zip(defType.impls, valType.impls):
      let valGenericImplMap = ? analyzeValueTypeAgainstDefinitionType(app, file, fileScope, defScope, defImpl, valImpl, loc)
      genericImplMap = ? genericImplMap.merge(valGenericImplMap)
    ok(genericImplMap)

proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, defScope: AnalyzedDefinedTypeScope, defType: AnalyzedModuleArgumentType, valType: AnalyzedDefinedArgumentType, loc: Location): Result[GenericImplMap, string] =
  case valType.kind:
  of adatkGeneric:
    err(fmt"{loc} expected a module {defType.asl} type but found generic type {valType.asl}")
  of adatkModule:
    analyzeValueTypeAgainstDefinitionType(app, file, fileScope, defScope, defType, valType.module, loc)

proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, defScope: AnalyzedDefinedTypeScope, defType: AnalyzedModuleArgumentType, valType: AnalyzedArgumentType, loc: Location): Result[GenericImplMap, string] =
  case valType.kind:
  of aatkImported:
    err(fmt"{loc} todo: analyze imported value type against module argument type")
  of aatkDefined:
    analyzeValueTypeAgainstDefinitionType(app, file, fileScope, defScope, defType, valType.definedType, loc)

proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, defScope: AnalyzedDefinedTypeScope, defType: AnalyzedGenericArgumentType, valType: AnalyzedArgumentType, loc: Location): Result[GenericImplMap, string] =
  let funcDefs = defType.resolved.concreteImpls(valType.self)
  for funcDef in funcDefs:
    case valType.kind:
    of aatkImported:
      return err(fmt"{loc} todo: analyze imported impl type")
    of aatkDefined:
      case valType.definedType.kind:
      of adatkGeneric:
        let maybeConcreteFuncDef = valType.definedType.generic.resolved.findFunctionDef(funcDef)
        if maybeConcreteFuncDef.isNone:
          return err(fmt"{loc} type `{valType.name.asl}` does not implement function `{funcDef.name.asl}` to support `{defType.resolved.name.asl}`")
      of adatkModule:
        let maybeConcreteFuncDef = valType.definedType.module.module.findFunctionDef(funcDef)
        if maybeConcreteFuncDef.isNone:
          return err(fmt"{loc} type `{valType.name.asl}` does not implement function `{funcDef.name.asl}` to support `{defType.resolved.name.asl}`")
  var genericImplMap: GenericImplMap
  genericImplMap[defType.resolved] = valType
  ok(genericImplMap)

proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, defScope: AnalyzedDefinedTypeScope, defType: AnalyzedDefinedArgumentType, valType: AnalyzedArgumentType, loc: Location): Result[GenericImplMap, string] =
  case defType.kind:
  of adatkModule: analyzeValueTypeAgainstDefinitionType(app, file, fileScope, defScope, defType.module, valType, loc)
  of adatkGeneric: analyzeValueTypeAgainstDefinitionType(app, file, fileScope, defScope, defType.generic, valType, loc)

# TODO: Return a map of generic -> argType from the recursive analysis
proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, defScope: AnalyzedDefinedTypeScope, defType: AnalyzedArgumentType, valType: AnalyzedArgumentType, loc: Location): Result[GenericImplMap, string] =
  case defType.kind:
  of aatkImported:
    err(fmt"{loc} todo: analyze value type against imported argument type")
  of aatkDefined:
    analyzeValueTypeAgainstDefinitionType(app, file, fileScope, defScope, defType.definedType, valType, loc)

proc analyzeArgumentList*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, argValues: seq[AnalyzedExpression], funcDef: AnalyzedFunctionDefinition): Result[GenericImplMap, string] =
  # BUG: `zip` below silently truncates to the shorter sequence — if
  # funcDef.args.len != argValues.len the type-check walks only the common
  # prefix and reports success. Today the resolver's arity check prevents
  # this from being reachable, but the defensive assert traps the mismatch
  # if overload selection is ever wired wrong upstream.
  assert(funcDef.args.len == argValues.len,
    fmt"BUG: analyzeArgumentList arity mismatch — funcDef has {funcDef.args.len} args, call site passed {argValues.len}. zip would silently truncate; fix by erroring (or relying on resolver / overload selection).")
  var genericImplMap: GenericImplMap
  for (argDef, argValue) in zip(funcDef.args, argValues):
    if argValue.argType.isNone:
      let argDefModule = ? defScope.findModuleDef(argDef.argType, argValue.loc)
      let argDefData = ? defScope.extractDataBlock(argDefModule, argValue.loc)
      case argDefData.kind:
      of adkStruct: return err(fmt"{argValue.loc} function call expects a struct initializer `{argDefModule.name.asl}`")
      of adkUnion: return err(fmt"{argValue.loc} function call expects a union initializer `{argDefModule.name.asl}`")
      of adkLiteral:
        let maybeValidLiteral = analyzeLiteral(argDefData.literal.resolved, argValue.literal)
        if maybeValidLiteral.isOk: return ok(genericImplMap)
        else: return err(maybeValidLiteral.error)
    else:
      let argGenericImplMap = ? analyzeValueTypeAgainstDefinitionType(app, file, fileScope, defScope, argDef.argType, argValue.argType.get, argValue.loc)
      genericImplMap = ? genericImplMap.merge(argGenericImplMap)
  ok(genericImplMap)

proc analyzeArgumentList(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, fncall: ResolvedFunctionCall, funcDefs: seq[AnalyzedFunctionDefinition], analyzedArgs: seq[AnalyzedExpression]): Result[(AnalyzedFunctionDefinition, GenericImplMap), string] =
  var matches: seq[(AnalyzedFunctionDefinition, GenericImplMap)]
  var errors: seq[string]
  for index, funcDef in funcDefs:
    let maybeGenericImplMap = analyzeArgumentList(app, file, fileScope, defScope, funcScope, analyzedArgs, funcDef)
    if maybeGenericImplMap.isOk:
      matches.add((funcDef, maybeGenericImplMap.get))
    else:
      errors.add(fmt"[{index + 1}] - " & maybeGenericImplMap.error)
      errors.add("\t" & fmt"{funcDef.loc}: {funcDef.asl}")

  if matches.len == 1:
    ok(matches[0])
  else:
    var message: seq[string]
    if matches.len == 0:
      message.add(fmt"{fncall.loc} failed to find matching function:")
    else:
      message.add(fmt"{fncall.loc} ambiguous function call — multiple candidates match:")
    message.add(errors)
    err(message.join("\n"))

proc analyzeFunctionCall*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, fncall: ResolvedFunctionCall): Result[AnalyzedFunctionCall, string] =
  let definedType = ? defScope.findType(fncall.parsed.root, fncall.loc)
  let public =
    case definedType.kind:
    of adtkModule: (moduleDef.resolved != definedType.module.resolved)
    of adtkGeneric: true # generic func defs are not required to be explicitly marked public
  let funcDefs = ? definedType.findFunctionDefs(fncall.parsed.name, fncall.parsed.args.len, public)

  var analyzedArgs: seq[AnalyzedExpression]
  for arg in fncall.args:
    let analyzedArg = ? analyzeExpression(app, file, fileScope, moduleDef, defScope, funcScope, arg)
    analyzedArgs.add(analyzedArg)

  let (matchingFuncDef, genericImpls) = ? analyzeArgumentList(app, file, fileScope, defScope, funcScope, fncall, funcDefs, analyzedArgs)
  # NOTE: compute concrete return type from the inferred implementation types
  let concreteReturns = matchingFuncDef.returns.concrete(genericImpls)
  ok(newAnalyzedFunctionCall(fncall, matchingFuncDef, analyzedArgs, concreteReturns))

proc analyzeCaseBlock*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, caseBlock: ResolvedCaseBlock, subjectType: AnalyzedArgumentType, union: AnalyzedUnion): Result[AnalyzedCaseBlock, string] =
  let analyzedCasePattern = ? analyzeCasePattern(app, file, fileScope, defScope, funcScope, caseBlock.pattern, subjectType, union)
  var caseScope = funcScope.clone()
  for binding in analyzedCasePattern.bindings:
    # echo fmt"SET {binding.name.asl} {binding.argType.asl}"
    caseScope[binding.name] = binding.argType
  var analyzedStatements: seq[AnalyzedStatement]
  for statement in caseBlock.statements:
    let analyzedStatement = ? analyzeStatement(app, file, fileScope, moduleDef, defScope, caseScope, statement)
    analyzedStatements.add(analyzedStatement)
    # echo moduleDef.loc, " ", analyzedStatement.argType.get.asl
    if analyzedStatement.arg.isSome:
      let newArg = analyzedStatement.arg.get
      # echo fmt"SET {newArg.name.asl} {newArg.argType.asl}"
      caseScope[newArg.name] = newArg.argType
  ok(newAnalyzedCaseBlock(caseBlock, analyzedCasePattern, analyzedStatements))

proc analyzeCaseBlock*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, caseBlock: ResolvedCaseBlock, subjectType: AnalyzedArgumentType): Result[AnalyzedCaseBlock, string] =
  let analyzedCasePattern = ? analyzeCasePattern(app, file, fileScope, defScope, funcScope, caseBlock.pattern, subjectType)
  var caseScope = funcScope.clone()
  for binding in analyzedCasePattern.bindings:
    # echo fmt"SET {binding.name.asl} {binding.argType.asl}"
    caseScope[binding.name] = binding.argType
  var analyzedStatements: seq[AnalyzedStatement]
  for statement in caseBlock.statements:
    let analyzedStatement = ? analyzeStatement(app, file, fileScope, moduleDef, defScope, caseScope, statement)
    analyzedStatements.add(analyzedStatement)
    # echo moduleDef.loc, " ", analyzedStatement.argType.get.asl
    if analyzedStatement.arg.isSome:
      let newArg = analyzedStatement.arg.get
      # echo fmt"SET {newArg.name.asl} {newArg.argType.asl}"
      caseScope[newArg.name] = newArg.argType
  ok(newAnalyzedCaseBlock(caseBlock, analyzedCasePattern, analyzedStatements))

proc verifyUniformReturnType(cases: seq[AnalyzedCaseBlock]): Result[void, string] =
  let expected = cases[0].argType
  if expected.isNone:
    return err(fmt"{cases[0].loc} todo: handle case block returning literal type")
  for c in cases:
    if c.argType.isNone:
      return err(fmt"{c.loc} todo: handle case block returning literal type")
    if c.argType.get != expected.get:
      return err(fmt"{c.loc} todo: return an error message telling that the case block return types are not same")
  ok()

proc analyzeCases*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, cases: seq[ResolvedCaseBlock], subjectType: AnalyzedArgumentType, union: AnalyzedUnion, loc: Location): Result[seq[AnalyzedCaseBlock], string] =
  var patternScope = newAnalyzedVariantPatternScope(cases.len)
  for id, caseBlock in cases:
    patternScope = ? patternScope.update(id, caseBlock.pattern)

  ? hasUncoveredCases(patternScope, union.variants.len, loc)

  assert(cases.len > 0, "UNREACHABLE: zero-case match should have been caught by the resolver")

  var analyzedCaseBlocks: seq[AnalyzedCaseBlock]
  for caseBlock in cases:
    let analyzedCaseBlock = ? analyzeCaseBlock(app, file, fileScope, moduleDef, defScope, funcScope, caseBlock, subjectType, union)
    analyzedCaseBlocks.add(analyzedCaseBlock)
    # echo analyzedCaseBlock.argType.get.asl
  ? verifyUniformReturnType(analyzedCaseBlocks)
  ok(analyzedCaseBlocks)

proc analyzeCases*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, cases: seq[ResolvedCaseBlock], subjectType: AnalyzedArgumentType, literal: AnalyzedLiteralBlock, loc: Location): Result[seq[AnalyzedCaseBlock], string] =
  var patternScope = ? newAnalyzedLiteralPatternScope(literal.resolved, cases.len)
  for id, caseBlock in cases:
    patternScope = ? patternScope.update(id, caseBlock.pattern)

  ? hasUncoveredCases(patternScope, loc)

  assert(cases.len > 0, "UNREACHABLE: zero-case match should have been caught by the resolver")

  var analyzedCaseBlocks: seq[AnalyzedCaseBlock]
  for caseBlock in cases:
    let analyzedCaseBlock = ? analyzeCaseBlock(app, file, fileScope, moduleDef, defScope, funcScope, caseBlock, subjectType)
    analyzedCaseBlocks.add(analyzedCaseBlock)
  ? verifyUniformReturnType(analyzedCaseBlocks)
  ok(analyzedCaseBlocks)

proc analyzeMatchExpression*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, match: ResolvedMatchExpression): Result[AnalyzedMatchExpression, string] =
  # echo match.loc
  let analyzedSubjectExpr = ? analyzeExpression(app, file, fileScope, moduleDef, defScope, funcScope, match.subject)
  if analyzedSubjectExpr.argType.isNone:
    err(fmt"{analyzedSubjectExpr.loc} todo: analyze case blocks for literal expression")
  else:
    let analyzedSubjectDataType = ? defScope.extractDataBlock(analyzedSubjectExpr.argType.get, analyzedSubjectExpr.loc)
    case analyzedSubjectDataType.kind:
    of adkStruct:
      let moduleName = analyzedSubjectExpr.argType.get.name
      err(fmt"{match.loc} match block only supports literal and union types but subject expression returns `{moduleName.asl}` a struct type")
    of adkLiteral:
      if match.cases.len == 0:
        err(fmt"{match.loc} UNREACHABLE: match block does not contain any case blocks")
      else:
        let analyzedCases = ? analyzeCases(app, file, fileScope, moduleDef, defScope, funcScope, match.cases, analyzedSubjectExpr.argType.get, analyzedSubjectDataType.literal, match.loc)
        ok(newAnalyzedMatchExpression(match, analyzedSubjectExpr, analyzedCases, analyzedCases[0].argType.get))
    of adkUnion:
      if match.cases.len == 0:
        err(fmt"{match.loc} UNREACHABLE: match block does not contain any case blocks")
      else:
        case analyzedSubjectExpr.argType.get.kind:
        of aatkImported:
          err(fmt"{match.loc} todo: handle analyzed imported type in match expression analysis for concrete union module")
        of aatkDefined:
          case analyzedSubjectExpr.argType.get.definedType.kind:
          of adatkGeneric:
            err(fmt"{match.loc} UNREACHABLE: match block does not support generic types in subject expression")
          of adatkModule:
            let impls = analyzedSubjectExpr.argType.get.definedType.module.impls
            let concreteUnion = analyzedSubjectDataType.union.concrete(impls)
            let analyzedCases = ? analyzeCases(app, file, fileScope, moduleDef, defScope, funcScope, match.cases, analyzedSubjectExpr.argType.get, concreteUnion, match.loc)
            ok(newAnalyzedMatchExpression(match, analyzedSubjectExpr, analyzedCases, analyzedCases[0].argType.get))

proc analyzeKeywordArgument*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, kwarg: ResolvedKeywordArgument, analyzedField: AnalyzedArgumentDefinition): Result[AnalyzedKeywordArgument, string] =
  let analyzedExpression = ? analyzeExpression(app, file, fileScope, moduleDef, defScope, funcScope, kwarg.expression)
  if analyzedExpression.argType.isNone:
    let fieldModule = ? defScope.findModuleDef(analyzedField.argType, kwarg.expression.loc)
    let fieldModuleData = ? defScope.extractDataBlock(fieldModule, kwarg.expression.loc)
    case fieldModuleData.kind:
    of adkStruct:
      err(fmt"{kwarg.expression.loc} field `{kwarg.name.asl}` expected a struct value but found literal")
    of adkUnion:
      err(fmt"{kwarg.expression.loc} field `{kwarg.name.asl}` expected a union value but found literal")
    of adkLiteral:
      let maybeAnalyzedLiteral = analyzeLiteral(fieldModuleData.literal.resolved, kwarg.expression.literal)
      if maybeAnalyzedLiteral.isErr: err(maybeAnalyzedLiteral.error)
      else: ok(newAnalyzedKeywordArgument(kwarg, analyzedField, analyzedExpression))
  else:
    # TODO: Utilize genericImplMap
    let genericImplMap = ? analyzeValueTypeAgainstDefinitionType(app, file, fileScope, defScope, analyzedField.argType, analyzedExpression.argType.get, analyzedExpression.loc)
    ok(newAnalyzedKeywordArgument(kwarg, analyzedField, analyzedExpression))

proc receiverArgType(receiver: AnalyzedModuleDefinition): AnalyzedArgumentType =
  ## Builds an AnalyzedArgumentType pointing at the receiver module with
  ## no impls. Used for default-kind struct initializers and union
  ## initializers (where impls live in the analyzer's deferred-inference
  ## thread, not at the call site).
  let resolvedSelfArg = receiver.resolved.self
  let analyzedModuleArg = newAnalyzedModuleArgumentType(resolvedSelfArg, receiver.resolved)
  newAnalyzedArgumentType(newAnalyzedDefinedArgumentType(analyzedModuleArg))

proc analyzeUnionRef(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, unionRef: ResolvedUnionRef): Result[AnalyzedUnionRef, string] =
  case unionRef.kind:
  of rurkDefault:
    let receiverDef = ? defScope.findModuleDef(unionRef.module.name, unionRef.loc)
    ok(newAnalyzedUnionRef(unionRef, receiverDef))
  of rurkImpl:
    let analyzedArgType = ? analyzeArgumentType(app, file, fileScope, moduleDef.resolved, unionRef.argType)
    ok(newAnalyzedUnionRef(unionRef, analyzedArgType))

proc analyzeUnionInitializer*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, init: ResolvedUnionInitializer): Result[AnalyzedUnionInitializer, string] =
  ## Dispatches on UnionRef kind. urkImpl substitutes the user-supplied
  ## impls into the variant's field types via concrete() and type-checks
  ## each kwarg against the substituted type — no inference. urkDefault
  ## walks the kwargs, accumulates a GenericImplMap from value-vs-field
  ## type matches, and builds the result type with bound concretes at
  ## positions the variant touched + free generics at uncovered positions
  ## (leave-as-is — unification at downstream use sites fills the rest).
  let analyzedUnionRef = ? analyzeUnionRef(app, file, fileScope, moduleDef, defScope, init.unionRef)
  let receiver =
    case analyzedUnionRef.kind:
    of aurkDefault: analyzedUnionRef.module
    of aurkImpl: ? defScope.findModuleDef(init.module.name, init.loc)
  if receiver.data.isNone:
    return err(fmt"{init.loc} module `{receiver.name.asl}` is not a union")
  let dataBlock = receiver.data.get
  case dataBlock.kind:
  of adkLiteral: return err(fmt"{init.loc} module `{receiver.name.asl}` is a literal")
  of adkStruct: return err(fmt"{init.loc} module `{receiver.name.asl}` is a struct")
  of adkUnion: discard
  let analyzedUnion = dataBlock.union
  let analyzedVariant = ? analyzedUnion.findVariant(init.variant)

  # Seed implMap from explicit impls (urkImpl path) so substitution
  # works without inference. urkDefault leaves the map empty and
  # accumulates from each kwarg below.
  var implMap: GenericImplMap
  case analyzedUnionRef.kind:
  of aurkImpl:
    case analyzedUnionRef.argType.kind:
    of aatkImported:
      return err(fmt"{analyzedUnionRef.loc} todo: explicit-impl union initializer with imported receiver type")
    of aatkDefined:
      case analyzedUnionRef.argType.definedType.kind:
      of adatkGeneric:
        return err(fmt"{analyzedUnionRef.loc} union receiver `{analyzedUnionRef.resolved.module.name.asl}` cannot be a generic")
      of adatkModule:
        let explicitImpls = analyzedUnionRef.argType.definedType.module.impls
        for genericArgType, position in analyzedUnion.genericTypeIndex:
          implMap[genericArgType.resolved] = explicitImpls[position]
  of aurkDefault: discard

  # Walk kwargs. Substitute the variant's field type via implMap before
  # type-checking — equivalent to direct match on urkDefault (implMap
  # is empty there), full concretization on urkImpl. Accumulate bindings
  # into implMap only on the urkDefault path.
  var analyzedKwargs: seq[AnalyzedKeywordArgument]
  for kwarg in init.kwargs:
    let analyzedField: AnalyzedArgumentDefinition = ? analyzedVariant.findField(kwarg.name)
    let analyzedExpression = ? analyzeExpression(app, file, fileScope, moduleDef, defScope, funcScope, kwarg.expression)
    if analyzedExpression.argType.isNone:
      return err(fmt"{kwarg.expression.loc} todo: literal-typed kwarg in union initializer")
    let fieldType = analyzedField.argType.concrete(implMap)
    let local = ? analyzeValueTypeAgainstDefinitionType(app, file, fileScope, defScope, fieldType, analyzedExpression.argType.get, analyzedExpression.loc)
    case analyzedUnionRef.kind:
    of aurkImpl: discard
    of aurkDefault: implMap = ? implMap.merge(local)
    analyzedKwargs.add(newAnalyzedKeywordArgument(kwarg, analyzedField, analyzedExpression))

  # Build the result type. urkImpl already carries the fully-bound
  # argType from the user. urkDefault fills impls positionally from
  # the accumulated implMap, leaving uncovered positions as free
  # generics (the leave-as-is shape).
  let argType =
    case analyzedUnionRef.kind:
    of aurkImpl: analyzedUnionRef.argType
    of aurkDefault:
      var impls = newSeq[AnalyzedArgumentType](analyzedUnion.genericTypeIndex.len)
      for genericArgType, position in analyzedUnion.genericTypeIndex:
        if genericArgType.resolved in implMap:
          impls[position] = implMap[genericArgType.resolved]
        else:
          impls[position] = newAnalyzedArgumentType(newAnalyzedDefinedArgumentType(genericArgType))
      let resolvedSelfArg = receiver.resolved.self
      let analyzedModuleArg = newAnalyzedModuleArgumentType(resolvedSelfArg, receiver.resolved, impls)
      newAnalyzedArgumentType(newAnalyzedDefinedArgumentType(analyzedModuleArg))

  ok(newAnalyzedUnionInitializer(init, analyzedUnionRef, argType, analyzedVariant, analyzedKwargs))

proc analyzeStructRef(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, structRef: ResolvedStructRef): Result[AnalyzedStructRef, string] =
  case structRef.kind:
  of rsrkDefault:
    let receiverDef = ? defScope.findModuleDef(structRef.module.name, structRef.loc)
    ok(newAnalyzedStructRef(structRef, receiverDef))
  of rsrkImpl:
    let analyzedArgType = ? analyzeArgumentType(app, file, fileScope, moduleDef.resolved, structRef.argType)
    ok(newAnalyzedStructRef(structRef, analyzedArgType))

proc analyzeStructInitializer*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, init: ResolvedStructInitializer): Result[AnalyzedStructInitializer, string] =
  let analyzedStructRef = ? analyzeStructRef(app, file, fileScope, moduleDef, defScope, init.structRef)
  let receiver =
    case analyzedStructRef.kind:
    of asrkDefault: analyzedStructRef.module
    of asrkImpl: ? defScope.findModuleDef(init.structRef.module.name, init.loc)
  if receiver.data.isNone:
    return err(fmt"{init.loc} module `{receiver.name.asl}` is not a struct")
  let dataBlock = receiver.data.get
  case dataBlock.kind:
  of adkLiteral: err(fmt"{init.loc} module `{receiver.name.asl}` is a literal")
  of adkUnion: err(fmt"{init.loc} module `{receiver.name.asl}` is a union")
  of adkStruct:
    var analyzedKwargs: seq[AnalyzedKeywordArgument]
    for kwarg in init.kwargs:
      let analyzedField = ? dataBlock.struct.findField(kwarg.name)
      let analyzedKwarg = ? analyzeKeywordArgument(app, file, fileScope, moduleDef, defScope, funcScope, kwarg, analyzedField)
      analyzedKwargs.add(analyzedKwarg)
    let argType =
      case analyzedStructRef.kind:
      of asrkImpl: analyzedStructRef.argType
      of asrkDefault:
        # TODO: In case the fully qualified impls are not provided in struct initializer we need to infer the generic types ourselves
        receiverArgType(receiver)
    ok(newAnalyzedStructInitializer(init, analyzedStructRef, argType, analyzedKwargs))

proc analyzeInitializer*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, init: ResolvedInitializer): Result[AnalyzedInitializer, string] =
  case init.kind:
  of rikLiteral:
    let analyzedLiteralInit = ? analyzeLiteralInitializer(app, file, fileScope, moduleDef, defScope, funcScope, init.literal)
    ok(newAnalyzedInitializer(analyzedLiteralInit))
  of rikStruct:
    let analyzedStructInit = ? analyzeStructInitializer(app, file, fileScope, moduleDef, defScope, funcScope, init.struct)
    ok(newAnalyzedInitializer(analyzedStructInit))
  of rikUnion:
    let analyzedUnionInit = ? analyzeUnionInitializer(app, file, fileScope, moduleDef, defScope, funcScope, init.union)
    ok(newAnalyzedInitializer(analyzedUnionInit))

proc analyzeExpression*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, expression: ResolvedExpression): Result[AnalyzedExpression, string] =
  case expression.kind:
  of rekLiteral: ok(newAnalyzedExpression(expression.literal))
  of rekVariable:
    let analyzedVariable = ? analyzeVariable(funcScope, expression.variable)
    ok(newAnalyzedExpression(analyzedVariable))
  of rekGetter:
    let analyzedGetter = ? analyzeGetter(app, file, fileScope, defScope, funcScope, expression.getter)
    ok(newAnalyzedExpression(analyzedGetter))
  of rekInitializer:
    let analyzedInit = ? analyzeInitializer(app, file, fileScope, moduleDef, defScope, funcScope, expression.init)
    ok(newAnalyzedExpression(analyzedInit))
  of rekFunctionCall:
    let analyzedFunctionCall = ? analyzeFunctionCall(app, file, fileScope, moduleDef, defScope, funcScope, expression.fncall)
    ok(newAnalyzedExpression(analyzedFunctionCall))
  of rekMatchExpr:
    let analyzedMatchExpr = ? analyzeMatchExpression(app, file, fileScope, moduleDef, defScope, funcScope, expression.match)
    ok(newAnalyzedExpression(analyzedMatchExpr))

proc analyzeAssignment*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, assignment: ResolvedAssignment): Result[AnalyzedAssignment, string] =
  let analyzedExpr = ? analyzeExpression(app, file, fileScope, moduleDef, defScope, funcScope, assignment.expression)
  ok(newAnalyzedAssignment(assignment, analyzedExpr))

proc analyzeMutation*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, mutation: ResolvedSetter): Result[AnalyzedMutation, string] =
  let analyzedGetter = ? analyzeGetter(app, file, fileScope, defScope, funcScope, mutation.getter)
  let analyzedExpression = ? analyzeExpression(app, file, fileScope, moduleDef, defScope, funcScope, mutation.expression)
  # TODO: Ensure that the getter field type and the expression type are same
  ok(newAnalyzedMutation(mutation, analyzedGetter, analyzedExpression))

proc analyzeStatement*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, statement: ResolvedStatement): Result[AnalyzedStatement, string] =
  case statement.kind:
  of rskExpr:
    let analyzedExpr = ? analyzeExpression(app, file, fileScope, moduleDef, defScope, funcScope, statement.expression)
    ok(newAnalyzedStatement(analyzedExpr))
  of rskAssignment:
    let analyzedAssignment = ? analyzeAssignment(app, file, fileScope, moduleDef, defScope, funcScope, statement.assignment)
    ok(newAnalyzedStatement(analyzedAssignment))
  of rskMutation:
    let analyzedMutation = ? analyzeMutation(app, file, fileScope, moduleDef, defScope, funcScope, statement.mutation)
    ok(newAnalyzedStatement(analyzedMutation))


type AnalyzedUserFunction* = ref object
  resolved: ResolvedUserFunction
  def: AnalyzedFunctionDefinition
  statements: seq[AnalyzedStatement]

proc newAnalyzedUserFunction*(resolved: ResolvedUserFunction, def: AnalyzedFunctionDefinition, statements: seq[AnalyzedStatement]): AnalyzedUserFunction =
  AnalyzedUserFunction(resolved: resolved, def: def, statements: statements)

proc resolved*(function: AnalyzedUserFunction): ResolvedUserFunction = function.resolved
proc def*(function: AnalyzedUserFunction): AnalyzedFunctionDefinition = function.def
proc statements*(function: AnalyzedUserFunction): seq[AnalyzedStatement] = function.statements

proc analyzeUserFunction*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, function: ResolvedUserFunction): Result[AnalyzedUserFunction, string] =
  var funcScope: AnalyzedFunctionScope
  let analyzedFuncDef = ? moduleDef.findFunctionDef(function.def)
  for argDef in analyzedFuncDef.args:
    funcScope[argDef.name] = argDef.argType

  var analyzedStatements: seq[AnalyzedStatement]
  for statement in function.statements:
    let analyzedStatement = ? analyzeStatement(app, file, fileScope, moduleDef, defScope, funcScope, statement)
    analyzedStatements.add(analyzedStatement)
    if analyzedStatement.arg.isSome:
      let newArg = analyzedStatement.arg.get
      funcScope[newArg.name] = newArg.argType

  #TODO: ensure that last statement always returns a type that matches with the function defintion's return type
  if function.statements.len == 0:
    err(fmt"{function.loc} UNREACHABLE: should have been caught by the resolver")
  else:
    if analyzedStatements[^1].argType.isNone:
      err(fmt"{function.loc} todo: analyze function that returns a literal")
    else:
      if analyzedStatements[^1].argType.get != analyzedFuncDef.returns:
        err(fmt"{function.statements[^1].loc} function does not return the expected return type")
      else:
        ok(newAnalyzedUserFunction(function, analyzedFuncDef, analyzedStatements))

type AnalyzedExternFunction* = ref object
  resolved: ResolvedExternFunction
  def: AnalyzedFunctionDefinition

proc newAnalyzedExternFunction*(resolved: ResolvedExternFunction, def: AnalyzedFunctionDefinition): AnalyzedExternFunction =
  AnalyzedExternFunction(resolved: resolved, def: def)

proc resolved*(function: AnalyzedExternFunction): ResolvedExternFunction = function.resolved
proc def*(function: AnalyzedExternFunction): AnalyzedFunctionDefinition = function.def

type
  AnalyzedFunctionKind* = enum
    afkUser, afkExtern
  AnalyzedFunction* = ref object
    case kind: AnalyzedFunctionKind
    of afkUser: user: AnalyzedUserFunction
    of afkExtern: extern: AnalyzedExternFunction

proc newAnalyzedFunction*(user: AnalyzedUserFunction): AnalyzedFunction =
  AnalyzedFunction(kind: afkUser, user: user)

proc newAnalyzedFunction*(extern: AnalyzedExternFunction): AnalyzedFunction =
  AnalyzedFunction(kind: afkExtern, extern: extern)

proc kind*(function: AnalyzedFunction): AnalyzedFunctionKind = function.kind
proc user*(function: AnalyzedFunction): AnalyzedUserFunction =
  assert function.kind == afkUser,
    fmt"AnalyzedFunction.user accessed but kind is {function.kind}"
  function.user
proc extern*(function: AnalyzedFunction): AnalyzedExternFunction =
  assert function.kind == afkExtern,
    fmt"AnalyzedFunction.extern accessed but kind is {function.kind}"
  function.extern

type AnalyzedModule* = ref object
  def: AnalyzedModuleDefinition
  functions: seq[AnalyzedFunction]

proc newAnalyzedModule*(def: AnalyzedModuleDefinition, functions: seq[AnalyzedFunction]): AnalyzedModule =
  AnalyzedModule(def: def, functions: functions)

proc def*(m: AnalyzedModule): AnalyzedModuleDefinition = m.def
proc resolved*(m: AnalyzedModule): ResolvedModule = m.def.resolved
proc loc*(m: AnalyzedModule): Location = m.def.resolved.loc
proc name*(m: AnalyzedModule): Identifier = m.def.name
proc functions*(m: AnalyzedModule): seq[AnalyzedFunction] = m.functions

proc analyzeModule*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope): Result[AnalyzedModule, string] =
  var analyzedFunctions: seq[AnalyzedFunction]
  for function in moduleDef.resolved.functions:
    case function.kind:
    of rfkExtern:
      let analyzedFuncDef = ? moduleDef.findFunctionDef(function.def)
      analyzedFunctions.add(newAnalyzedFunction(newAnalyzedExternFunction(function.extern, analyzedFuncDef)))
    of rfkUser:
      let analyzedUserFunction = ? analyzeUserFunction(app, file, fileScope, moduleDef, defScope, function.user)
      analyzedFunctions.add(newAnalyzedFunction(analyzedUserFunction))
  ok(newAnalyzedModule(moduleDef, analyzedFunctions))

type AnalyzedFile = ref object
  def: AnalyzedFileDefinition
  modules: seq[AnalyzedModule]

proc newAnalyzedFile(def: AnalyzedFileDefinition, modules: seq[AnalyzedModule]): AnalyzedFile =
  AnalyzedFile(def: def, modules: modules)

proc analyzeFile(appDef: AnalyzedAppDefinition, fileDef: AnalyzedFileDefinition): Result[AnalyzedFile, string] =
  var defScope = fileDef.definedTypeIndex
  # TODO: Insert imported types in the definition scope
  for imp in fileDef.imports:
    let impFileDef = ? appDef.findFileDef(imp.path)
    for impType in imp.importedTypes:
      defScope[impType.binding] = ? impFileDef.findType(impType.definedType.name)

  var analyzedModules: seq[AnalyzedModule]
  for definedType in fileDef.types:
    case definedType.kind:
    of adtkGeneric: discard # generics are already resolved since it is only a definition type
    of adtkModule:
      let analyzedModule = ? analyzeModule(appDef.resolved, fileDef.resolved, fileDef.scope, definedType.module, defScope)
      analyzedModules.add(analyzedModule)
  ok(newAnalyzedFile(fileDef, analyzedModules))

type AnalyzedApp = ref object
  def: AnalyzedAppDefinition
  files: seq[AnalyzedFile]

proc newAnalyzedApp(def: AnalyzedAppDefinition, files: seq[AnalyzedFile]): AnalyzedApp =
  AnalyzedApp(def: def, files: files)

proc analyze*(app: ResolvedApp): Result[AnalyzedApp, string] =
  let analyzedAppDef = ? app.analyzeAppDefinition()
  var analyzedFiles: seq[AnalyzedFile]
  for fileDef in analyzedAppDef.fileDefs:
    let analyzedFile = ? analyzedAppDef.analyzeFile(fileDef)
    analyzedFiles.add(analyzedFile)
  ok(newAnalyzedApp(analyzedAppDef, analyzedFiles))