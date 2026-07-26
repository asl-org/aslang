## ResolvedType — file-scope umbrella over ResolvedModule +
## ResolvedGeneric. Tagged-union pair: the Kind enum and the type live
## in the same file per convention.

import hashes, strformat

import ./parser
import module
import generic

type
  ResolvedTypeKind* = enum
    rtkModule, rtkGeneric
  ResolvedType* = ref object
    case kind: ResolvedTypeKind
    of rtkModule: module: ResolvedModule
    of rtkGeneric: generic: ResolvedGeneric

proc newResolvedType*(module: ResolvedModule): ResolvedType =
  ResolvedType(kind: rtkModule, module: module)

proc newResolvedType*(generic: ResolvedGeneric): ResolvedType =
  ResolvedType(kind: rtkGeneric, generic: generic)

proc kind*(typ: ResolvedType): ResolvedTypeKind = typ.kind
proc module*(typ: ResolvedType): ResolvedModule =
  assert typ.kind == rtkModule,
    fmt"ResolvedType.module accessed but kind is {typ.kind}"
  typ.module
proc generic*(typ: ResolvedType): ResolvedGeneric =
  assert typ.kind == rtkGeneric,
    fmt"ResolvedType.generic accessed but kind is {typ.kind}"
  typ.generic

proc name*(typ: ResolvedType): Identifier =
  case typ.kind:
  of rtkModule: typ.module.name
  of rtkGeneric: typ.generic.name

proc loc*(typ: ResolvedType): Location =
  case typ.kind:
  of rtkModule: typ.module.loc
  of rtkGeneric: typ.generic.loc

proc parsed*(typ: ResolvedType): parser.Type =
  ## Underlying parser Type for identity-keyed scope lookups. See
  ## plans/plan_identity_based_lookups.md — scope tables downstream
  ## of name resolution key on `parser.Type` (hash-by-loc), not on
  ## `Identifier` (hash-by-string).
  case typ.kind:
  of rtkModule: newType(typ.module.parsed)
  of rtkGeneric: newType(typ.generic.parsed)

proc hash*(typ: ResolvedType): Hash =
  case typ.kind:
  of rtkModule: typ.module.hash
  of rtkGeneric: typ.generic.hash

proc `==`*(a, b: ResolvedType): bool =
  if a.kind != b.kind: false
  else:
    case a.kind:
    of rtkModule: a.module == b.module
    of rtkGeneric: a.generic == b.generic
