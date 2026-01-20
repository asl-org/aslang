# ResolvedArgumentDefinition, ResolvedUserFunctionDefinition, ResolvedStruct
import results, strformat, strutils, sets, hashes

import module_ref
export module_ref

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

proc module_deps*(arg: ResolvedArgumentDefinition): HashSet[UserModule] =
  arg.module_ref.module_deps

proc hash*(def: ResolvedArgumentDefinition): Hash =
  def.module_ref.hash

proc location*(arg: ResolvedArgumentDefinition): Location = arg.module_ref.location
proc name*(arg: ResolvedArgumentDefinition): Identifier = arg.name
proc module_ref*(arg: ResolvedArgumentDefinition): ResolvedModuleRef = arg.module_ref
proc asl*(arg: ResolvedArgumentDefinition): string = fmt"{arg.module_ref.asl} {arg.name.asl}"

# =============================================================================
# ResolvedUserFunctionDefinition
# =============================================================================

type ResolvedUserFunctionDefinition* = ref object of RootObj
  name: Identifier
  args: seq[ResolvedArgumentDefinition]
  returns: ResolvedModuleRef
  location: Location

proc new_resolved_function_definition*(name: Identifier, args: seq[
    ResolvedArgumentDefinition], returns: ResolvedModuleRef,
    location: Location): ResolvedUserFunctionDefinition =
  ResolvedUserFunctionDefinition(name: name, args: args, returns: returns,
      location: location)

proc module_deps*(def: ResolvedUserFunctionDefinition): HashSet[UserModule] =
  var module_set = accumulate_module_deps(def.args)
  module_set.incl(def.returns.module_deps)
  module_set

proc hash*(def: ResolvedUserFunctionDefinition): Hash =
  var acc = def.name.hash
  for arg in def.args:
    acc = acc !& arg.hash
  acc !& def.returns.hash

proc `==`*(self: ResolvedUserFunctionDefinition,
    other: ResolvedUserFunctionDefinition): bool =
  self.hash == other.hash

proc asl*(def: ResolvedUserFunctionDefinition): string =
  var args: seq[string]
  for arg in def.args: args.add(arg.asl)
  let args_str = args.join(", ")
  let returns_str = def.returns.asl
  fmt"fn {def.name.asl}({args_str}): {returns_str}"

proc location*(def: ResolvedUserFunctionDefinition): Location = def.location
proc name*(def: ResolvedUserFunctionDefinition): Identifier = def.name
proc returns*(def: ResolvedUserFunctionDefinition): ResolvedModuleRef = def.returns
proc args*(def: ResolvedUserFunctionDefinition): seq[
    ResolvedArgumentDefinition] = def.args

proc concretize*(def: ResolvedUserFunctionDefinition, generic: Generic,
    module_ref: ResolvedModuleRef): ResolvedUserFunctionDefinition =
  var concrete_args: seq[ResolvedArgumentDefinition]
  for arg in def.args:
    let concrete_arg = arg.concretize(generic, module_ref)
    concrete_args.add(concrete_arg)
  let concrete_returns = def.returns.concretize(generic, module_ref)
  new_resolved_function_definition(def.name, concrete_args, concrete_returns, def.location)

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

proc module_deps*(struct: ResolvedStruct): HashSet[UserModule] =
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
