import results, sequtils, strformat, tables, strutils, sets, options, algorithm

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
  collect_impls(struct.fields)

proc asl*(struct: AnalyzedStruct, indent: string): seq[string] =
  var lines =
    case struct.kind:
    of RSK_DEFAULT: @["struct:"]
    of RSK_NAMED: @[fmt"struct {struct.name.asl}:"]

  for field in struct.fields:
    lines.add(indent & field.asl)

  return lines

proc h*(struct: AnalyzedStruct, prefix: string): seq[string] =
  # NOTE: sort fields for efficient packing of bytes
  let fields = struct.fields.sorted(proc(a,
      b: AnalyzedArgumentDefinition): int =
    if a.byte_size > b.byte_size: -1
    elif b.byte_size > a.byte_size: 1
    else: 0
  )

  var lines: seq[string]
  # if id is some then it is a union branch so offset for id
  var offset: uint64 = 0
  for field in fields:
    lines.add(fmt"{field.module_ref.c} {prefix}_get_{field.name.asl}(Pointer __asl_ptr);")
    lines.add(fmt"Pointer {prefix}_set_{field.name.asl}(Pointer __asl_ptr, {field.c});")
    offset += field.byte_size

  # NOTE: This is hack to avoid generating an init method since `Array`
  # module has 2 properties but only 1 is accessible.
  if prefix == "Array": return lines
  # NOTE: maintain field order in the init call
  let args_str = struct.fields.map_it(it.c).join(", ")
  lines.add(fmt"Pointer {prefix}_init({args_str});")
  return lines

proc c*(struct: AnalyzedStruct, prefix: string): seq[string] =
  # NOTE: sort fields for efficient packing of bytes
  let fields = struct.fields.sorted(proc(a,
      b: AnalyzedArgumentDefinition): int =
    if a.byte_size > b.byte_size: -1
    elif b.byte_size > a.byte_size: 1
    else: 0
  )

  var lines: seq[string]
  # internal functions for structs
  # byte size
  lines.add(fmt"U64 {prefix}_byte_size(U64 items)")
  lines.add("{")
  lines.add("return Pointer_byte_size(items);")
  lines.add("}")
  # read
  lines.add(fmt"Pointer {prefix}_read(Pointer __asl_ptr, U64 offset)")
  lines.add("{")
  lines.add("return Pointer_read(__asl_ptr, offset);")
  lines.add("}")
  # write
  lines.add(fmt"Pointer {prefix}_write(Pointer value, Pointer __asl_ptr, U64 offset)")
  lines.add("{")
  lines.add("return Pointer_write(value, __asl_ptr, offset);")
  lines.add("}")

  # if id is some then it is a union branch so offset for id
  var offset: uint64 = 0
  for field in fields:
    lines.add(fmt"{field.module_ref.c} {prefix}_get_{field.name.asl}(Pointer __asl_ptr)")
    lines.add("{")
    lines.add(fmt"return {field.module_ref.c}_read(__asl_ptr, {offset});")
    lines.add("}")

    lines.add(fmt"Pointer {prefix}_set_{field.name.asl}(Pointer __asl_ptr, {field.c})")
    lines.add("{")
    lines.add(fmt"return {field.module_ref.c}_write({field.name.asl}, __asl_ptr, {offset});")
    lines.add("}")

    offset += field.byte_size

  if prefix == "Array": return lines
  # NOTE: maintain field order in the init call
  let args_str = struct.fields.map_it(it.c).join(", ")
  lines.add(fmt"Pointer {prefix}_init({args_str})")
  lines.add("{")
  lines.add(fmt"Pointer __asl_ptr = System_allocate({offset});")

  for field in struct.fields:
    lines.add(fmt"__asl_ptr = {prefix}_set_{field.name.asl}(__asl_ptr, {field.name.asl});")

  lines.add("return __asl_ptr;")
  lines.add("}")
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
  collect_impls(branch.fields)

proc asl*(branch: AnalyzedUnionBranch, indent: string): seq[string] =
  var lines = @[fmt"{branch.name.asl}:"]

  for field in branch.fields:
    lines.add(indent & field.asl)

  return lines

proc h*(branch: AnalyzedUnionBranch, prefix: string, id: uint64): seq[string] =
  let sub_prefix = fmt"{prefix}_{branch.name.asl}"

  # NOTE: sort fields for efficient packing of bytes
  let fields = branch.fields.sorted(proc(a,
      b: AnalyzedArgumentDefinition): int =
    if a.byte_size > b.byte_size: -1
    elif b.byte_size > a.byte_size: 1
    else: 0
  )

  var lines: seq[string]
  # if id is some then it is a union branch so offset for id
  var offset: uint64 = 8
  for field in fields:
    lines.add(fmt"{field.module_ref.c} {sub_prefix}_get_{field.name.asl}(Pointer __asl_ptr);")
    lines.add(fmt"Pointer {sub_prefix}_set_{field.name.asl}(Pointer __asl_ptr, {field.c});")
    offset += field.byte_size

  # NOTE: This is hack to avoid generating an init method since `Array`
  # module has 2 properties but only 1 is accessible.
  if prefix == "Array": return lines
  # NOTE: maintain field order in the init call
  let args_str = branch.fields.map_it(it.c).join(", ")
  lines.add(fmt"Pointer {sub_prefix}_init({args_str});")
  return lines

proc c*(branch: AnalyzedUnionBranch, prefix: string, id: uint64): seq[string] =
  let sub_prefix = fmt"{prefix}_{branch.name.asl}"

  # NOTE: sort fields for efficient packing of bytes
  let fields = branch.fields.sorted(proc(a,
      b: AnalyzedArgumentDefinition): int =
    if a.byte_size > b.byte_size: -1
    elif b.byte_size > a.byte_size: 1
    else: 0
  )

  var lines: seq[string]
  var offset: uint64 = 8
  for field in fields:
    lines.add(fmt"{field.module_ref.c} {sub_prefix}_get_{field.name.asl}(Pointer __asl_ptr)")
    lines.add("{")
    lines.add(fmt"return {field.module_ref.c}_read(__asl_ptr, {offset});")
    lines.add("}")

    lines.add(fmt"Pointer {sub_prefix}_set_{field.name.asl}(Pointer __asl_ptr, {field.c})")
    lines.add("{")
    lines.add(fmt"return {field.module_ref.c}_write({field.name.asl}, __asl_ptr, {offset});")
    lines.add("}")

    offset += field.byte_size

  if prefix == "Array": return lines
  # NOTE: maintain field order in the init call
  let args_str = branch.fields.map_it(it.c).join(", ")
  lines.add(fmt"Pointer {sub_prefix}_init({args_str})")
  lines.add("{")
  lines.add(fmt"Pointer __asl_ptr = System_allocate({offset});")
  lines.add(fmt"__asl_ptr = {prefix}_set_id(__asl_ptr, {id});")

  for field in branch.fields:
    lines.add(fmt"__asl_ptr = {sub_prefix}_set_{field.name.asl}(__asl_ptr, {field.name.asl});")

  lines.add("return __asl_ptr;")
  lines.add("}")
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
  collect_impls(union.branches)

proc asl*(union: AnalyzedUnion, indent: string): seq[string] =
  var lines = @[fmt"union:"]

  for branch in union.branches:
    lines.add(indent & branch.asl(indent))

  return lines

proc h*(union: AnalyzedUnion, prefix: string): seq[string] =
  var lines: seq[string]
  lines.add(fmt"U64 {prefix}_byte_size(U64 items);") # byte size
  lines.add(fmt"Pointer {prefix}_read(Pointer __asl_ptr, U64 offset);") # read
  lines.add(fmt"Pointer {prefix}_write(Pointer value, Pointer __asl_ptr, U64 offset);") # write
  # union branch id getter
  lines.add(fmt"U64 {prefix}_get_id(Pointer __asl_ptr);")
  # union branch id setter
  lines.add(fmt"Pointer {prefix}_set_id(Pointer __asl_ptr, U64 id);")
  for index, branch in union.branches:
    lines.add(branch.h(prefix, index.uint64))
  return lines

proc c*(union: AnalyzedUnion, prefix: string): seq[string] =
  var lines: seq[string]
  # internal functions for structs
  # byte size
  lines.add(fmt"U64 {prefix}_byte_size(U64 items)")
  lines.add("{")
  lines.add("return Pointer_byte_size(items);")
  lines.add("}")
  # read
  lines.add(fmt"Pointer {prefix}_read(Pointer __asl_ptr, U64 offset)")
  lines.add("{")
  lines.add("return Pointer_read(__asl_ptr, offset);")
  lines.add("}")
  # write
  lines.add(fmt"Pointer {prefix}_write(Pointer value, Pointer __asl_ptr, U64 offset)")
  lines.add("{")
  lines.add("return Pointer_write(value, __asl_ptr, offset);")
  lines.add("}")
  # union branch id getter
  lines.add(fmt"U64 {prefix}_get_id(Pointer __asl_ptr)")
  lines.add("{")
  lines.add(fmt"return U64_read(__asl_ptr, 0);")
  lines.add("}")

  # union branch id setter
  lines.add(fmt"Pointer {prefix}_set_id(Pointer __asl_ptr, U64 id)")
  lines.add("{")
  lines.add(fmt"return U64_write(id, __asl_ptr, 0);")
  lines.add("}")
  for index, branch in union.branches:
    lines.add(branch.c(prefix, index.uint64))
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

proc h*(data: AnalyzedData, prefix: string): seq[string] =
  var lines: seq[string]
  case data.kind:
  of ADK_NONE: discard
  of ADK_LITERAL: do_assert false, "[UNREACHABLE] literal codegen is not supported"
  of ADK_STRUCT:
    lines.add(data.struct.h(prefix))
  of ADK_UNION:
    lines.add(data.union.h(prefix))
  return lines

proc c*(data: AnalyzedData, prefix: string): seq[string] =
  var lines: seq[string]
  case data.kind:
  of ADK_NONE: discard
  of ADK_LITERAL: do_assert false, "[UNREACHABLE] literal code gen is not supported"
  of ADK_STRUCT: lines.add(data.struct.c(prefix))
  of ADK_UNION: lines.add(data.union.c(prefix))
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
