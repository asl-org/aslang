import results, strformat, tables

import core, defs
export core, defs

type Struct* = ref object of RootObj
  def: StructDefinition
  fields: seq[ArgumentDefinition]
  fields_map: Table[Identifier, int]

proc new_struct*(def: StructDefinition, fields: seq[
    ArgumentDefinition]): Result[Struct, string] =
  if fields.len == 0:
    return err(fmt"{def.location} [PE106] struct block can not be empty")
  if fields.len > MAX_ARGS_LENGTH:
    return err(fmt"{def.location} [PE107] struct field length `{fields.len}` exceeded maximum field length `{MAX_ARGS_LENGTH}`")

  var fields_map: Table[Identifier, int]
  for index, field in fields.pairs:
    if field.name in fields_map:
      let predefined_field_location = fields[fields_map[field.name]].location
      return err(fmt"{field.location} [PE108] field `{field.name.asl}` is already defined at {predefined_field_location}")
    fields_map[field.name] = index

  ok(Struct(def: def, fields: fields, fields_map: fields_map))

proc find_field*(struct: Struct, field: Identifier): Result[ModuleRef, string] =
  if field notin struct.fields_map:
    err(fmt"{field.location} [PE109] field `{field.asl}` does not exist")
  else:
    ok(struct.fields[struct.fields_map[field]].module_ref)

proc fields*(struct: Struct): seq[ArgumentDefinition] = struct.fields

proc location*(struct: Struct): Location =
  struct.def.location

proc name*(struct: Struct): Result[Identifier, string] = name(struct.def)
proc def*(struct: Struct): StructDefinition = struct.def

proc asl*(struct: Struct, indent: string): seq[string] =
  let header = struct.def.asl
  var fields: seq[string]
  for field in struct.fields:
    fields.add(indent & field.asl)

  return (@[header] & fields)

proc struct_spec*(parser: Parser, indent: int): Result[Struct, string] =
  discard ? parser.expect(indent_spec, indent)
  let def = ? parser.expect(struct_definition_spec)
  discard ? parser.expect(strict_empty_line_spec)

  var fields: seq[ArgumentDefinition]
  # NOTE: struct must always at least have 1 field.
  fields.add( ? parser.expect(struct_field_definition_spec, indent + 1))
  discard ? parser.expect(strict_empty_line_spec)

  var maybe_field = parser.expect(struct_field_definition_spec, indent + 1)
  while maybe_field.is_ok:
    fields.add(maybe_field.get)
    discard ? parser.expect(strict_empty_line_spec)
    maybe_field = parser.expect(struct_field_definition_spec, indent + 1)

  new_struct(def, fields)
