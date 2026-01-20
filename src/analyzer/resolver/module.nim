import results, strformat, tables, sets, hashes, sequtils, options

import parser
import expression
export expression

# =============================================================================
# ResolvedGeneric
# =============================================================================
type ResolvedGeneric* = ref object of RootObj
  id: uint64
  generic: Generic
  defs: seq[ResolvedUserFunctionDefinition]
  defs_map: Table[ResolvedUserFunctionDefinition, ResolvedUserFunctionDefinition]
  location: Location

proc new_resolved_generic*(id: uint64, generic: Generic, defs: seq[
    ResolvedUserFunctionDefinition], location: Location): ResolvedGeneric =
  var defs_map: Table[ResolvedUserFunctionDefinition, ResolvedUserFunctionDefinition]
  for def in defs: defs_map[def] = def
  ResolvedGeneric(id: id, generic: generic, defs: defs, defs_map: defs_map,
      location: location)

proc module_deps*(generic: ResolvedGeneric): HashSet[UserModule] =
  accumulate_module_deps(generic.defs)

proc id*(generic: ResolvedGeneric): uint64 = generic.id
proc location*(generic: ResolvedGeneric): Location = generic.location
proc name*(generic: ResolvedGeneric): Identifier = generic.generic.name
proc defs*(generic: ResolvedGeneric): seq[
    ResolvedUserFunctionDefinition] = generic.defs
proc hash*(generic: ResolvedGeneric): Hash = generic.location.hash
proc `==`*(self: ResolvedGeneric, other: ResolvedGeneric): bool = self.hash == other.hash
proc asl*(generic: ResolvedGeneric): string = generic.name.asl

proc concrete_defs*(generic: ResolvedGeneric,
    module_ref: ResolvedModuleRef): seq[ResolvedUserFunctionDefinition] =
  var concrete_defs: seq[ResolvedUserFunctionDefinition]
  for def in generic.defs:
    let concrete_def = def.concretize(generic.generic, module_ref)
    concrete_defs.add(concrete_def)
  concrete_defs

proc find_function*(generic: ResolvedGeneric,
    def: ResolvedUserFunctionDefinition): Result[ResolvedUserFunctionDefinition, string] =
  if def in generic.defs_map:
    ok(generic.defs_map[def])
  else:
    err(fmt"failed to find function `{def.asl}`")

proc resolve*(file: parser.File, module: Option[parser.Module],
    generic: Generic, id: uint64): Result[ResolvedGeneric, string] =
  var resolved_fndefs: seq[ResolvedUserFunctionDefinition]
  for def in generic.defs:
    let resolved_fndef = ? resolve(file, module, generic, def)
    resolved_fndefs.add(resolved_fndef)
  ok(new_resolved_generic(id, generic, resolved_fndefs, generic.location))

# =============================================================================
# ResolvedUserModule
# =============================================================================
type ResolvedUserModule* = ref object of RootObj
  id: uint64
  name: Identifier
  location: Location
  generics: seq[ResolvedGeneric]
  generics_map: Table[Generic, ResolvedGeneric]
  structs: seq[ResolvedStruct]
  functions_map: Table[ResolvedUserFunctionDefinition, ResolvedFunction]
  functions: seq[ResolvedFunction]

proc new_resolved_user_module*(id: uint64, name: Identifier, generic_pairs: seq[
    (Generic, ResolvedGeneric)], structs: seq[ResolvedStruct], functions: seq[
    ResolvedFunction], location: Location): ResolvedUserModule =
  var generics: seq[ResolvedGeneric]
  var generics_map: Table[Generic, ResolvedGeneric]
  for (generic, resolved_generic) in generic_pairs:
    generics.add(resolved_generic)
    generics_map[generic] = resolved_generic

  var functions_map: Table[ResolvedUserFunctionDefinition, ResolvedFunction]
  for function in functions: functions_map[function.def] = function

  ResolvedUserModule(id: id, name: name, location: location, generics: generics,
      generics_map: generics_map, structs: structs, functions: functions,
      functions_map: functions_map)

proc module_deps*(module: ResolvedUserModule): HashSet[UserModule] =
  var module_set = accumulate_module_deps(module.generics)
  module_set.incl(accumulate_module_deps(module.structs))
  module_set.incl(accumulate_module_deps(module.functions))
  module_set

proc id*(module: ResolvedUserModule): uint64 = module.id
proc location*(module: ResolvedUserModule): Location = module.location
proc name*(module: ResolvedUserModule): Identifier = module.name
proc generics*(module: ResolvedUserModule): seq[
    ResolvedGeneric] = module.generics
proc structs*(module: ResolvedUserModule): seq[ResolvedStruct] = module.structs
proc functions*(module: ResolvedUserModule): seq[
    ResolvedFunction] = module.functions
proc hash*(module: ResolvedUserModule): Hash = module.location.hash
proc `==`*(self: ResolvedUserModule, other: ResolvedUserModule): bool = self.hash == other.hash
proc asl*(module: ResolvedUserModule): string = module.name.asl

proc find_generic*(module: ResolvedUserModule, generic: Generic): Result[
    ResolvedGeneric, string] =
  if generic in module.generics_map:
    ok(module.generics_map[generic])
  else:
    err(fmt"failed to find generic `{generic.name.asl}`")

proc find_function*(module: ResolvedUserModule,
    def: ResolvedUserFunctionDefinition): Result[ResolvedUserFunctionDefinition, string] =
  if def in module.functions_map:
    ok(module.functions_map[def].def)
  else:
    err(fmt"2 - failed to find function `{def.asl}`")

# =============================================================================
# ResolvedNativeModule
# =============================================================================
type ResolvedNativeModule* = ref object of RootObj
  user_module: ResolvedUserModule

proc new_resolved_native_module*(id: uint64, name: Identifier,
    generic_pairs: seq[(Generic, ResolvedGeneric)], structs: seq[
    ResolvedStruct], functions: seq[ResolvedFunction]): ResolvedNativeModule =
  let user_module = new_resolved_user_module(id, name, generic_pairs, structs,
      functions, Location())
  ResolvedNativeModule(user_module: user_module)

proc name*(module: ResolvedNativeModule): Identifier = module.user_module.name
proc generics*(module: ResolvedNativeModule): seq[
    ResolvedGeneric] = module.user_module.generics
proc structs*(module: ResolvedNativeModule): seq[
    ResolvedStruct] = module.user_module.structs
proc functions*(module: ResolvedNativeModule): seq[
    ResolvedFunction] = module.user_module.functions
proc id*(module: ResolvedNativeModule): uint64 = module.user_module.id
proc hash*(module: ResolvedNativeModule): Hash = module.name.hash
proc `==`*(self: ResolvedNativeModule, other: ResolvedNativeModule): bool = self.hash == other.hash
proc asl*(module: ResolvedNativeModule): string = module.name.asl

proc find_generic*(module: ResolvedNativeModule, generic: Generic): Result[
    ResolvedGeneric, string] =
  module.user_module.find_generic(generic)

proc find_function*(module: ResolvedNativeModule,
    def: ResolvedUserFunctionDefinition): Result[ResolvedUserFunctionDefinition, string] =
  module.user_module.find_function(def)

# =============================================================================
# ResolvedModule (Unified Wrapper)
# =============================================================================
type ResolvedModuleKind* = enum
  TMK_NATIVE, TMK_USER

type ResolvedModule* = ref object of RootObj
  case kind: ResolvedModuleKind
  of TMK_NATIVE: native: ResolvedNativeModule
  of TMK_USER: user: ResolvedUserModule

proc new_resolved_module*(module: ResolvedUserModule): ResolvedModule =
  ResolvedModule(kind: TMK_USER, user: module)

proc new_resolved_module*(module: ResolvedNativeModule): ResolvedModule =
  ResolvedModule(kind: TMK_NATIVE, native: module)

proc kind*(module: ResolvedModule): ResolvedModuleKind = module.kind

proc native*(module: ResolvedModule): Result[ResolvedNativeModule, string] =
  case module.kind:
  of TMK_NATIVE: ok(module.native)
  of TMK_USER: err("expected a resolved native module")

proc user*(module: ResolvedModule): Result[ResolvedUserModule, string] =
  case module.kind:
  of TMK_USER: ok(module.user)
  of TMK_NATIVE: err("expected a resolved user module")

proc name*(module: ResolvedModule): Identifier =
  case module.kind:
  of TMK_NATIVE: module.native.name
  of TMK_USER: module.user.name

proc generics*(module: ResolvedModule): seq[ResolvedGeneric] =
  case module.kind:
  of TMK_NATIVE: module.native.generics
  of TMK_USER: module.user.generics

proc structs*(module: ResolvedModule): seq[ResolvedStruct] =
  case module.kind:
  of TMK_NATIVE: module.native.structs
  of TMK_USER: module.user.structs

proc functions*(module: ResolvedModule): seq[ResolvedUserFunctionDefinition] =
  case module.kind:
  of TMK_NATIVE: module.native.functions.map_it(it.def)
  of TMK_USER: module.user.functions.map_it(it.def)

proc module_deps*(module: ResolvedModule): HashSet[UserModule] =
  case module.kind:
  of TMK_NATIVE: init_hashset[UserModule]()
  of TMK_USER: module.user.module_deps

proc resolve*(file: parser.File, module: parser.Module, id: uint64): Result[
    ResolvedModule, string] =
  # Generic resolution
  var resolved_generics: seq[(Generic, ResolvedGeneric)]
  for id, generic in module.generics:
    let resolved_generic = ? resolve(file, some(module), generic, id.uint64)
    resolved_generics.add((generic, resolved_generic))

  var resolved_structs: seq[ResolvedStruct]
  for id, struct in module.structs:
    let resolved_struct = ? resolve(file, module, struct, id.uint64)
    resolved_structs.add(resolved_struct)

  var resolved_functions: seq[ResolvedFunction]
  for function in module.functions:
    let resolved_function = ? resolve(file, module, function)
    resolved_functions.add(resolved_function)

  # TODO: Eliminate un-necessary case block once the ExternFunction is evened out.
  case module.kind:
  of parser.MK_USER:
    let resolved_user = new_resolved_user_module(id, module.name,
        resolved_generics, resolved_structs, resolved_functions,
        module.location)
    ok(new_resolved_module(resolved_user))
  of parser.MK_NATIVE:
    let resolved_native = new_resolved_native_module(id, module.name,
        resolved_generics, resolved_structs, resolved_functions)
    ok(new_resolved_module(resolved_native))
