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

proc struct_default_spec(parser: Parser, indent: int): Result[Struct, string] =
  discard ? parser.expect(indent_spec, indent)
  let def = ? parser.expect(struct_default_definition_spec)
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

proc struct_named_spec(parser: Parser, indent: int): Result[Struct, string] =
  discard ? parser.expect(indent_spec, indent)
  let def = ? parser.expect(struct_named_definition_spec)
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

proc struct_spec*(parser: Parser, indent: int): Result[Struct, string] =
  let maybe_default_struct = parser.expect(struct_default_spec, indent)
  if maybe_default_struct.is_ok: return maybe_default_struct
  parser.expect(struct_named_spec, indent)

proc struct_list_spec(parser: Parser, indent: int): Result[seq[Struct], string] =
  var structs: seq[Struct]
  discard ? parser.expect(optional_empty_line_spec)
  var maybe_struct = parser.expect(struct_spec, indent + 1)
  while maybe_struct.is_ok:
    structs.add(maybe_struct.get)
    discard ? parser.expect(optional_empty_line_spec)
    maybe_struct = parser.expect(struct_spec, indent + 1)
  ok(structs)

type UnionBranch = ref object of RootObj
  name: Identifier
  fields: seq[ArgumentDefinition]
  fields_map: Table[Identifier, int]

proc new_union_branch*(name: Identifier, fields: seq[
    ArgumentDefinition]): Result[UnionBranch, string] =
  if fields.len == 0:
    return err(fmt"{name.location} [PE106] union branch can not be empty")
  if fields.len > MAX_ARGS_LENGTH:
    return err(fmt"{name.location} [PE107] union branch field length `{fields.len}` exceeded maximum field length `{MAX_ARGS_LENGTH}`")

  var fields_map: Table[Identifier, int]
  for index, field in fields.pairs:
    if field.name in fields_map:
      let predefined_field_location = fields[fields_map[field.name]].location
      return err(fmt"{field.location} [PE108] field `{field.name.asl}` is already defined at {predefined_field_location}")
    fields_map[field.name] = index

  ok(UnionBranch(name: name, fields: fields, fields_map: fields_map))

proc location(branch: UnionBranch): Location = branch.location
proc name*(branch: UnionBranch): Identifier = branch.name

proc union_branch_spec*(parser: Parser, indent: int): Result[UnionBranch, string] =
  discard ? parser.expect(indent_spec, indent)
  let name = ? parser.expect(identifier_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(colon_spec)
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

  new_union_branch(name, fields)

type Union = ref object of RootObj
  location: Location
  branches: seq[UnionBranch]
  branch_map: Table[Identifier, int]

proc new_union*(location: Location, branches: seq[
    UnionBranch]): Result[Union, string] =
  if branches.len == 0:
    return err(fmt"{location} [PE106] union branch can not be empty")
  if branches.len > MAX_BRANCH_LENGTH:
    return err(fmt"{location} [PE107] union branch field length `{branches.len}` exceeded maximum field length `{MAX_BRANCH_LENGTH}`")

  var branch_map: Table[Identifier, int]
  for index, branch in branches:
    if branch.name in branch_map:
      let predefined_branch_location = branches[branch_map[
          branch.name]].location
      return err(fmt"{branch.location} [PE108] branch `{branch.name.asl}` is already defined at {predefined_branch_location}")
    branch_map[branch.name] = index

  ok(Union(location: location, branches: branches, branch_map: branch_map))

proc find_branch*(union: Union, name: Identifier): Result[UnionBranch, string] =
  if name in union.branch_map:
    ok(union.branches[union.branch_map[name]])
  else:
    err(fmt"{name.location} union does not have any branch named `{name.asl}`")

proc union_spec*(parser: Parser, indent: int): Result[Union, string] =
  let union_keyword = ? parser.expect(identifier_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(colon_spec)
  discard ? parser.expect(strict_empty_line_spec)

  var branches: seq[UnionBranch]
  discard ? parser.expect(optional_empty_line_spec)
  var maybe_union_branch = parser.expect(union_branch_spec, indent + 1)
  while maybe_union_branch.is_ok:
    branches.add(maybe_union_branch.get)
    discard ? parser.expect(optional_empty_line_spec)
    maybe_union_branch = parser.expect(union_branch_spec, indent + 1)

  new_union(union_keyword.location, branches)

type
  DataKind* = enum
    DK_NONE, DK_LITERAL, DK_STRUCT, DK_UNION, DK_MULTI_STRUCT
  Data* = ref object of RootObj
    case kind: DataKind
    of DK_NONE: discard
    of DK_LITERAL: discard
    of DK_STRUCT: struct: Struct
    of DK_UNION: union: Union
    of DK_MULTI_STRUCT: structs: seq[Struct]

proc new_data*(): Data =
  Data(kind: DK_NONE)

proc new_data(union: Union): Data =
  Data(kind: DK_UNION, union: union)

proc new_data(struct: Struct): Data =
  Data(kind: DK_STRUCT, struct: struct)

proc new_data*(structs: seq[Struct]): Data =
  Data(kind: DK_MULTI_STRUCT, structs: structs)

proc kind*(data: Data): DataKind = data.kind
proc structs*(data: Data): Result[seq[Struct], string] =
  case data.kind:
  of DK_MULTI_STRUCT: ok(data.structs)
  else: err(fmt"[INTERNAL ERROR] - expected data to be a list of structs but found {data.kind}")
proc struct*(data: Data): Result[Struct, string] =
  case data.kind:
  of DK_STRUCT: ok(data.struct)
  else: err(fmt"[INTERNAL ERROR] - expected data to be a default struct but found {data.kind}")
proc union*(data: Data): Result[Union, string] =
  case data.kind:
  of DK_UNION: ok(data.union)
  else: err(fmt"[INTERNAL ERROR] - expected data to be a union but found {data.kind}")

proc data_spec*(parser: Parser, indent: int): Result[Data, string] =
  let maybe_union = parser.expect(union_spec, indent)
  if maybe_union.is_ok:
    return ok(new_data(maybe_union.get))

  let maybe_struct = parser.expect(struct_default_spec, indent)
  if maybe_struct.is_ok:
    return ok(new_data(maybe_struct.get))

  let maybe_multi_struct = parser.expect(struct_list_spec, indent)
  if maybe_multi_struct.is_ok:
    return ok(new_data(maybe_multi_struct.get))

  # TODO: Introduce may be literal data type
  ok(new_data())
