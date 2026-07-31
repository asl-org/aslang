## ResolvedStructDef — a struct definition whose fields (and required
## impl set) have been resolved.

import results, strformat, tables

import ./parser
import argtype  # ResolvedGenericArgumentType lives here
import argdef

proc buildFieldIndex(fields: seq[ResolvedArgumentDef]): Table[Identifier, int] =
  var fieldIndex: Table[Identifier, int]
  for id, field in fields:
    assert(field.name notin fieldIndex, "UNREACHABLE: duplicate field name — should have been caught in parser")
    fieldIndex[field.name] = id
  return fieldIndex

proc buildGenericTypeIndex(generics: seq[ResolvedGenericArgumentType]): Table[ResolvedGenericArgumentType, int] =
  var genericTypeIndex: Table[ResolvedGenericArgumentType, int]
  for id, generic in generics:
    assert(generic notin genericTypeIndex, "UNREACHABLE: duplicate generic field — should have been caught in resolver")
    genericTypeIndex[generic] = id
  return genericTypeIndex

type
  ResolvedStructDefKind* = enum
    rsdkInfer, rsdkExplicit
  ResolvedStructDef* = ref object
    kind: ResolvedStructDefKind
    parsed: StructDef
    generics: seq[ResolvedGenericArgumentType]
    fields: seq[ResolvedArgumentDef]
    fieldIndex: Table[Identifier, int]

proc newResolvedStructDef(kind: ResolvedStructDefKind, parsed: StructDef, generics: seq[ResolvedGenericArgumentType], fields: seq[ResolvedArgumentDef]): ResolvedStructDef =
  let fieldIndex = buildFieldIndex(fields)
  ResolvedStructDef(kind: kind, parsed: parsed, generics: generics, fields: fields, fieldIndex: fieldIndex)

proc newResolvedExplicitStructDef*(parsed: StructDef, generics: seq[ResolvedGenericArgumentType], fields: seq[ResolvedArgumentDef]): ResolvedStructDef =
  newResolvedStructDef(rsdkExplicit, parsed, generics, fields)

proc newResolvedInferredStructDef*(parsed: StructDef, generics: seq[ResolvedGenericArgumentType], fields: seq[ResolvedArgumentDef]): ResolvedStructDef =
  newResolvedStructDef(rsdkInfer, parsed, generics, fields)

proc kind*(struct: ResolvedStructDef): ResolvedStructDefKind = struct.kind
proc loc*(struct: ResolvedStructDef): Location = struct.parsed.loc
proc parsed*(struct: ResolvedStructDef): StructDef = struct.parsed
proc fields*(struct: ResolvedStructDef): seq[ResolvedArgumentDef] = struct.fields
proc requires*(struct: ResolvedStructDef): seq[ResolvedGenericArgumentType] = struct.generics

proc fieldIndex*(struct: ResolvedStructDef): Table[Identifier, int] = struct.fieldIndex
proc genericTypeIndex*(struct: ResolvedStructDef): Table[ResolvedGenericArgumentType, int] = struct.generics.buildGenericTypeIndex()

proc findField*(struct: ResolvedStructDef, name: Identifier): Result[ResolvedArgumentDef, string] =
  if name in struct.fieldIndex: ok(struct.fields[struct.fieldIndex[name]])
  else: err(fmt"{name.loc} field `{name.asl}` does not exist")

