## ResolvedType — file-scope umbrella over ResolvedModule +
## ResolvedGeneric. Tagged-union pair: the Kind enum and the type live
## in the same file per convention.

import hashes, strformat

import ./parser
import module
import generic

type
  ResolvedTypeKind* = enum
    rdtkModule, rdtkGeneric
  ResolvedType* = ref object
    case kind: ResolvedTypeKind
    of rdtkModule: module: ResolvedModule
    of rdtkGeneric: generic: ResolvedGeneric

proc newResolvedType*(module: ResolvedModule): ResolvedType =
  ResolvedType(kind: rdtkModule, module: module)

proc newResolvedType*(generic: ResolvedGeneric): ResolvedType =
  ResolvedType(kind: rdtkGeneric, generic: generic)

proc kind*(typ: ResolvedType): ResolvedTypeKind = typ.kind
proc module*(typ: ResolvedType): ResolvedModule =
  assert typ.kind == rdtkModule,
    fmt"ResolvedType.module accessed but kind is {typ.kind}"
  typ.module
proc generic*(typ: ResolvedType): ResolvedGeneric =
  assert typ.kind == rdtkGeneric,
    fmt"ResolvedType.generic accessed but kind is {typ.kind}"
  typ.generic

proc name*(typ: ResolvedType): Identifier =
  case typ.kind:
  of rdtkModule: typ.module.name
  of rdtkGeneric: typ.generic.name

proc loc*(typ: ResolvedType): Location =
  case typ.kind:
  of rdtkModule: typ.module.loc
  of rdtkGeneric: typ.generic.loc

proc parsed*(typ: ResolvedType): parser.Type =
  ## Underlying parser Type for identity-keyed scope lookups. See
  ## plans/plan_identity_based_lookups.md — scope tables downstream
  ## of name resolution key on `parser.Type` (hash-by-loc), not on
  ## `Identifier` (hash-by-string).
  case typ.kind:
  of rdtkModule: newType(typ.module.parsed)
  of rdtkGeneric: newType(typ.generic.parsed)

proc hash*(typ: ResolvedType): Hash =
  case typ.kind:
  of rdtkModule: typ.module.hash
  of rdtkGeneric: typ.generic.hash

proc `==`*(a, b: ResolvedType): bool =
  if a.kind != b.kind: false
  else:
    case a.kind:
    of rdtkModule: a.module == b.module
    of rdtkGeneric: a.generic == b.generic
