## Argument-type cluster — the resolved counterpart to parser
## `ArgumentType`, mutually recursive with its module-variant carrier.
##
## `ResolvedModuleArgumentType`, `ResolvedGenericArgumentType`, and the
## outer `ResolvedArgumentType` tagged union all live in this single
## file because Nim requires mutually-referencing `ref object` types to
## share one `type` block. The tiny `moduleargtype.nim` /
## `genericargtype.nim` files re-export this module so downstream
## callers that only need one variant can import it by name.

import results, strformat, strutils, hashes, tables

import ./parser
import ./typecontext

type
  ResolvedGenericArgumentType* = ref object
    generic: Generic
    loc: Location

  ResolvedModuleArgumentType* = ref object
    module: Module
    impls: seq[ResolvedArgumentType]
    loc: Location

  ResolvedArgumentTypeKind* = enum
    ratkModule, ratkGeneric

  ResolvedArgumentType* = ref object
    case kind: ResolvedArgumentTypeKind
    of ratkModule: module: ResolvedModuleArgumentType
    of ratkGeneric: generic: ResolvedGenericArgumentType

  # Substitution map for generic grounding — the resolver-side, map-based
  # counterpart to the analyzer's `GenericImplMap` + `concrete`. In
  # practice it carries a single entry (a generic block has one type
  # parameter, so constraint grounding substitutes that one generic),
  # but the map shape keeps both layers' `concrete` engines aligned.
  GenericSubst* = Table[Generic, ResolvedArgumentType]

# ---- forward declarations (case-union recursion) ----

proc newResolvedArgumentType*(module: ResolvedModuleArgumentType): ResolvedArgumentType
proc newResolvedArgumentType*(generic: ResolvedGenericArgumentType): ResolvedArgumentType
proc concrete*(argType: ResolvedArgumentType, subst: GenericSubst): ResolvedArgumentType
proc hash*(argType: ResolvedArgumentType): Hash
proc asl*(argType: ResolvedArgumentType): string

# =====================================================================

# ---- ResolvedGenericArgumentType ----

proc newResolvedGenericArgumentType*(generic: Generic, loc: Location): ResolvedGenericArgumentType =
  ResolvedGenericArgumentType(generic: generic, loc: loc)

proc generic*(argType: ResolvedGenericArgumentType): Generic = argType.generic
proc name*(argType: ResolvedGenericArgumentType): Identifier = argType.generic.name
proc loc*(argType: ResolvedGenericArgumentType): Location = argType.loc
proc hash*(argType: ResolvedGenericArgumentType): Hash = argType.generic.hash
proc `==`*(a, b: ResolvedGenericArgumentType): bool = a.hash == b.hash
proc asl*(argType: ResolvedGenericArgumentType): string = argType.generic.name.asl

proc satisfies*(argType: ResolvedGenericArgumentType, base: Generic): Result[void, string] =
  for def in base.defs:
    let maybeFuncDefs = argType.generic.findFunctionDefs(def.name, def.arity)
    if maybeFuncDefs.isErr: return err(fmt"{argType.loc} generic `{argType.name.asl}` does not implement function `{def.name.asl}` to support `{base.name.asl}`")
  ok()

proc concrete*(argType: ResolvedGenericArgumentType, subst: GenericSubst): ResolvedArgumentType =
  subst.getOrDefault(argType.generic, newResolvedArgumentType(argType))

# ---- ResolvedModuleArgumentType ----

proc newResolvedModuleArgumentType*(module: Module, impls: seq[ResolvedArgumentType], loc: Location): ResolvedModuleArgumentType =
  ResolvedModuleArgumentType(loc: loc, module: module, impls: impls)

proc newResolvedModuleArgumentType*(module: Module, loc: Location): ResolvedModuleArgumentType =
  newResolvedModuleArgumentType(module, @[], loc)

proc loc*(argType: ResolvedModuleArgumentType): Location = argType.loc
proc module*(argType: ResolvedModuleArgumentType): Module = argType.module
proc impls*(argType: ResolvedModuleArgumentType): seq[ResolvedArgumentType] = argType.impls
proc parsed*(argType: ResolvedModuleArgumentType): Module = argType.module
  ## The parser Module that this argument type refers to. Consumers who
  ## need the ResolvedModule look it up at their site via
  ## `ResolvedFile.findModule(module.name)`.
proc name*(argType: ResolvedModuleArgumentType): Identifier = argType.module.name

proc hash*(argType: ResolvedModuleArgumentType): Hash =
  # Hash by parser Module identity.
  var acc = argType.module.hash
  for impl in argType.impls:
    acc = acc !& impl.hash
  return acc
proc `==`*(a, b: ResolvedModuleArgumentType): bool = a.hash == b.hash

proc asl*(argType: ResolvedModuleArgumentType): string =
  if argType.impls.len == 0:
    fmt"{argType.parsed.name.asl}"
  else:
    var impls: seq[string]
    for impl in argType.impls:
      impls.add(impl.asl)
    let implsJoined = impls.join(", ")
    fmt"{argType.parsed.name.asl}[{implsJoined}]"

proc satisfies*(argType: ResolvedModuleArgumentType, base: Generic, typeCtx: TypeContext): Result[void, string] =
  ## A private function only counts as implementing `base` when the
  ## lookup context is the impl module itself (`faAll`) — everywhere
  ## else the constraint demands a public function.
  let access = typeCtx.access(argType.module)
  for def in base.defs:
    let maybeFuncDefs = argType.module.findFunctionDefs(def.name, def.arity, access)
    if maybeFuncDefs.isErr: return err(fmt"{argType.loc} module `{argType.name.asl}` does not implement function `{def.name.asl}` to support `{base.name.asl}`")
  ok()

proc concrete*(argType: ResolvedModuleArgumentType, subst: GenericSubst): ResolvedArgumentType =
  var impls: seq[ResolvedArgumentType]
  for impl in argType.impls:
    impls.add(impl.concrete(subst))
  let moduleArgType = newResolvedModuleArgumentType(argType.module, impls, argType.loc)
  newResolvedArgumentType(moduleArgType)

# ---- ResolvedArgumentType (outer tagged union) ----

proc newResolvedArgumentType*(module: ResolvedModuleArgumentType): ResolvedArgumentType =
  ResolvedArgumentType(kind: ratkModule, module: module)

proc newResolvedArgumentType*(generic: ResolvedGenericArgumentType): ResolvedArgumentType =
  ResolvedArgumentType(kind: ratkGeneric, generic: generic)

proc kind*(argType: ResolvedArgumentType): ResolvedArgumentTypeKind = argType.kind

proc module*(argType: ResolvedArgumentType): ResolvedModuleArgumentType =
  assert argType.kind == ratkModule,
    fmt"ResolvedArgumentType.module accessed but kind is {argType.kind}"
  argType.module

proc generic*(argType: ResolvedArgumentType): ResolvedGenericArgumentType =
  assert argType.kind == ratkGeneric,
    fmt"ResolvedArgumentType.generic accessed but kind is {argType.kind}"
  argType.generic

proc name*(argType: ResolvedArgumentType): Identifier =
  case argType.kind:
  of ratkModule: argType.module.parsed.name
  of ratkGeneric: argType.generic.name

proc loc*(argType: ResolvedArgumentType): Location =
  case argType.kind:
  of ratkModule: argType.module.loc
  of ratkGeneric: argType.generic.loc

proc hash*(argType: ResolvedArgumentType): Hash =
  case argType.kind:
  of ratkModule: argType.module.hash
  of ratkGeneric: argType.generic.hash

proc `==`*(a, b: ResolvedArgumentType): bool = a.hash == b.hash

proc asl*(argType: ResolvedArgumentType): string =
  case argType.kind:
  of ratkModule: argType.module.asl
  of ratkGeneric: argType.generic.asl

proc concrete*(argType: ResolvedArgumentType, subst: GenericSubst): ResolvedArgumentType =
  ## Recursive generic substitution — rewrites any generic bound by
  ## `subst` at any depth of the impl tree (`Array[Eq]` under {Eq: u8}
  ## becomes `Array[u8]`); unbound generics stay as-is. Map-based, so it
  ## mirrors the analyzer's `concrete(argType, implMap)`.
  case argType.kind:
  of ratkGeneric: argType.generic.concrete(subst)
  of ratkModule: argType.module.concrete(subst)

proc satisfies*(argType: ResolvedArgumentType, base: Generic, typeCtx: TypeContext): Result[void, string] =
  case argType.kind:
  of ratkModule: argType.module.satisfies(base, typeCtx)
  of ratkGeneric: argType.generic.satisfies(base)
