import results, strformat, tables

import core, defs, identifier, module_ref

type Struct* = ref object of RootObj
  def: StructDefinition
  fields_repo: Repo[ArgumentDefinition]

proc new_struct*(def: StructDefinition, fields: seq[
    ArgumentDefinition]): Result[Struct, core.Error] =
  if fields.len == 0:
    return err(err_parser_empty_struct(def.location))
  if fields.len > MAX_ARGS_LENGTH:
    return err(err_parser_struct_too_long(def.location, fields.len))

  let maybe_fields_repo = new_repo(fields, @[new_index[ArgumentDefinition](
      "name", name, true)])
  if maybe_fields_repo.is_ok:
    ok(Struct(def: def, fields_repo: maybe_fields_repo.get))
  else:
    let error = maybe_fields_repo.error
    let field = error.current
    let predefined_field_location = error.previous.location
    err(err_parser_arg_already_defined(field.location, field.name.asl,
          predefined_field_location))

proc find_field*(struct: Struct, field: Identifier): Result[ModuleRef, string] =
  let maybe_found = struct.fields_repo.find("name", field)
  if maybe_found.is_err:
    err(fmt"{field.location} [PE109] field `{field.asl}` does not exist")
  else:
    ok(maybe_found.get[0].module_ref)

proc fields*(struct: Struct): seq[ArgumentDefinition] = struct.fields_repo.items

proc location*(struct: Struct): Location =
  struct.def.location

proc name*(struct: Struct): Identifier = name(struct.def)
proc def*(struct: Struct): StructDefinition = struct.def

proc asl*(struct: Struct, indent: string): seq[string] =
  let header = struct.def.asl
  var fields: seq[string]
  for field in struct.fields:
    fields.add(indent & field.asl)

  return (@[header] & fields)

proc struct_default_spec(parser: Parser, indent: int): Result[Struct,
    core.Error] =
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

type UnionBranch* = ref object of RootObj
  name: Identifier
  fields_repo: Repo[ArgumentDefinition]

proc new_union_branch*(branch_name: Identifier, fields: seq[
    ArgumentDefinition]): Result[UnionBranch, core.Error] =
  if fields.len == 0:
    return err(err_parser_empty_union_branch(branch_name.location))
  if fields.len > MAX_ARGS_LENGTH:
    return err(err_parser_union_branch_too_long(branch_name.location, fields.len))

  let maybe_fields_repo = new_repo(fields, @[new_index[ArgumentDefinition](
      "name", name, true)])
  if maybe_fields_repo.is_ok:
    ok(UnionBranch(name: branch_name, fields_repo: maybe_fields_repo.get))
  else:
    let error = maybe_fields_repo.error
    let field = error.current
    let predefined_field_location = error.previous.location
    err(err_parser_arg_already_defined(field.location, field.name.asl,
          predefined_field_location))

proc location*(branch: UnionBranch): Location = branch.location
proc name*(branch: UnionBranch): Identifier = branch.name
proc fields*(branch: UnionBranch): seq[ArgumentDefinition] = branch.fields_repo.items
proc struct*(branch: UnionBranch): Result[Struct, string] =
  let def = new_struct_definition(branch.name, branch.name.location)
  let maybe_struct = new_struct(def, branch.fields_repo.items)
  if maybe_struct.is_ok: ok(maybe_struct.get)
  else: err($(maybe_struct.error))

proc union_branch_spec*(parser: Parser, indent: int): Result[UnionBranch,
    core.Error] =
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

type Union* = ref object of RootObj
  location: Location
  branches_repo: Repo[UnionBranch]

proc new_union*(location: Location, branches: seq[
    UnionBranch]): Result[Union, core.Error] =
  if branches.len == 0:
    return err(err_parser_empty_union_branch(location))
  if branches.len > MAX_BRANCH_LENGTH:
    return err(err_parser_union_branch_too_long(location, branches.len))

  let maybe_branches_repo = new_repo(branches, @[new_index[UnionBranch]("name",
      name, true)])
  if maybe_branches_repo.is_ok:
    ok(Union(location: location, branches_repo: maybe_branches_repo.get))
  else:
    let error = maybe_branches_repo.error
    let branch = error.current
    let predefined_branch_location = error.previous.location
    err(err_parser_arg_already_defined(branch.location, branch.name.asl,
        predefined_branch_location))

proc location*(union: Union): Location = union.location
proc branches*(union: Union): seq[UnionBranch] = union.branches_repo.items

proc find_branch*(union: Union, name: Identifier): Result[UnionBranch, string] =
  let maybe_branch = union.branches_repo.find("name", name)
  if maybe_branch.is_err:
    err(fmt"{name.location} union does not have any branch named `{name.asl}`")
  else:
    ok(maybe_branch.get[0])

proc union_spec*(parser: Parser, indent: int): Result[Union, core.Error] =
  discard ? parser.expect(indent_spec, indent)
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
    DK_NONE, DK_LITERAL, DK_STRUCT, DK_UNION
  Data* = ref object of RootObj
    case kind: DataKind
    of DK_NONE: discard
    of DK_LITERAL: discard
    of DK_STRUCT: struct: Struct
    of DK_UNION: union: Union

proc new_data*(): Data =
  Data(kind: DK_NONE)

proc new_data(union: Union): Data =
  Data(kind: DK_UNION, union: union)

proc new_data(struct: Struct): Data =
  Data(kind: DK_STRUCT, struct: struct)

proc kind*(data: Data): DataKind = data.kind
proc struct*(data: Data): Struct =
  do_assert data.kind == DK_STRUCT, "[UNREACHABLE] expected a struct"
  data.struct
proc union*(data: Data): Union =
  do_assert data.kind == DK_UNION, "[UNREACHABLE] expected a union"
  data.union

proc data_spec*(parser: Parser, indent: int): Result[Data, core.Error] =
  let maybe_union = parser.expect(union_spec, indent)
  if maybe_union.is_ok: return ok(new_data(maybe_union.get))

  let maybe_struct = parser.expect(struct_default_spec, indent)
  if maybe_struct.is_ok: return ok(new_data(maybe_struct.get))

  # TODO: Introduce may be literal data type
  ok(new_data())
