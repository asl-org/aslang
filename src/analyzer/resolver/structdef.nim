## ResolvedStructDef — a struct definition whose fields (and required
## impl set) have been resolved.

import results, strformat, tables

import ./parser
import argtype  # ResolvedGenericArgumentType lives here
import argdef

type ResolvedStructDef* = ref object
  parsed: StructDef
  fields: seq[ResolvedArgumentDef]
  fieldIndex: Table[Identifier, int]
  genericTypeIndex: Table[ResolvedGenericArgumentType, int]

proc newResolvedStructDef*(parsed: StructDef,
    fields: seq[ResolvedArgumentDef],
    genericTypeIndex: Table[ResolvedGenericArgumentType, int]): ResolvedStructDef =
  var fieldIndex: Table[Identifier, int]
  for id, field in fields:
    assert(field.name notin fieldIndex, "UNREACHABLE: duplicate field name — should have been caught in parser")
    fieldIndex[field.name] = id
  ResolvedStructDef(parsed: parsed, fields: fields, fieldIndex: fieldIndex, genericTypeIndex: genericTypeIndex)

proc parsed*(struct: ResolvedStructDef): StructDef = struct.parsed
proc fields*(struct: ResolvedStructDef): seq[ResolvedArgumentDef] = struct.fields
proc genericTypeIndex*(struct: ResolvedStructDef): Table[ResolvedGenericArgumentType, int] = struct.genericTypeIndex
proc fieldIndex*(struct: ResolvedStructDef): Table[Identifier, int] = struct.fieldIndex
proc loc*(struct: ResolvedStructDef): Location = struct.parsed.loc

proc findField*(struct: ResolvedStructDef, name: Identifier): Result[ResolvedArgumentDef, string] =
  if name in struct.fieldIndex: ok(struct.fields[struct.fieldIndex[name]])
  else: err(fmt"{name.loc} field `{name.asl}` does not exist")

proc requires*(struct: ResolvedStructDef): seq[ResolvedGenericArgumentType] =
  var requires = newSeq[ResolvedGenericArgumentType](struct.genericTypeIndex.len)
  for genericType, index in struct.genericTypeIndex:
    requires[index] = genericType
  return requires
