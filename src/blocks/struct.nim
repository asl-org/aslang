import strformat, strutils, results, tables

import arg_def, token, function

type StructDefinition* = ref object of RootObj
  location*: Location

proc `$`*(struct_definition: StructDefinition): string =
  fmt"struct:"

proc new_struct_definition*(location: Location): StructDefinition =
  StructDefinition(location: location)

type Struct* = ref object of RootObj
  struct_def*: StructDefinition
  field_map*: Table[string, int]
  fields*: seq[ArgumentDefinition]

proc new_struct*(struct_def: StructDefinition): Struct =
  Struct(struct_def: struct_def)

proc location*(struct: Struct): Location =
  struct.struct_def.location

proc `$`*(struct: Struct): string =
  let prefix = " ".repeat(struct.struct_def.location.column - 1)
  let child_prefix = " ".repeat(struct.struct_def.location.column + 1)
  var lines = @[prefix & $(struct.struct_def)]
  for field in struct.fields:
    lines.add(child_prefix & fmt"{field.typ} {field.name}")
  return lines.join("\n")

proc add_field*(struct: Struct, field: ArgumentDefinition): Result[void, string] =
  let field_name = $(field.name)
  if field_name in struct.field_map:
    let predefined_field = struct.fields[struct.field_map[field_name]]
    return err(fmt"{field.location} Field `{field_name}` is already defined at {predefined_field.location}")

  struct.field_map[field_name] = struct.fields.len
  struct.fields.add(field)
  ok()

proc find_field*(struct: Struct, field_name: Token): Result[
    ArgumentDefinition, string] =
  if $(field_name) notin struct.field_map:
    return err(fmt"{field_name.location} does not have any field named {field_name} at {struct.struct_def.location}")
  return ok(struct.fields[struct.field_map[$(field_name)]])

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
  field_map*: Table[string, int]
  fields*: seq[ArgumentDefinition]

proc new_union_field_definition*(name: Token): UnionFieldDefinition =
  UnionFieldDefinition(name: name)

proc location*(union_field_def: UnionFieldDefinition): Location =
  union_field_def.name.location

proc `$`*(union_field_def: UnionFieldDefinition): string =
  let prefix = " ".repeat(union_field_def.name.location.column - 1)
  let child_prefix = " ".repeat(union_field_def.name.location.column + 1)
  var lines = @[prefix & $(union_field_def.name)]
  for field in union_field_def.fields:
    lines.add(child_prefix & fmt"{field.typ} {field.name}")
  return lines.join("\n")

proc find_field*(union_field_def: UnionFieldDefinition,
    field_name: Token): Result[ArgumentDefinition, string] =
  if $(field_name) notin union_field_def.field_map:
    return err(fmt"{field_name.location} Union field `{field_name}` does not exist in {union_field_def.location}")

  ok(union_field_def.fields[union_field_def.field_map[$(field_name)]])

proc add_field*(union_field_def: UnionFieldDefinition,
    field: ArgumentDefinition): Result[void, string] =
  let field_name = $(field.name)
  if field_name in union_field_def.field_map:
    let predefined_location = union_field_def.fields[union_field_def.field_map[
        field_name]].location
    return err(fmt"{field.location} Union field `{field_name}` is already defined at {predefined_location}")

  union_field_def.field_map[field_name] = union_field_def.fields.len
  union_field_def.fields.add(field)
  ok()

proc close*(union_field_def: UnionFieldDefinition): Result[void, string] =
  if union_field_def.fields.len == 0:
    return err(fmt"{union_field_def.location} `union` field must contain at least 1 field")
  ok()

type Union* = ref object of RootObj
  union_def*: UnionDefinition
  fields*: seq[UnionFieldDefinition]
  field_map*: Table[string, int]

proc new_union*(union_def: UnionDefinition): Union =
  Union(union_def: union_def)

proc location*(union: Union): Location =
  union.union_def.location

proc find_field_id*(union: Union, field_name: Token): Result[int, string] =
  if $(field_name) notin union.field_map:
    return err(fmt"{field_name.location} Union field `{field_name}` does not exist in {union.location}")
  ok(union.field_map[$(field_name)])

proc find_field*(union: Union, field_name: Token): Result[UnionFieldDefinition, string] =
  let index = ? union.find_field_id(field_name)
  ok(union.fields[index])

proc add_field*(union: Union, field: UnionFieldDefinition): Result[void, string] =
  let field_name = $(field.name)
  if field_name in union.field_map:
    let index = union.field_map[field_name]
    let predefined_location = union.fields[index].location
    return err(fmt"{field.location} Union field `{field_name}` is already defined at {predefined_location}")

  # NOTE: At max 256 union branches are allowed due to 1 byte `id` field (0-255)
  if union.fields.len > 256:
    return err(fmt"{field.location} Union only supports 256 fields at max")

  union.field_map[field_name] = union.fields.len
  union.fields.add(field)
  ok()

proc `$`*(union: Union): string =
  let prefix = " ".repeat(union.union_def.location.column - 1)
  let child_prefix = " ".repeat(union.union_def.location.column + 1)
  var lines = @[prefix & $(union.union_def)]
  for field in union.fields:
    lines.add(child_prefix & $(field))
  return lines.join("\n")

proc close*(union: Union): Result[void, string] =
  if union.fields.len < 2:
    return err(fmt"{union.location} Union must have at least 2 fields.")
  ok()

type
  GenericKind* = enum
    GDK_DEFAULT, GDK_EXTENDED
  Generic* = ref object of RootObj
    name*: Token
    location*: Location
    case kind*: GenericKind
    of GDK_DEFAULT: discard
    of GDK_EXTENDED: constraints: seq[FunctionDefinition]

proc `$`*(generic: Generic): string =
  case generic.kind:
  of GDK_DEFAULT:
    fmt"generic {generic.name}"
  of GDK_EXTENDED:
    # TODO: add constraints/function definitions
    fmt"generic {generic.name}:"

proc new_generic*(name: Token,
    location: Location): Generic =
  Generic(kind: GDK_DEFAULT, name: name, location: location)

proc new_extended_generic*(name: Token,
    location: Location): Generic =
  Generic(kind: GDK_EXTENDED, name: name, location: location)

proc add_constraint*(generic: Generic, func_def: FunctionDefinition): Result[
    void, string] =
  case generic.kind:
  of GDK_DEFAULT:
    err(fmt"{generic.location} Generic block is missing `:` at the end")
  of GDK_EXTENDED:
    for constraint in generic.constraints:
      if constraint.hash() == func_def.hash():
        return err(fmt"{func_def.location} same constraint is already defined at {constraint.location}")
    generic.constraints.add(func_def)
    ok()

proc constraints*(generic: Generic): seq[
    FunctionDefinition] = generic.constraints

proc constraints*(generic: Generic, module_name: Token): seq[
    FunctionDefinition] =
  var concrete_constraints: seq[FunctionDefinition]
  for func_def in generic.constraints:
    var concrete_arg_def_list: seq[ArgumentDefinition]
    for arg_def in func_def.arg_def_list:
      if $(arg_def.typ) == $(generic.name):
        concrete_arg_def_list.add(new_argument_definition(module_name, arg_def.name))

    let concrete_return_type =
      if $(func_def.return_type) == $(generic.name): module_name
      else: func_def.return_type

    let concrete_func_def = new_function_definition(func_def.name,
        concrete_arg_def_list, concrete_return_type, func_def.location)
    concrete_constraints.add(concrete_func_def)

  return concrete_constraints

proc close*(generic: Generic): Result[void, string] =
  case generic.kind:
  of GDK_DEFAULT: discard
  of GDK_EXTENDED:
    if generic.constraints.len == 0:
      return err(fmt"{generic.location} `generic` block must contain at least one constraint.")
  ok()
