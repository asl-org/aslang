import strformat, strutils, results, tables

import arg_def, token

type StructDefinition* = ref object of RootObj
  location*: Location

proc `$`*(struct_definition: StructDefinition): string =
  fmt"struct:"

proc new_struct_definition*(location: Location): StructDefinition =
  StructDefinition(location: location)

type Struct* = ref object of RootObj
  struct_def*: StructDefinition
  fields*: Table[string, ArgumentDefinition]

proc new_struct*(struct_def: StructDefinition): Struct =
  Struct(struct_def: struct_def)

proc location*(struct: Struct): Location =
  struct.struct_def.location

proc `$`*(struct: Struct): string =
  let prefix = " ".repeat(struct.struct_def.location.column - 1)
  let child_prefix = " ".repeat(struct.struct_def.location.column + 1)
  var lines = @[prefix & $(struct.struct_def)]
  for field in struct.fields.values:
    lines.add(child_prefix & fmt"{field.arg_type} {field.arg_name}")
  return lines.join("\n")

proc add_field*(struct: Struct, field: ArgumentDefinition): Result[void, string] =
  let field_name = $(field.arg_name)
  if field_name in struct.fields:
    let predefined_field = struct.fields[field_name]
    return err(fmt"{field.location} Field `{field_name}` is already defined at {predefined_field.location}")

  struct.fields[field_name] = field
  ok()

proc find_field*(struct: Struct, field_name: Token): Result[
    ArgumentDefinition, string] =
  for field in struct.fields.values:
    if $(field.arg_name) == $(field_name):
      return ok(field)
  return err(fmt"{field_name.location} does not have any field named {field_name} at {struct.struct_def.location}")

proc close*(struct: Struct): Result[void, string] =
  if struct.fields.len == 0:
    return err(fmt"{struct.location} `struct` must contain at least one field")
  ok()

type UnionDefinition* = ref object of RootObj
  location*: Location

proc `$`*(union_definition: UnionDefinition): string =
  fmt"union:"

proc new_union_definition*(location: Location): UnionDefinition =
  UnionDefinition(location: location)

type UnionFieldDefinition* = ref object of RootObj
  name*: Token
  fields*: Table[string, ArgumentDefinition]

proc new_union_field_definition*(name: Token): UnionFieldDefinition =
  UnionFieldDefinition(name: name)

proc location*(union_field_def: UnionFieldDefinition): Location =
  union_field_def.name.location

proc `$`*(union_field_def: UnionFieldDefinition): string =
  let prefix = " ".repeat(union_field_def.name.location.column - 1)
  let child_prefix = " ".repeat(union_field_def.name.location.column + 1)
  var lines = @[prefix & $(union_field_def.name)]
  for field in union_field_def.fields.values:
    lines.add(child_prefix & fmt"{field.arg_type} {field.arg_name}")
  return lines.join("\n")

proc find_field*(union_field_def: UnionFieldDefinition,
    field_name: Token): Result[ArgumentDefinition, string] =
  if $(field_name) notin union_field_def.fields:
    return err(fmt"{field_name.location} Union field `{field_name}` does not exist in {union_field_def.location}")

  ok(union_field_def.fields[$(field_name)])

proc add_field*(union_field_def: UnionFieldDefinition,
    field: ArgumentDefinition): Result[void, string] =
  let field_name = $(field.arg_name)
  if field_name in union_field_def.fields:
    let predefined_location = union_field_def.fields[field_name].location
    return err(fmt"{field.location} Union field `{field_name}` is already defined at {predefined_location}")

  union_field_def.fields[field_name] = field
  ok()

proc close*(union_field_def: UnionFieldDefinition): Result[void, string] =
  if union_field_def.fields.len == 0:
    return err(fmt"{union_field_def.location} `union` field must contain at least 1 field")
  ok()

type Union* = ref object of RootObj
  union_def*: UnionDefinition
  fields*: Table[string, UnionFieldDefinition]

proc new_union*(union_def: UnionDefinition): Union =
  Union(union_def: union_def)

proc location*(union: Union): Location =
  union.union_def.location

proc find_field*(union: Union, field_name: Token): Result[UnionFieldDefinition, string] =
  if $(field_name) notin union.fields:
    return err(fmt"{field_name.location} Union field `{field_name}` does not exist in {union.location}")

  ok(union.fields[$(field_name)])

proc add_field*(union: Union, field: UnionFieldDefinition): Result[void, string] =
  let field_name = $(field.name)
  if field_name in union.fields:
    let predefined_location = union.fields[field_name].location
    return err(fmt"{field.location} Union field `{field_name}` is already defined at {predefined_location}")

  union.fields[field_name] = field
  ok()

proc `$`*(union: Union): string =
  let prefix = " ".repeat(union.union_def.location.column - 1)
  let child_prefix = " ".repeat(union.union_def.location.column + 1)
  var lines = @[prefix & $(union.union_def)]
  for field in union.fields.values:
    lines.add(child_prefix & $(field))
  return lines.join("\n")

proc close*(union: Union): Result[void, string] =
  if union.fields.len < 2:
    return err(fmt"{union.location} Union must have at least 2 fields.")
  ok()
