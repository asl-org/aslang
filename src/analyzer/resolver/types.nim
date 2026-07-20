## ResolvedType — file-scope umbrella over ResolvedModule +
## ResolvedGeneric. Tagged-union pair: the Kind enum and the type live
## in the same file per convention.

import strformat

import ./parser
import module
import generic

type
  ResolvedTypeKind* = enum
    rdtkModule, rdtkGeneric
  ResolvedType* = ref object
    id: int
    case kind: ResolvedTypeKind
    of rdtkModule: module: ResolvedModule
    of rdtkGeneric: generic: ResolvedGeneric

proc newResolvedType*(id: int, module: ResolvedModule): ResolvedType =
  ResolvedType(id: id, kind: rdtkModule, module: module)

proc newResolvedType*(id: int, generic: ResolvedGeneric): ResolvedType =
  ResolvedType(id: id, kind: rdtkGeneric, generic: generic)

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
