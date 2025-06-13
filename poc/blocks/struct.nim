import strformat, strutils

import arg_def, token

type StructDefinition* = ref object of RootObj
  name*: Token
  location*: Location

proc `$`*(struct_definition: StructDefinition): string =
  fmt"struct {struct_definition.name}:"

proc new_struct_definition*(name: Token, location: Location): StructDefinition =
  StructDefinition(name: name, location: location)

type Struct* = ref object of RootObj
  struct_def*: StructDefinition
  fields*: seq[ArgumentDefinition]

proc location*(struct: Struct): Location =
  struct.struct_def.location

proc name*(struct: Struct): Token =
  struct.struct_def.name

proc `$`*(struct: Struct): string =
  let prefix = " ".repeat(struct.struct_def.location.column - 1)
  let child_prefix = " ".repeat(struct.struct_def.location.column + 1)
  var lines = @[prefix & $(struct.struct_def)]
  for field in struct.fields:
    lines.add(child_prefix & fmt"{field.arg_type} {field.arg_name}")
  return lines.join("\n")

proc c*(struct: Struct): string =
  raise new_exception(IOError, "TODO: To be implemented")

proc add_field*(struct: Struct, field: ArgumentDefinition): void =
  struct.fields.add(field)

proc new_struct*(struct_def: StructDefinition): Struct =
  Struct(struct_def: struct_def)
