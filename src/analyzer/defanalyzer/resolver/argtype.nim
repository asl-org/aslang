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

# ---- forward declarations (case-union recursion) ----

proc newResolvedArgumentType*(module: ResolvedModuleArgumentType): ResolvedArgumentType
proc newResolvedArgumentType*(generic: ResolvedGenericArgumentType): ResolvedArgumentType
proc substitute*(argType: ResolvedArgumentType, bindings: Table[Generic, ResolvedArgumentType]): ResolvedArgumentType
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

proc substitute*(argType: ResolvedGenericArgumentType, bindings: Table[Generic, ResolvedArgumentType]): ResolvedArgumentType =
  if argType.generic notin bindings: newResolvedArgumentType(argType)
  else: bindings[argType.generic]

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

proc substitute*(argType: ResolvedModuleArgumentType, bindings: Table[Generic, ResolvedArgumentType]): ResolvedArgumentType =
  var impls: seq[ResolvedArgumentType]
  for impl in argType.impls:
    impls.add(impl.substitute(bindings))
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

proc concreteArgumentType*(argType: ResolvedArgumentType, concrete: ResolvedArgumentType, generic: Generic): ResolvedArgumentType =
  case argType.kind:
  of ratkModule: argType
  of ratkGeneric:
    if argType.generic.generic != generic: argType
    else: concrete

proc satisfies*(argType: ResolvedArgumentType, base: Generic, typeCtx: TypeContext): Result[void, string] =
  case argType.kind:
  of ratkModule: argType.module.satisfies(base, typeCtx)
  of ratkGeneric: argType.generic.satisfies(base)

proc substitute*(argType: ResolvedArgumentType, bindings: Table[Generic, ResolvedArgumentType]): ResolvedArgumentType =
  ## Recursive generic substitution — unlike `concreteArgumentType`
  ## (single generic, top level only) this rewrites bound generics at
  ## any depth of the impl tree (`Array[Eq]` under {Eq → u8} becomes
  ## `Array[u8]`). Unbound generics stay as-is.
  case argType.kind:
  of ratkGeneric: argType.generic.substitute(bindings)
  of ratkModule: argType.module.substitute(bindings)

type SignatureParity* = enum
  ## Verdict of the four-case argument-type matching relation
  ## (`argTypeMatches` on the defanalyzer barrel, which owns the
  ## scope lookups the recursion needs):
  ##   module   vs module   — identity (loc-based hash equality);
  ##   module   vs generic  — never matches (the expected side is
  ##                          already concrete, kinds cannot
  ##                          reconcile);
  ##   generic  vs module   — the expected generic is a CONTRACT: the
  ##   generic  vs generic    actual type must provide every funcDef
  ##                          the generic mandates, with the generic
  ##                          substituted by the actual's fully
  ##                          qualified type (recursively).
  spEqual, spUnequal