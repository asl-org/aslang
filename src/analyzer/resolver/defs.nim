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
  var module_set = accumulate_module_deps(def.args)
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
    id: uint64
    fields: seq[ResolvedArgumentDefinition]
    location: Location
    case kind: ResolvedStructKind
    of TSK_DEFAULT: discard
    of TSK_NAMED: name: Identifier

proc new_resolved_struct*(id: uint64, fields: seq[ResolvedArgumentDefinition],
    location: Location): ResolvedStruct =
  ResolvedStruct(kind: TSK_DEFAULT, id: id, fields: fields, location: location)

proc new_resolved_struct*(id: uint64, name: Identifier, fields: seq[
    ResolvedArgumentDefinition], location: Location): ResolvedStruct =
  ResolvedStruct(kind: TSK_NAMED, id: id, name: name, fields: fields,
      location: location)

proc module_deps*(struct: ResolvedStruct): HashSet[Module] =
  accumulate_module_deps(struct.fields)

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

proc resolve*(file: parser.File, module: parser.Module, struct: Struct,
    id: uint64): Result[ResolvedStruct, string] =
  var resolved_fields: seq[ResolvedArgumentDefinition]
  for field in struct.fields:
    let resolved_field = ? resolve(file, some(module), field)
    resolved_fields.add(resolved_field)

  case struct.def.kind:
  of SDK_DEFAULT:
    ok(new_resolved_struct(id, resolved_fields, struct.location))
  of SDK_NAMED:
    ok(new_resolved_struct(id, struct.name, resolved_fields, struct.location))
