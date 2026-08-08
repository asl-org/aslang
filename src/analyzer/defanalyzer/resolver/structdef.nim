## ResolvedStructDef — a struct definition whose fields (and required
## impl set) have been resolved.

import results, sequtils, sets, strformat, tables

import ./parser
import ./indexing
import argtype  # ResolvedGenericArgumentType lives here
import argdef

proc buildGenericTypeIndex(generics: seq[ResolvedGenericArgumentType]): Table[ResolvedGenericArgumentType, int] =
  var genericTypeIndex: Table[ResolvedGenericArgumentType, int]
  for id, generic in generics:
    assert(generic notin genericTypeIndex, "[BUG] - Resolver dedups generic slots first-seen")
    genericTypeIndex[generic] = id
  return genericTypeIndex

type ResolvedStructDef* = ref object
  parsed: StructDef
  generics: seq[ResolvedGenericArgumentType]
  fields: seq[ResolvedArgumentDef]
  fieldIndex: Table[Identifier, int]

proc newResolvedStructDef*(parsed: StructDef, requires: seq[ResolvedGenericArgumentType], fields: seq[ResolvedArgumentDef]): Result[ResolvedStructDef, string] =
  ## Front-door: owns the explicit-vs-inferred decision. With an
  ## explicit `struct(...)` header (`requires` non-empty) no field may
  ## be generic-typed — the two declaration modes are mutually
  ## exclusive; with a plain header the generics are inferred from
  ## the fields in first-seen order. Nothing downstream needs to know
  ## which path produced the def.
  var genericFields: OrderedSet[ResolvedGenericArgumentType]
  for field in fields:
    case field.argType.kind:
    of ratkModule: discard
    of ratkGeneric: genericFields.incl(field.argType.generic)

  if requires.len > 0 and genericFields.len > 0:
    return err(fmt"{parsed.loc} struct with explicit generic requirements does not support generic fields")

  let generics = if requires.len > 0: requires else: genericFields.toSeq
  let fieldIndex = fields.indexByName()
  ok(ResolvedStructDef(parsed: parsed, generics: generics, fields: fields, fieldIndex: fieldIndex))

proc fields*(struct: ResolvedStructDef): seq[ResolvedArgumentDef] = struct.fields
proc requires*(struct: ResolvedStructDef): seq[ResolvedGenericArgumentType] = struct.generics

proc genericTypeIndex*(struct: ResolvedStructDef): Table[ResolvedGenericArgumentType, int] = struct.generics.buildGenericTypeIndex()

proc findField*(struct: ResolvedStructDef, name: Identifier): Result[ResolvedArgumentDef, string] =
  if name in struct.fieldIndex: ok(struct.fields[struct.fieldIndex[name]])
  else: err(fmt"{name.loc} field `{name.asl}` does not exist")

