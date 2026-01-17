# TypedArgumentDefinition, TypedFunctionDefinition, TypedStruct
import results, strformat, strutils, sets, hashes

import typed_ref
export typed_ref

# =============================================================================
# TypedArgumentDefinition
# =============================================================================

type TypedArgumentDefinition* = ref object of RootObj
  name: Identifier
  module_ref: TypedModuleRef

proc new_typed_argument_definition*(module_ref: TypedModuleRef,
    name: Identifier): TypedArgumentDefinition =
  TypedArgumentDefinition(module_ref: module_ref, name: name)

proc concretize*(def: TypedArgumentDefinition, generic: Generic,
    module_ref: TypedModuleRef): TypedArgumentDefinition =
  let concrete_module_ref = concretize(def.module_ref, generic, module_ref)
  new_typed_argument_definition(concrete_module_ref, def.name)

proc module_deps*(arg: TypedArgumentDefinition): HashSet[UserModule] =
  arg.module_ref.module_deps

proc hash*(def: TypedArgumentDefinition): Hash =
  def.module_ref.hash

proc location*(arg: TypedArgumentDefinition): Location = arg.module_ref.location
proc name*(arg: TypedArgumentDefinition): Identifier = arg.name
proc module_ref*(arg: TypedArgumentDefinition): TypedModuleRef = arg.module_ref
proc asl*(arg: TypedArgumentDefinition): string = fmt"{arg.module_ref.asl} {arg.name.asl}"

# =============================================================================
# TypedFunctionDefinition
# =============================================================================

type TypedFunctionDefinition* = ref object of RootObj
  name: Identifier
  args: seq[TypedArgumentDefinition]
  returns: TypedModuleRef
  location: Location

proc new_typed_function_definition*(name: Identifier, args: seq[
    TypedArgumentDefinition], returns: TypedModuleRef,
    location: Location): TypedFunctionDefinition =
  TypedFunctionDefinition(name: name, args: args, returns: returns,
      location: location)

proc module_deps*(def: TypedFunctionDefinition): HashSet[UserModule] =
  var module_set = accumulate_module_deps(def.args)
  module_set.incl(def.returns.module_deps)
  module_set

proc hash*(def: TypedFunctionDefinition): Hash =
  var acc = def.name.hash
  for arg in def.args:
    acc = acc !& arg.hash
  acc !& def.returns.hash

proc `==`*(self: TypedFunctionDefinition,
    other: TypedFunctionDefinition): bool =
  self.hash == other.hash

proc asl*(def: TypedFunctionDefinition): string =
  var args: seq[string]
  for arg in def.args: args.add(arg.asl)
  let args_str = args.join(", ")
  let returns_str = def.returns.asl
  fmt"fn {def.name.asl}({args_str}): {returns_str}"

proc location*(def: TypedFunctionDefinition): Location = def.location
proc name*(def: TypedFunctionDefinition): Identifier = def.name
proc returns*(def: TypedFunctionDefinition): TypedModuleRef = def.returns
proc args*(def: TypedFunctionDefinition): seq[
    TypedArgumentDefinition] = def.args

proc concretize*(def: TypedFunctionDefinition, generic: Generic,
    module_ref: TypedModuleRef): TypedFunctionDefinition =
  var concrete_args: seq[TypedArgumentDefinition]
  for arg in def.args:
    let concrete_arg = arg.concretize(generic, module_ref)
    concrete_args.add(concrete_arg)
  let concrete_returns = def.returns.concretize(generic, module_ref)
  new_typed_function_definition(def.name, concrete_args, concrete_returns, def.location)

# =============================================================================
# TypedStruct
# =============================================================================

type
  TypedStructKind* = enum
    TSK_DEFAULT, TSK_NAMED
  TypedStruct* = ref object of RootObj
    id: uint64
    fields: seq[TypedArgumentDefinition]
    location: Location
    case kind: TypedStructKind
    of TSK_DEFAULT: discard
    of TSK_NAMED: name: Identifier

proc new_typed_struct*(id: uint64, fields: seq[TypedArgumentDefinition],
    location: Location): TypedStruct =
  TypedStruct(kind: TSK_DEFAULT, id: id, fields: fields, location: location)

proc new_typed_struct*(id: uint64, name: Identifier, fields: seq[
    TypedArgumentDefinition], location: Location): TypedStruct =
  TypedStruct(kind: TSK_NAMED, id: id, name: name, fields: fields,
      location: location)

proc module_deps*(struct: TypedStruct): HashSet[UserModule] =
  accumulate_module_deps(struct.fields)

proc id*(struct: TypedStruct): uint64 = struct.id
proc hash*(struct: TypedStruct): Hash = struct.location.hash
proc `==`*(self: TypedStruct, other: TypedStruct): bool = self.hash == other.hash
proc kind*(struct: TypedStruct): TypedStructKind = struct.kind
proc location*(struct: TypedStruct): Location = struct.location
proc fields*(struct: TypedStruct): seq[TypedArgumentDefinition] = struct.fields

proc name*(struct: TypedStruct): Result[Identifier, string] =
  case struct.kind:
  of TSK_DEFAULT: err("{struct.location} expected a named struct")
  of TSK_NAMED: ok(struct.name)
