## ResolvedStructDef — a struct definition whose fields (and required
## impl set) have been resolved.

import results, strformat, tables

import ./parser
import argtype  # ResolvedGenericArgumentType lives here
import argdef

proc buildFieldIndex(fields: seq[ResolvedArgumentDef]): Table[Identifier, int] =
  var fieldIndex: Table[Identifier, int]
  for id, field in fields:
    assert(field.name notin fieldIndex, "[BUG] - Parser rejects duplicate field names")
    fieldIndex[field.name] = id
  return fieldIndex

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

proc newResolvedStructDef*(parsed: StructDef, generics: seq[ResolvedGenericArgumentType], fields: seq[ResolvedArgumentDef]): ResolvedStructDef =
  ## One constructor for both the explicit-header and inferred-from-
  ## fields paths — the split is fully decided by resolveStructDef
  ## before construction, and nothing downstream ever needed to know
  ## which path produced the def.
  let fieldIndex = buildFieldIndex(fields)
  ResolvedStructDef(parsed: parsed, generics: generics, fields: fields, fieldIndex: fieldIndex)

proc loc*(struct: ResolvedStructDef): Location = struct.parsed.loc
proc parsed*(struct: ResolvedStructDef): StructDef = struct.parsed
proc fields*(struct: ResolvedStructDef): seq[ResolvedArgumentDef] = struct.fields
proc requires*(struct: ResolvedStructDef): seq[ResolvedGenericArgumentType] = struct.generics

proc fieldIndex*(struct: ResolvedStructDef): Table[Identifier, int] = struct.fieldIndex
proc genericTypeIndex*(struct: ResolvedStructDef): Table[ResolvedGenericArgumentType, int] = struct.generics.buildGenericTypeIndex()

proc findField*(struct: ResolvedStructDef, name: Identifier): Result[ResolvedArgumentDef, string] =
  if name in struct.fieldIndex: ok(struct.fields[struct.fieldIndex[name]])
  else: err(fmt"{name.loc} field `{name.asl}` does not exist")

