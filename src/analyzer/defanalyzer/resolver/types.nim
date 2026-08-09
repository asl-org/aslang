## ResolvedLocalType — file-scope umbrella over ResolvedModule +
## ResolvedGeneric. Tagged-union pair: the Kind enum and the type live
## in the same file per convention.

import hashes, strformat

import parser
import module
import generic

type
  ResolvedLocalTypeKind* = enum
    rltkModule, rltkGeneric
  ResolvedLocalType* = ref object
    case kind: ResolvedLocalTypeKind
    of rltkModule: module: ResolvedModule
    of rltkGeneric: generic: ResolvedGeneric

proc newResolvedLocalType*(module: ResolvedModule): ResolvedLocalType =
  ResolvedLocalType(kind: rltkModule, module: module)

proc newResolvedLocalType*(generic: ResolvedGeneric): ResolvedLocalType =
  ResolvedLocalType(kind: rltkGeneric, generic: generic)

proc kind*(typ: ResolvedLocalType): ResolvedLocalTypeKind = typ.kind
proc module*(typ: ResolvedLocalType): ResolvedModule =
  assert typ.kind == rltkModule,
    fmt"ResolvedLocalType.module accessed but kind is {typ.kind}"
  typ.module
proc generic*(typ: ResolvedLocalType): ResolvedGeneric =
  assert typ.kind == rltkGeneric,
    fmt"ResolvedLocalType.generic accessed but kind is {typ.kind}"
  typ.generic

proc name*(typ: ResolvedLocalType): Identifier =
  case typ.kind:
  of rltkModule: typ.module.name
  of rltkGeneric: typ.generic.name

proc loc*(typ: ResolvedLocalType): Location =
  case typ.kind:
  of rltkModule: typ.module.loc
  of rltkGeneric: typ.generic.loc

proc parsed*(typ: ResolvedLocalType): parser.LocalType =
  ## Underlying parser LocalType for identity-keyed scope lookups. See
  ## plans/plan_identity_based_lookups.md — scope tables downstream
  ## of name resolution key on `parser.LocalType` (hash-by-loc), not on
  ## `Identifier` (hash-by-string).
  case typ.kind:
  of rltkModule: newLocalType(typ.module.parsed)
  of rltkGeneric: newLocalType(typ.generic.parsed)

proc hash*(typ: ResolvedLocalType): Hash =
  case typ.kind:
  of rltkModule: typ.module.hash
  of rltkGeneric: typ.generic.hash

proc `==`*(a, b: ResolvedLocalType): bool =
  if a.kind != b.kind: false
  else:
    case a.kind:
    of rltkModule: a.module == b.module
    of rltkGeneric: a.generic == b.generic
