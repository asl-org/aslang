import results, strformat, tables, sets, hashes, sequtils

import parser
import typed_expr
export typed_expr

# =============================================================================
# TypedGeneric
# =============================================================================
type TypedGeneric* = ref object of RootObj
  id: uint64
  generic: Generic
  defs: seq[TypedFunctionDefinition]
  defs_map: Table[TypedFunctionDefinition, TypedFunctionDefinition]
  location: Location

proc new_typed_generic*(id: uint64, generic: Generic, defs: seq[
    TypedFunctionDefinition], location: Location): TypedGeneric =
  var defs_map: Table[TypedFunctionDefinition, TypedFunctionDefinition]
  for def in defs: defs_map[def] = def
  TypedGeneric(id: id, generic: generic, defs: defs, defs_map: defs_map,
      location: location)

proc module_deps*(generic: TypedGeneric): HashSet[UserModule] =
  accumulate_module_deps(generic.defs)

proc id*(generic: TypedGeneric): uint64 = generic.id
proc location*(generic: TypedGeneric): Location = generic.location
proc name*(generic: TypedGeneric): Identifier = generic.generic.name
proc defs*(generic: TypedGeneric): seq[TypedFunctionDefinition] = generic.defs
proc hash*(generic: TypedGeneric): Hash = generic.location.hash
proc `==`*(self: TypedGeneric, other: TypedGeneric): bool = self.hash == other.hash
proc asl*(generic: TypedGeneric): string = generic.name.asl

proc concrete_defs*(generic: TypedGeneric, module_ref: TypedModuleRef): seq[
    TypedFunctionDefinition] =
  var concrete_defs: seq[TypedFunctionDefinition]
  for def in generic.defs:
    let concrete_def = def.concretize(generic.generic, module_ref)
    concrete_defs.add(concrete_def)
  concrete_defs

proc find_function*(generic: TypedGeneric,
    def: TypedFunctionDefinition): Result[TypedFunctionDefinition, string] =
  if def in generic.defs_map:
    ok(generic.defs_map[def])
  else:
    err(fmt"failed to find function `{def.asl}`")

# =============================================================================
# TypedUserModule
# =============================================================================
type TypedUserModule* = ref object of RootObj
  id: uint64
  name: Identifier
  location: Location
  generics: seq[TypedGeneric]
  generics_map: Table[Generic, TypedGeneric]
  structs: seq[TypedStruct]
  functions_map: Table[TypedFunctionDefinition, TypedFunction]
  functions: seq[TypedFunction]
  internal_functions_map: Table[TypedFunctionDefinition, TypedFunctionDefinition]

proc new_typed_user_module*(id: uint64, name: Identifier, generic_pairs: seq[(
    Generic, TypedGeneric)], structs: seq[TypedStruct], functions: seq[
    TypedFunction], internal_functions: seq[TypedFunctionDefinition],
    location: Location): TypedUserModule =
  var generics: seq[TypedGeneric]
  var generics_map: Table[Generic, TypedGeneric]
  for (generic, typed_generic) in generic_pairs:
    generics.add(typed_generic)
    generics_map[generic] = typed_generic

  var functions_map: Table[TypedFunctionDefinition, TypedFunction]
  for function in functions: functions_map[function.def] = function

  var internal_functions_map: Table[TypedFunctionDefinition, TypedFunctionDefinition]
  for internal_function in internal_functions:
    internal_functions_map[internal_function] = internal_function

  TypedUserModule(id: id, name: name, location: location, generics: generics,
      generics_map: generics_map, structs: structs, functions: functions,
      functions_map: functions_map, internal_functions_map: internal_functions_map)

proc module_deps*(module: TypedUserModule): HashSet[UserModule] =
  var module_set = accumulate_module_deps(module.generics)
  module_set.incl(accumulate_module_deps(module.structs))
  module_set.incl(accumulate_module_deps(module.functions))
  module_set

proc id*(module: TypedUserModule): uint64 = module.id
proc location*(module: TypedUserModule): Location = module.location
proc name*(module: TypedUserModule): Identifier = module.name
proc generics*(module: TypedUserModule): seq[TypedGeneric] = module.generics
proc structs*(module: TypedUserModule): seq[TypedStruct] = module.structs
proc functions*(module: TypedUserModule): seq[TypedFunction] = module.functions
proc hash*(module: TypedUserModule): Hash = module.location.hash
proc `==`*(self: TypedUserModule, other: TypedUserModule): bool = self.hash == other.hash
proc asl*(module: TypedUserModule): string = module.name.asl

proc find_generic*(module: TypedUserModule, generic: Generic): Result[
    TypedGeneric, string] =
  if generic in module.generics_map:
    ok(module.generics_map[generic])
  else:
    err(fmt"failed to find generic `{generic.name.asl}`")

proc find_function*(module: TypedUserModule,
    def: TypedFunctionDefinition): Result[TypedFunctionDefinition, string] =
  if def in module.functions_map:
    ok(module.functions_map[def].def)
  elif def in module.internal_functions_map:
    ok(module.internal_functions_map[def])
  else:
    err(fmt"2 - failed to find function `{def.asl}`")

# =============================================================================
# TypedNativeFunction
# =============================================================================
type TypedNativeFunction* = ref object of RootObj
  native: string
  def: TypedFunctionDefinition

proc new_typed_native_function*(native: string,
    def: TypedFunctionDefinition): TypedNativeFunction =
  TypedNativeFunction(native: native, def: def)

proc native*(function: TypedNativeFunction): string = function.native
proc def*(function: TypedNativeFunction): TypedFunctionDefinition = function.def

# =============================================================================
# TypedNativeModule
# =============================================================================
type TypedNativeModule* = ref object of RootObj
  id: uint64
  name: Identifier
  generics: seq[TypedGeneric]
  generics_map: Table[Generic, TypedGeneric]
  structs: seq[TypedStruct]
  functions: seq[TypedNativeFunction]
  functions_map: Table[TypedFunctionDefinition, TypedNativeFunction]

proc new_typed_native_module*(name: Identifier, generic_pairs: seq[(Generic,
    TypedGeneric)], structs: seq[TypedStruct], functions: seq[
        TypedNativeFunction],
    id: uint64): TypedNativeModule =
  var generics: seq[TypedGeneric]
  var generics_map: Table[Generic, TypedGeneric]
  for (generic, typed_generic) in generic_pairs:
    generics.add(typed_generic)
    generics_map[generic] = typed_generic

  var functions_map: Table[TypedFunctionDefinition, TypedNativeFunction]
  for function in functions: functions_map[function.def] = function
  TypedNativeModule(id: id, name: name, generics: generics, structs: structs,
      generics_map: generics_map, functions: functions,
      functions_map: functions_map)

proc name*(module: TypedNativeModule): Identifier = module.name
proc generics*(module: TypedNativeModule): seq[TypedGeneric] = module.generics
proc structs*(module: TypedNativeModule): seq[TypedStruct] = module.structs
proc functions*(module: TypedNativeModule): seq[TypedNativeFunction] = module.functions
proc id*(module: TypedNativeModule): uint64 = module.id
proc hash*(module: TypedNativeModule): Hash = module.name.hash
proc `==`*(self: TypedNativeModule, other: TypedNativeModule): bool = self.hash == other.hash
proc asl*(module: TypedNativeModule): string = module.name.asl

proc find_generic*(module: TypedNativeModule, generic: Generic): Result[
    TypedGeneric, string] =
  if generic in module.generics_map:
    ok(module.generics_map[generic])
  else:
    err(fmt"failed to find generic `{generic.name.asl}`")

proc find_function*(module: TypedNativeModule,
    def: TypedFunctionDefinition): Result[TypedFunctionDefinition, string] =
  if def in module.functions_map:
    ok(module.functions_map[def].def)
  else:
    err(fmt"failed to find function `{def.asl}`")

# =============================================================================
# TypedModule (Unified Wrapper)
# =============================================================================
type TypedModuleKind* = enum
  TMK_NATIVE, TMK_USER

type TypedModule* = ref object of RootObj
  case kind: TypedModuleKind
  of TMK_NATIVE: native: TypedNativeModule
  of TMK_USER: user: TypedUserModule

proc new_typed_module*(module: TypedUserModule): TypedModule =
  TypedModule(kind: TMK_USER, user: module)

proc new_typed_module*(module: TypedNativeModule): TypedModule =
  TypedModule(kind: TMK_NATIVE, native: module)

proc kind*(module: TypedModule): TypedModuleKind = module.kind

proc native*(module: TypedModule): Result[TypedNativeModule, string] =
  case module.kind:
  of TMK_NATIVE: ok(module.native)
  of TMK_USER: err("expected a typed native module")

proc user*(module: TypedModule): Result[TypedUserModule, string] =
  case module.kind:
  of TMK_USER: ok(module.user)
  of TMK_NATIVE: err("expected a typed user module")

proc name*(module: TypedModule): Identifier =
  case module.kind:
  of TMK_NATIVE: module.native.name
  of TMK_USER: module.user.name

proc generics*(module: TypedModule): seq[TypedGeneric] =
  case module.kind:
  of TMK_NATIVE: module.native.generics
  of TMK_USER: module.user.generics

proc structs*(module: TypedModule): seq[TypedStruct] =
  case module.kind:
  of TMK_NATIVE: module.native.structs
  of TMK_USER: module.user.structs

proc functions*(module: TypedModule): seq[TypedFunctionDefinition] =
  case module.kind:
  of TMK_NATIVE: module.native.functions.map_it(it.def)
  of TMK_USER: module.user.functions.map_it(it.def)

proc module_deps*(module: TypedModule): HashSet[UserModule] =
  case module.kind:
  of TMK_NATIVE: init_hashset[UserModule]()
  of TMK_USER: module.user.module_deps
