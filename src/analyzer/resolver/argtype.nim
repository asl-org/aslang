## Argument-type cluster — the resolved counterpart to parser
## `ArgumentType`, mutually recursive with its module-variant carrier.
##
## `ResolvedModuleArgumentType`, `ResolvedGenericArgumentType`, and the
## outer `ResolvedArgumentType` tagged union all live in this single
## file because Nim requires mutually-referencing `ref object` types to
## share one `type` block. The tiny `moduleargtype.nim` /
## `genericargtype.nim` files re-export this module so downstream
## callers that only need one variant can import it by name.

import results, strformat, strutils, hashes

import ./parser

type
  ResolvedModuleArgumentType* = ref object
    module: Module
    impls: seq[ResolvedArgumentType]
    loc: Location

  ResolvedGenericArgumentType* = ref object
    generic: Generic
    loc: Location

  ResolvedArgumentTypeKind* = enum
    ratkModule, ratkGeneric

  ResolvedArgumentType* = ref object
    case kind: ResolvedArgumentTypeKind
    of ratkModule: module: ResolvedModuleArgumentType
    of ratkGeneric: generic: ResolvedGenericArgumentType

# ---- forward declarations (case-union recursion) ----

proc hash*(argType: ResolvedArgumentType): Hash
proc asl*(argType: ResolvedArgumentType): string

# =====================================================================

# ---- ResolvedGenericArgumentType ----

proc newResolvedGenericArgumentType*(generic: Generic, loc: Location): ResolvedGenericArgumentType =
  ResolvedGenericArgumentType(generic: generic, loc: loc)

proc parsed*(argType: ResolvedGenericArgumentType): Generic = argType.generic
proc name*(argType: ResolvedGenericArgumentType): Identifier = argType.generic.name
proc loc*(argType: ResolvedGenericArgumentType): Location = argType.loc
proc hash*(argType: ResolvedGenericArgumentType): Hash = argType.generic.hash
proc `==`*(a, b: ResolvedGenericArgumentType): bool = a.hash == b.hash
proc asl*(argType: ResolvedGenericArgumentType): string = argType.generic.name.asl

proc satisfies*(argType: ResolvedGenericArgumentType, base: Generic): Result[void, string] =
  for funcDef in base.funcDefs:
    let maybeFuncDefs = argType.parsed.findFunctionDefs(funcDef.name, funcDef.arity)
    if maybeFuncDefs.isErr: return err(fmt"{argType.loc} generic `{argType.name.asl}` does not implement function `{funcDef.name.asl}` to support `{base.name.asl}`")
  ok()

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

proc satisfies*(argType: ResolvedModuleArgumentType, base: Generic): Result[void, string] =
  for funcDef in base.funcDefs:
    let maybeFuncDefs = argType.module.findFunctionDefs(funcDef.name, funcDef.arity)
    if maybeFuncDefs.isErr: return err(fmt"{argType.loc} module `{argType.name.asl}` does not implement function `{funcDef.name.asl}` to support `{base.name.asl}`")
  ok()

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
    if argType.generic.parsed != generic:
      argType
    else:
      concrete

proc satisfies*(argType: ResolvedArgumentType, base: Generic): Result[void, string] =
  case argType.kind:
  of ratkModule: argType.module.satisfies(base)
  of ratkGeneric: argType.generic.satisfies(base)