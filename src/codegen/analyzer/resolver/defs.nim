# ResolvedArgumentDefinition, ResolvedFunctionDefinition, ResolvedStruct
import results, strformat, strutils, sets, hashes, options

import parser
import module_ref

# =============================================================================
# ResolvedArgumentDefinition
# =============================================================================

type ResolvedArgumentDefinition* = ref object of RootObj
  name: Identifier
  module_ref: ResolvedModuleRef

proc new_resolved_argument_definition*(module_ref: ResolvedModuleRef,
    name: Identifier): ResolvedArgumentDefinition =
  ResolvedArgumentDefinition(module_ref: module_ref, name: name)

proc concretize*(def: ResolvedArgumentDefinition, generic: Generic,
    module_ref: ResolvedModuleRef): ResolvedArgumentDefinition =
  let concrete_module_ref = concretize(def.module_ref, generic, module_ref)
  new_resolved_argument_definition(concrete_module_ref, def.name)

proc module_deps*(arg: ResolvedArgumentDefinition): HashSet[Module] =
  arg.module_ref.module_deps

proc hash*(def: ResolvedArgumentDefinition): Hash =
  def.module_ref.hash

proc location*(arg: ResolvedArgumentDefinition): Location = arg.module_ref.location
proc name*(arg: ResolvedArgumentDefinition): Identifier = arg.name
proc module_ref*(arg: ResolvedArgumentDefinition): ResolvedModuleRef = arg.module_ref
proc asl*(arg: ResolvedArgumentDefinition): string = fmt"{arg.module_ref.asl} {arg.name.asl}"

proc resolve*(file: parser.File, module: Option[parser.Module],
    arg: ArgumentDefinition): Result[ResolvedArgumentDefinition, string] =
  let resolved_arg = ? resolve(file, module, arg.module_ref)
  ok(new_resolved_argument_definition(resolved_arg, arg.name))

# =============================================================================
# ResolvedFunctionDefinition
# =============================================================================

type ResolvedFunctionDefinition* = ref object of RootObj
  name: Identifier
  args: seq[ResolvedArgumentDefinition]
  returns: ResolvedModuleRef
  location: Location

proc new_resolved_function_definition*(name: Identifier, args: seq[
    ResolvedArgumentDefinition], returns: ResolvedModuleRef,
    location: Location): ResolvedFunctionDefinition =
  ResolvedFunctionDefinition(name: name, args: args, returns: returns,
      location: location)

proc module_deps*(def: ResolvedFunctionDefinition): HashSet[Module] =
  var module_set: HashSet[Module]
  for arg in def.args: module_set.incl(arg.module_deps)
  module_set.incl(def.returns.module_deps)
  module_set

proc hash*(def: ResolvedFunctionDefinition): Hash =
  var acc = def.name.hash
  for arg in def.args:
    acc = acc !& arg.hash
  acc !& def.returns.hash

proc `==`*(self: ResolvedFunctionDefinition,
    other: ResolvedFunctionDefinition): bool =
  self.hash == other.hash

proc asl*(def: ResolvedFunctionDefinition): string =
  var args: seq[string]
  for arg in def.args: args.add(arg.asl)
  let args_str = args.join(", ")
  let returns_str = def.returns.asl
  fmt"fn {def.name.asl}({args_str}): {returns_str}"

proc location*(def: ResolvedFunctionDefinition): Location = def.location
proc name*(def: ResolvedFunctionDefinition): Identifier = def.name
proc returns*(def: ResolvedFunctionDefinition): ResolvedModuleRef = def.returns
proc args*(def: ResolvedFunctionDefinition): seq[
    ResolvedArgumentDefinition] = def.args

proc concretize*(def: ResolvedFunctionDefinition, generic: Generic,
    module_ref: ResolvedModuleRef): ResolvedFunctionDefinition =
  var concrete_args: seq[ResolvedArgumentDefinition]
  for arg in def.args:
    let concrete_arg = arg.concretize(generic, module_ref)
    concrete_args.add(concrete_arg)
  let concrete_returns = def.returns.concretize(generic, module_ref)
  new_resolved_function_definition(def.name, concrete_args,
      concrete_returns, def.location)

proc resolve*(file: parser.File, module: Option[parser.Module],
    generic: Generic, def: FunctionDefinition): Result[
    ResolvedFunctionDefinition, string] =
  var resolved_args: seq[ResolvedArgumentDefinition]
  for arg in def.args:
    let resolved_arg = ? resolve(file, module, arg)
    resolved_args.add(resolved_arg)
  let resolved_return = ? resolve(file, module, def.returns)
  ok(new_resolved_function_definition(def.name, resolved_args,
      resolved_return, def.location))

proc resolve*(file: parser.File, module: Option[parser.Module],
    def: FunctionDefinition): Result[ResolvedFunctionDefinition, string] =
  var resolved_args: seq[ResolvedArgumentDefinition]
  for arg in def.args:
    resolved_args.add( ? resolve(file, module, arg))
  let resolved_return = ? resolve(file, module, def.returns)
  ok(new_resolved_function_definition(def.name, resolved_args,
      resolved_return, def.location))

# =============================================================================
# ResolvedStruct
# =============================================================================

type
  ResolvedStructKind* = enum
    TSK_DEFAULT, TSK_NAMED
  ResolvedStruct* = ref object of RootObj
    fields: seq[ResolvedArgumentDefinition]
    location: Location
    case kind: ResolvedStructKind
    of TSK_DEFAULT: discard
    of TSK_NAMED: name: Identifier

proc new_resolved_struct(fields: seq[ResolvedArgumentDefinition],
    location: Location): ResolvedStruct =
  ResolvedStruct(kind: TSK_DEFAULT, fields: fields, location: location)

proc module_deps*(struct: ResolvedStruct): HashSet[Module] =
  var module_set: HashSet[Module]
  for field in struct.fields: module_set.incl(field.module_deps)
  module_set

proc id*(struct: ResolvedStruct): uint64 = struct.id
proc hash*(struct: ResolvedStruct): Hash = struct.location.hash
proc `==`*(self: ResolvedStruct, other: ResolvedStruct): bool = self.hash == other.hash
proc kind*(struct: ResolvedStruct): ResolvedStructKind = struct.kind
proc location*(struct: ResolvedStruct): Location = struct.location
proc fields*(struct: ResolvedStruct): seq[
    ResolvedArgumentDefinition] = struct.fields

proc name*(struct: ResolvedStruct): Result[Identifier, string] =
  case struct.kind:
  of TSK_DEFAULT: err("{struct.location} expected a named struct")
  of TSK_NAMED: ok(struct.name)

proc resolve*(file: parser.File, module: parser.Module, struct: Struct): Result[
    ResolvedStruct, string] =
  var resolved_fields: seq[ResolvedArgumentDefinition]
  for field in struct.fields:
    let resolved_field = ? resolve(file, some(module), field)
    resolved_fields.add(resolved_field)
  ok(new_resolved_struct(resolved_fields, struct.location))

type ResolvedUnionBranch* = ref object of RootObj
  id: uint64
  parsed_branch: UnionBranch
  fields: seq[ResolvedArgumentDefinition]

proc new_resolved_union_branch(id: uint64, parsed_branch: UnionBranch,
    fields: seq[ResolvedArgumentDefinition]): ResolvedUnionBranch =
  ResolvedUnionBranch(id: id, parsed_branch: parsed_branch, fields: fields)

proc name*(branch: ResolvedUnionBranch): Identifier = branch.parsed_branch.name
proc id*(branch: ResolvedUnionBranch): uint64 = branch.id

proc fields*(branch: ResolvedUnionBranch): seq[ResolvedArgumentDefinition] =
  branch.fields

proc module_deps*(branch: ResolvedUnionBranch): HashSet[Module] =
  var module_set: HashSet[Module]
  for field in branch.fields: module_set.incl(field.module_deps)
  module_set

proc resolve*(file: parser.File, module: parser.Module, branch: UnionBranch,
    id: uint64): Result[ResolvedUnionBranch, string] =
  var resolved_fields: seq[ResolvedArgumentDefinition]
  for field in branch.fields:
    let resolved_field = ? resolve(file, some(module), field)
    resolved_fields.add(resolved_field)

  ok(new_resolved_union_branch(id, branch, resolved_fields))

type ResolvedUnion* = ref object of RootObj
  union: Union
  branches: seq[ResolvedUnionBranch]

proc new_resolved_union(union: Union, branches: seq[
    ResolvedUnionBranch]): ResolvedUnion =
  ResolvedUnion(union: union, branches: branches)

proc location*(union: ResolvedUnion): Location = union.union.location

proc branches*(union: ResolvedUnion): seq[ResolvedUnionBranch] =
  union.branches

proc module_deps*(union: ResolvedUnion): HashSet[Module] =
  var module_set: HashSet[Module]
  for branch in union.branches: module_set.incl(branch.module_deps)
  module_set

proc resolve*(file: parser.File, module: parser.Module, union: Union): Result[
    ResolvedUnion, string] =
  var resolved_branches: seq[ResolvedUnionBranch]
  for id, branch in union.branches:
    let resolved_branch = ? resolve(file, module, branch, id.uint64)
    resolved_branches.add(resolved_branch)
  ok(new_resolved_union(union, resolved_branches))

type
  ResolvedDataKind* = enum
    RDK_NONE, RDK_LITERAL, RDK_STRUCT, RDK_UNION
  ResolvedData* = ref object of RootObj
    case kind: ResolvedDataKind
    of RDK_NONE: discard
    of RDK_LITERAL: discard
    of RDK_STRUCT: struct: ResolvedStruct
    of RDK_UNION: union: ResolvedUnion

proc new_resolved_data(): ResolvedData =
  ResolvedData(kind: RDK_NONE)

proc new_resolved_data(struct: ResolvedStruct): ResolvedData =
  ResolvedData(kind: RDK_STRUCT, struct: struct)

proc new_resolved_data(union: ResolvedUnion): ResolvedData =
  ResolvedData(kind: RDK_UNION, union: union)

proc kind*(data: ResolvedData): ResolvedDataKind = data.kind
proc struct*(data: ResolvedData): ResolvedStruct =
  do_assert data.kind == RDK_STRUCT, "[UNREACHABLE] expected data to be struct"
  data.struct
proc union*(data: ResolvedData): ResolvedUnion =
  do_assert data.kind == RDK_UNION, "[UNREACHABLE] expected data to be union"
  data.union

proc module_deps*(data: ResolvedData): HashSet[Module] =
  case data.kind:
  of RDK_NONE: init_hashset[Module]()
  of RDK_LITERAL: init_hashset[Module]()
  of RDK_STRUCT: data.struct.module_deps
  of RDK_UNION: data.union.module_deps

proc resolve*(file: parser.File, module: parser.Module, data: Data): Result[
    ResolvedData, string] =
  case module.data.kind:
  of DK_NONE:
    return ok(new_resolved_data())
  of DK_LITERAL:
    assert false, "[UNREACHABLE] - literal resolution is not supported"
  of DK_STRUCT:
    let resolved_struct = ? resolve(file, module, module.data.struct)
    return ok(new_resolved_data(resolved_struct))
  of DK_UNION:
    let resolved_union = ? resolve(file, module, module.data.union)
    return ok(new_resolved_data(resolved_union))
