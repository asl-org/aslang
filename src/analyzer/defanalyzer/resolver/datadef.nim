## ResolvedDataDef — the tagged-union umbrella over a module's underlying
## representation: literal (primitive), struct, or union.

import strformat

import argtype  # ResolvedGenericArgumentType
import literaldef  # ResolvedLiteralDef
import structdef
import uniondef

type
  ResolvedDataKind* = enum
    rdkLiteral, rdkStruct, rdkUnion

  ResolvedDataDef* = ref object
    case kind: ResolvedDataKind
    of rdkLiteral: literal: ResolvedLiteralDef
    of rdkStruct: struct: ResolvedStructDef
    of rdkUnion: union: ResolvedUnionDef

proc newResolvedDataDef*(literal: ResolvedLiteralDef): ResolvedDataDef =
  ResolvedDataDef(kind: rdkLiteral, literal: literal)

proc newResolvedDataDef*(struct: ResolvedStructDef): ResolvedDataDef =
  ResolvedDataDef(kind: rdkStruct, struct: struct)

proc newResolvedDataDef*(union: ResolvedUnionDef): ResolvedDataDef =
  ResolvedDataDef(kind: rdkUnion, union: union)

proc kind*(data: ResolvedDataDef): ResolvedDataKind = data.kind
proc literal*(data: ResolvedDataDef): ResolvedLiteralDef =
  assert data.kind == rdkLiteral,
    fmt"ResolvedDataDef.literal accessed but kind is {data.kind}"
  data.literal
proc struct*(data: ResolvedDataDef): ResolvedStructDef =
  assert data.kind == rdkStruct,
    fmt"ResolvedDataDef.struct accessed but kind is {data.kind}"
  data.struct
proc union*(data: ResolvedDataDef): ResolvedUnionDef =
  assert data.kind == rdkUnion,
    fmt"ResolvedDataDef.union accessed but kind is {data.kind}"
  data.union

proc requires*(data: ResolvedDataDef): seq[ResolvedGenericArgumentType] =
  case data.kind:
  of rdkLiteral: @[]
  of rdkStruct: data.struct.requires
  of rdkUnion: data.union.requires
