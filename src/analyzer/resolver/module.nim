import results, strformat, tables, sets, hashes, options

import parser
import defs
import module_ref
import expression

# =============================================================================
# ResolvedGeneric
# =============================================================================
type ResolvedGeneric* = ref object of RootObj
  id: uint64
  generic: Generic
  defs: seq[ResolvedFunctionDefinition]
  defs_map: Table[ResolvedFunctionDefinition, ResolvedFunctionDefinition]
  location: Location

proc new_resolved_generic*(id: uint64, generic: Generic, defs: seq[
    ResolvedFunctionDefinition], location: Location): ResolvedGeneric =
  var defs_map: Table[ResolvedFunctionDefinition, ResolvedFunctionDefinition]
  for def in defs: defs_map[def] = def
  ResolvedGeneric(id: id, generic: generic, defs: defs, defs_map: defs_map,
      location: location)

proc module_deps*(generic: ResolvedGeneric): HashSet[Module] =
  accumulate_module_deps(generic.defs)

proc id*(generic: ResolvedGeneric): uint64 = generic.id
proc location*(generic: ResolvedGeneric): Location = generic.location
proc name*(generic: ResolvedGeneric): Identifier = generic.generic.name
proc defs*(generic: ResolvedGeneric): seq[
    ResolvedFunctionDefinition] = generic.defs
proc hash*(generic: ResolvedGeneric): Hash = generic.location.hash
proc `==`*(self: ResolvedGeneric, other: ResolvedGeneric): bool = self.hash == other.hash
proc asl*(generic: ResolvedGeneric): string = generic.name.asl

proc concrete_defs*(generic: ResolvedGeneric,
    module_ref: ResolvedModuleRef): seq[ResolvedFunctionDefinition] =
  var concrete_defs: seq[ResolvedFunctionDefinition]
  for def in generic.defs:
    let concrete_def = def.concretize(generic.generic, module_ref)
    concrete_defs.add(concrete_def)
  concrete_defs

proc find_function*(generic: ResolvedGeneric,
    def: ResolvedFunctionDefinition): Result[ResolvedFunctionDefinition, string] =
  if def in generic.defs_map:
    ok(generic.defs_map[def])
  else:
    err(fmt"failed to find function `{def.asl}`")

proc resolve*(file: parser.File, module: Option[parser.Module],
    generic: Generic, id: uint64): Result[ResolvedGeneric, string] =
  var resolved_fndefs: seq[ResolvedFunctionDefinition]
  for def in generic.defs:
    let resolved_fndef = ? resolve(file, module, generic, def)
    resolved_fndefs.add(resolved_fndef)
  ok(new_resolved_generic(id, generic, resolved_fndefs, generic.location))

# =============================================================================
# ResolvedModule
# =============================================================================
type ResolvedModule* = ref object of RootObj
  id: uint64
  name: Identifier
  location: Location
  generics: seq[ResolvedGeneric]
  generics_map: Table[Generic, ResolvedGeneric]
  structs: seq[ResolvedStruct]
  functions_map: Table[ResolvedFunctionDefinition, ResolvedFunction]
  functions: seq[ResolvedFunction]

proc new_resolved_module*(id: uint64, name: Identifier, generic_pairs: seq[
    (Generic, ResolvedGeneric)], structs: seq[ResolvedStruct], functions: seq[
    ResolvedFunction], location: Location): ResolvedModule =
  var generics: seq[ResolvedGeneric]
  var generics_map: Table[Generic, ResolvedGeneric]
  for (generic, resolved_generic) in generic_pairs:
    generics.add(resolved_generic)
    generics_map[generic] = resolved_generic

  var functions_map: Table[ResolvedFunctionDefinition, ResolvedFunction]
  for function in functions: functions_map[function.def] = function

  ResolvedModule(id: id, name: name, location: location, generics: generics,
      generics_map: generics_map, structs: structs, functions: functions,
      functions_map: functions_map)

proc module_deps*(module: ResolvedModule): HashSet[Module] =
  var module_set = accumulate_module_deps(module.generics)
  module_set.incl(accumulate_module_deps(module.structs))
  module_set.incl(accumulate_module_deps(module.functions))
  module_set

proc id*(module: ResolvedModule): uint64 = module.id
proc location*(module: ResolvedModule): Location = module.location
proc name*(module: ResolvedModule): Identifier = module.name
proc generics*(module: ResolvedModule): seq[
    ResolvedGeneric] = module.generics
proc structs*(module: ResolvedModule): seq[ResolvedStruct] = module.structs
proc functions*(module: ResolvedModule): seq[
    ResolvedFunction] = module.functions
proc hash*(module: ResolvedModule): Hash = module.location.hash
proc `==`*(self: ResolvedModule, other: ResolvedModule): bool = self.hash == other.hash
proc asl*(module: ResolvedModule): string = module.name.asl

proc find_generic*(module: ResolvedModule, generic: Generic): Result[
    ResolvedGeneric, string] =
  if generic in module.generics_map:
    ok(module.generics_map[generic])
  else:
    err(fmt"failed to find generic `{generic.name.asl}`")

proc find_function*(module: ResolvedModule,
    def: ResolvedFunctionDefinition): Result[ResolvedFunctionDefinition, string] =
  if def in module.functions_map:
    ok((module.functions_map[def].def))
  else:
    err(fmt"2 - failed to find function `{def.asl}`")

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
  ok(new_resolved_module(id, module.name, resolved_generics,
      resolved_structs, resolved_functions, module.location))
