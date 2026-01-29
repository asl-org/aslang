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
    fields_repo: Repo[Identifier, AnalyzedArgumentDefinition]
    case kind: AnalyzedStructKind
    of RSK_DEFAULT: discard
    of RSK_NAMED: name: Identifier

proc new_analyzed_struct(struct: ResolvedStruct, fields: seq[
    AnalyzedArgumentDefinition], location: Location): Result[AnalyzedStruct, string] =
  let maybe_fields_repo = new_repo(fields, name)
  if maybe_fields_repo.is_err: return err("new_analyzed_struct UNREACHABLE")
  ok(AnalyzedStruct(kind: RSK_DEFAULT, struct: struct,
      fields_repo: maybe_fields_repo.get, location: location))

proc new_analyzed_struct(struct: ResolvedStruct, struct_name: Identifier,
    fields: seq[AnalyzedArgumentDefinition], location: Location): Result[
        AnalyzedStruct, string] =
  let maybe_fields_repo = new_repo(fields, name)
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
  for field in struct.fields: impl_set = impl_set.merge(field.generic_impls())
  return impl_set

proc asl*(struct: AnalyzedStruct, indent: string): seq[string] =
  var lines =
    case struct.kind:
    of RSK_DEFAULT: @["struct:"]
    of RSK_NAMED: @[fmt"struct {struct.name.asl}:"]

  for field in struct.fields:
    lines.add(indent & field.asl)

  return lines

proc h*(struct: AnalyzedStruct, prefix: string, id: Option[uint64] = none(
    uint64)): seq[string] =
  let sub_prefix =
    case struct.kind:
    of RSK_DEFAULT: fmt"{prefix}"
    of RSK_NAMED: fmt"{prefix}_{struct.name.asl}"

  # NOTE: sort fields for efficient packing of bytes
  let fields = struct.fields.sorted(proc(a,
      b: AnalyzedArgumentDefinition): int =
    if a.byte_size > b.byte_size: -1
    elif b.byte_size > a.byte_size: 1
    else: 0
  )

  var lines: seq[string]
  # if id is some then it is a union branch so offset for id
  var offset: uint64 = if id.is_some: 8 else: 0
  for field in fields:
    lines.add(fmt"{field.module_ref.c} {sub_prefix}_get_{field.name.asl}(Pointer __asl_ptr);")
    lines.add(fmt"Pointer {sub_prefix}_set_{field.name.asl}(Pointer __asl_ptr, {field.c});")
    offset += field.byte_size

  # NOTE: This is hack to avoid generating an init method since `Array`
  # module has 2 properties but only 1 is accessible.
  if prefix == "Array": return lines
  # NOTE: maintain field order in the init call
  let args_str = struct.fields.map_it(it.c).join(", ")
  lines.add(fmt"Pointer {sub_prefix}_init({args_str});")
  return lines

proc c*(struct: AnalyzedStruct, prefix: string, id: Option[uint64] = none(
    uint64)): seq[string] =
  let sub_prefix =
    case struct.kind:
    of RSK_DEFAULT: fmt"{prefix}"
    of RSK_NAMED: fmt"{prefix}_{struct.name.asl}"

  # NOTE: sort fields for efficient packing of bytes
  let fields = struct.fields.sorted(proc(a,
      b: AnalyzedArgumentDefinition): int =
    if a.byte_size > b.byte_size: -1
    elif b.byte_size > a.byte_size: 1
    else: 0
  )

  var lines: seq[string]
  # if id is some then it is a union branch so offset for id
  var offset: uint64 = if id.is_some: 8 else: 0
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
  let args_str = struct.fields.map_it(it.c).join(", ")
  lines.add(fmt"Pointer {sub_prefix}_init({args_str})")
  lines.add("{")
  lines.add(fmt"Pointer __asl_ptr = System_allocate({offset});")

  # NOTE: if id is some that means it is union branch initializer so add id
  # Also note that we are using `prefix` instead of `sub_prefix`
  if id.is_some:
    lines.add(fmt"__asl_ptr = {prefix}_set_id(__asl_ptr, {id.get});")

  for field in struct.fields:
    lines.add(fmt"__asl_ptr = {sub_prefix}_set_{field.name.asl}(__asl_ptr, {field.name.asl});")

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
  let maybe_field_id = struct.fields_repo.find_id(field)
  if maybe_field_id.is_ok: ok(maybe_field_id.get)
  else: err(fmt"{field.location} field is not defined in the struct")

proc find_field*(struct: AnalyzedStruct, field: Identifier): Result[
    AnalyzedArgumentDefinition, string] =
  let maybe_field = struct.fields_repo.find(field)
  if maybe_field.is_ok: ok(maybe_field.get)
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
