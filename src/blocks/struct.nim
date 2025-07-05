import strformat, strutils, results

import arg_def, token

type NamedStructDefinition* = ref object of RootObj
  name*: Token
  location*: Location

proc `$`*(struct_definition: NamedStructDefinition): string =
  fmt"struct {struct_definition.name}:"

proc new_named_struct_definition*(name: Token,
    location: Location): NamedStructDefinition =
  NamedStructDefinition(name: name, location: location)

type StructDefinition* = ref object of RootObj
  location*: Location

proc `$`*(struct_definition: StructDefinition): string =
  fmt"struct:"

proc new_struct_definition*(location: Location): StructDefinition =
  StructDefinition(location: location)

type NamedStruct* = ref object of RootObj
  struct_def*: NamedStructDefinition
  fields*: seq[ArgumentDefinition]

proc location*(struct: NamedStruct): Location =
  struct.struct_def.location

proc name*(struct: NamedStruct): Token =
  struct.struct_def.name

proc `$`*(struct: NamedStruct): string =
  let prefix = " ".repeat(struct.struct_def.location.column - 1)
  let child_prefix = " ".repeat(struct.struct_def.location.column + 1)
  var lines = @[prefix & $(struct.struct_def)]
  for field in struct.fields:
    lines.add(child_prefix & fmt"{field.arg_type} {field.arg_name}")
  return lines.join("\n")

proc add_field*(struct: NamedStruct, field: ArgumentDefinition): void =
  struct.fields.add(field)

proc new_named_struct*(struct_def: NamedStructDefinition): NamedStruct =
  NamedStruct(struct_def: struct_def)

proc find_field*(struct: NamedStruct, field_name: Token): Result[
    ArgumentDefinition, string] =
  for field in struct.fields:
    if $(field.arg_name) == $(field_name):
      return ok(field)
  return err(fmt"{field_name.location} {struct.name} does not have any field named {field_name}")

type Struct* = ref object of RootObj
  struct_def*: StructDefinition
  fields*: seq[ArgumentDefinition]

proc location*(struct: Struct): Location =
  struct.struct_def.location

proc `$`*(struct: Struct): string =
  let prefix = " ".repeat(struct.struct_def.location.column - 1)
  let child_prefix = " ".repeat(struct.struct_def.location.column + 1)
  var lines = @[prefix & $(struct.struct_def)]
  for field in struct.fields:
    lines.add(child_prefix & fmt"{field.arg_type} {field.arg_name}")
  return lines.join("\n")

proc add_field*(struct: Struct, field: ArgumentDefinition): void =
  struct.fields.add(field)

proc new_struct*(struct_def: StructDefinition): Struct =
  Struct(struct_def: struct_def)

proc find_field*(struct: Struct, field_name: Token): Result[
    ArgumentDefinition, string] =
  for field in struct.fields:
    if $(field.arg_name) == $(field_name):
      return ok(field)
  return err(fmt"{field_name.location} does not have any field named {field_name} at {struct.struct_def.location}")
