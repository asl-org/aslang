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

proc new_struct*(struct_def: StructDefinition): Struct =
  Struct(struct_def: struct_def)

proc close*(struct: Struct): Result[void, string] =
  if struct.fields.len == 0:
    return err(fmt"{struct.location} `struct` must contain at least one field")
  ok()
