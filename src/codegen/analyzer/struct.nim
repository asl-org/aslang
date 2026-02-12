import results, strformat, tables, sets

import resolver
import module_ref
import arg_def

type
  AnalyzedStructKind* = enum
    RSK_DEFAULT, RSK_NAMED
  AnalyzedStruct* = ref object of RootObj
    struct: ResolvedStruct
    location: Location
    fields_repo: Repo[AnalyzedArgumentDefinition]
    case kind: AnalyzedStructKind
    of RSK_DEFAULT: discard
    of RSK_NAMED: name: Identifier

proc new_analyzed_struct(struct: ResolvedStruct, fields: seq[
    AnalyzedArgumentDefinition], location: Location): Result[AnalyzedStruct, string] =
  let maybe_fields_repo = new_repo(fields, @[new_index[
      AnalyzedArgumentDefinition]("name", name, true)])
  if maybe_fields_repo.is_err: return err("new_analyzed_struct UNREACHABLE")
  ok(AnalyzedStruct(kind: RSK_DEFAULT, struct: struct,
      fields_repo: maybe_fields_repo.get, location: location))

proc new_analyzed_struct(struct: ResolvedStruct, struct_name: Identifier,
    fields: seq[AnalyzedArgumentDefinition], location: Location): Result[
        AnalyzedStruct, string] =
  let maybe_fields_repo = new_repo(fields, @[new_index[
      AnalyzedArgumentDefinition]("name", name, true)])
  if maybe_fields_repo.is_err: return err("new_analyzed_struct UNREACHABLE")
  ok(AnalyzedStruct(kind: RSK_NAMED, struct: struct, name: struct_name,
      fields_repo: maybe_fields_repo.get, location: location))

proc kind*(struct: AnalyzedStruct): AnalyzedStructKind = struct.kind
proc id*(struct: AnalyzedStruct): uint64 = struct.struct.id
proc name*(struct: AnalyzedStruct): Identifier = struct.name
proc fields*(struct: AnalyzedStruct): seq[
    AnalyzedArgumentDefinition] = struct.fields_repo.items

proc generic_impls*(struct: AnalyzedStruct): Table[ResolvedModule, seq[
    HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedModule, seq[HashSet[AnalyzedImpl]]]
  for field in struct.fields: impl_set = impl_set.merge(field.generic_impls)
  return impl_set

proc asl*(struct: AnalyzedStruct, indent: string): seq[string] =
  var lines =
    case struct.kind:
    of RSK_DEFAULT: @["struct:"]
    of RSK_NAMED: @[fmt"struct {struct.name.asl}:"]

  for field in struct.fields:
    lines.add(indent & field.asl)

  return lines

proc concretize*(struct: AnalyzedStruct, concrete_map: Table[ResolvedGeneric,
    AnalyzedModuleRef]): Result[AnalyzedStruct, string] =
  var concretized_fields: seq[AnalyzedArgumentDefinition]
  for field in struct.fields:
    concretized_fields.add(field.concretize(concrete_map))

  case struct.kind:
  of RSK_DEFAULT: new_analyzed_struct(struct.struct, concretized_fields,
      struct.location)
  of RSK_NAMED: new_analyzed_struct(struct.struct, struct.name,
      concretized_fields, struct.location)

proc find_field_index*(struct: AnalyzedStruct, field: Identifier): Result[int, string] =
  let maybe_field_id = struct.fields_repo.find_id("name", field)
  if maybe_field_id.is_ok: ok(maybe_field_id.get[0])
  else: err(fmt"{field.location} field is not defined in the struct")

proc find_field*(struct: AnalyzedStruct, field: Identifier): Result[
    AnalyzedArgumentDefinition, string] =
  let maybe_field = struct.fields_repo.find("name", field)
  if maybe_field.is_ok: ok(maybe_field.get[0])
  else: err(fmt"{field.location} field is not defined in the struct")

# Helper for resolving ResolvedStruct with either module kind
proc analyze_def*(file: ResolvedFile, module: ResolvedModule,
    struct: ResolvedStruct): Result[AnalyzedStruct, string] =
  var analyzed_fields: seq[AnalyzedArgumentDefinition]
  for field in struct.fields:
    let analyzed_field = ? analyze_def(file, module, field)
    analyzed_fields.add(analyzed_field)

  case struct.kind:
  of TSK_DEFAULT:
    new_analyzed_struct(struct, analyzed_fields, struct.location)
  of TSK_NAMED:
    let struct_name = ? struct.name
    new_analyzed_struct(struct, struct_name, analyzed_fields, struct.location)

type AnalyzedUnionBranch* = ref object of RootObj
  resolved_branch: ResolvedUnionBranch
  fields_repo: Repo[AnalyzedArgumentDefinition]

proc new_analyzed_union_branch(resolved_branch: ResolvedUnionBranch,
    fields: seq[AnalyzedArgumentDefinition]): Result[AnalyzedUnionBranch, string] =
  let maybe_repo = new_repo(fields, @[
    new_index[AnalyzedArgumentDefinition]("name", name, true)
  ])
  if maybe_repo.is_err: return err("new_analyzed_union_branch [UNREACHABLE]")
  ok(AnalyzedUnionBranch(resolved_branch: resolved_branch,
      fields_repo: maybe_repo.get))

proc id*(branch: AnalyzedUnionBranch): uint64 = branch.resolved_branch.id
proc name*(branch: AnalyzedUnionBranch): Identifier = branch.resolved_branch.name

proc fields*(branch: AnalyzedUnionBranch): seq[AnalyzedArgumentDefinition] =
  branch.fields_repo.items

proc find_field_index*(branch: AnalyzedUnionBranch, field: Identifier): Result[
    int, string] =
  let maybe_field_id = branch.fields_repo.find_id("name", field)
  if maybe_field_id.is_ok: ok(maybe_field_id.get[0])
  else: err(fmt"{field.location} field is not defined in the branch `{branch.name.asl}`")

proc find_field*(branch: AnalyzedUnionBranch, field: Identifier): Result[
    AnalyzedArgumentDefinition, string] =
  let maybe_field = branch.fields_repo.find("name", field)
  if maybe_field.is_ok: ok(maybe_field.get[0])
  else: err(fmt"{field.location} field is not defined in the branch `{branch.name.asl}`")

proc generic_impls*(branch: AnalyzedUnionBranch): Table[ResolvedModule, seq[
    HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedModule, seq[HashSet[AnalyzedImpl]]]
  for field in branch.fields: impl_set = impl_set.merge(field.generic_impls)
  return impl_set

proc asl*(branch: AnalyzedUnionBranch, indent: string): seq[string] =
  var lines = @[fmt"{branch.name.asl}:"]

  for field in branch.fields:
    lines.add(indent & field.asl)

  return lines

proc concretize*(branch: AnalyzedUnionBranch, concrete_map: Table[
    ResolvedGeneric, AnalyzedModuleRef]): Result[AnalyzedUnionBranch, string] =
  var concretized_fields: seq[AnalyzedArgumentDefinition]
  for field in branch.fields:
    concretized_fields.add(field.concretize(concrete_map))
  new_analyzed_union_branch(branch.resolved_branch, concretized_fields)

proc analyze_def*(file: ResolvedFile, module: ResolvedModule,
    branch: ResolvedUnionBranch): Result[AnalyzedUnionBranch, string] =
  var analyzed_fields: seq[AnalyzedArgumentDefinition]
  for field in branch.fields:
    let analyzed_field = ? analyze_def(file, module, field)
    analyzed_fields.add(analyzed_field)
  new_analyzed_union_branch(branch, analyzed_fields)

type AnalyzedUnion* = ref object of RootObj
  resolved_union: ResolvedUnion
  branches_repo: Repo[AnalyzedUnionBranch]

proc new_analyzed_union(resolved_union: ResolvedUnion, branches: seq[
    AnalyzedUnionBranch]): Result[AnalyzedUnion, string] =
  let maybe_branches_repo = new_repo(branches, @[
    new_index[AnalyzedUnionBranch]("name", name, true)
  ])
  if maybe_branches_repo.is_err: return err("[UNREACHABLE] new_analyzed_union")
  ok(AnalyzedUnion(resolved_union: resolved_union,
      branches_repo: maybe_branches_repo.get))

proc location*(union: AnalyzedUnion): Location =
  union.resolved_union.location

proc branches*(union: AnalyzedUnion): seq[AnalyzedUnionBranch] =
  union.branches_repo.items

proc generic_impls*(union: AnalyzedUnion): Table[ResolvedModule, seq[
    HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedModule, seq[HashSet[AnalyzedImpl]]]
  for branch in union.branches: impl_set = impl_set.merge(branch.generic_impls)
  return impl_set

proc asl*(union: AnalyzedUnion, indent: string): seq[string] =
  var lines = @[fmt"union:"]

  for branch in union.branches:
    lines.add(indent & branch.asl(indent))

  return lines

proc find_branch*(union: AnalyzedUnion, name: Identifier): Result[
    AnalyzedUnionBranch, string] =
  let maybe_branch = union.branches_repo.find("name", name)
  if maybe_branch.is_err:
    err(fmt"{name.location} branch `{name.asl}` does not exist in union at location {union.location}")
  else:
    ok(maybe_branch.get[0])

# Helper for resolving ResolvedStruct with either module kind
proc analyze_def*(file: ResolvedFile, module: ResolvedModule,
    union: ResolvedUnion): Result[AnalyzedUnion, string] =
  var analyzed_union_branches: seq[AnalyzedUnionBranch]
  for branch in union.branches:
    let analyzed_branch = ? analyze_def(file, module, branch)
    analyzed_union_branches.add(analyzed_branch)
  new_analyzed_union(union, analyzed_union_branches)

type
  AnalyzedDataKind* = enum
    ADK_NONE, ADK_LITERAL, ADK_STRUCT, ADK_UNION
  AnalyzedData* = ref object of RootObj
    case kind: AnalyzedDataKind
    of ADK_NONE: discard
    of ADK_LITERAL: discard
    of ADK_STRUCT: struct: AnalyzedStruct
    of ADK_UNION: union: AnalyzedUnion

proc new_analyzed_data(): AnalyzedData =
  AnalyzedData(kind: ADK_NONE)

proc new_resolved_data(struct: AnalyzedStruct): AnalyzedData =
  AnalyzedData(kind: ADK_STRUCT, struct: struct)

proc new_resolved_data(union: AnalyzedUnion): AnalyzedData =
  AnalyzedData(kind: ADK_UNION, union: union)

proc kind*(data: AnalyzedData): AnalyzedDataKind = data.kind
proc struct*(data: AnalyzedData): AnalyzedStruct =
  do_assert data.kind == ADK_STRUCT, "[UNREACHABLE] expected a struct"
  data.struct
proc union*(data: AnalyzedData): AnalyzedUnion =
  do_assert data.kind == ADK_UNION, "[UNREACHABLE] expected a union"
  data.union

proc generic_impls*(data: AnalyzedData): Table[ResolvedModule, seq[HashSet[
    AnalyzedImpl]]] =
  var impl_set: Table[ResolvedModule, seq[HashSet[AnalyzedImpl]]]
  case data.kind:
  of ADK_NONE: discard
  of ADK_LITERAL: do_assert false, "[UNREACHABLE] literal generic_impls are not supported"
  of ADK_STRUCT: impl_set = impl_set.merge(data.struct.generic_impls)
  of ADK_UNION: impl_set = impl_set.merge(data.union.generic_impls)
  return impl_set

proc asl*(data: AnalyzedData, indent: string): seq[string] =
  var lines: seq[string]
  case data.kind:
  of ADK_NONE: discard
  of ADK_LITERAL:
    do_assert false, "[UNREACHABLE] code gen for literal not supported"
  of ADK_STRUCT:
    lines.add(data.struct.asl(indent))
  of ADK_UNION:
    lines.add(data.union.asl(indent))
  return lines

# Helper for resolving ResolvedStruct with either module kind
proc analyze_def*(file: ResolvedFile, module: ResolvedModule,
    data: ResolvedData): Result[AnalyzedData, string] =
  case data.kind:
  of RDK_NONE: return ok(new_analyzed_data())
  of RDK_LITERAL: do_assert false, "[UNREACHABLE] literal analysis is not yet supported"
  of RDK_STRUCT:
    let analyzed_struct = ? analyze_def(file, module, data.struct)
    return ok(new_resolved_data(analyzed_struct))
  of RDK_UNION:
    let analyzed_union = ? analyze_def(file, module, data.union)
    return ok(new_resolved_data(analyzed_union))
