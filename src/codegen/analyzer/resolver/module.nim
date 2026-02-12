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
  parsed_generic: Generic
  defs_repo: Repo[ResolvedFunctionDefinition]
  location: Location

proc new_resolved_generic*(id: uint64, generic: Generic, defs: seq[
    ResolvedFunctionDefinition], location: Location): Result[ResolvedGeneric, string] =
  let maybe_defs_repo = new_repo[ResolvedFunctionDefinition](defs, @[new_index[
      ResolvedFunctionDefinition]("def", hash, true)])
  if maybe_defs_repo.is_err: return err("new_resolved_generic UNREACHABLE")
  ok(ResolvedGeneric(id: id, parsed_generic: generic,
      defs_repo: maybe_defs_repo.get, location: location))

proc id*(generic: ResolvedGeneric): uint64 = generic.id
proc location*(generic: ResolvedGeneric): Location = generic.location
proc parsed_generic*(generic: ResolvedGeneric): Generic = generic.parsed_generic
proc name*(generic: ResolvedGeneric): Identifier = generic.parsed_generic.name
proc defs*(generic: ResolvedGeneric): seq[
    ResolvedFunctionDefinition] = generic.defs_repo.items
proc module_deps*(generic: ResolvedGeneric): HashSet[Module] =
  var module_set: HashSet[Module]
  for def in generic.defs: module_set.incl(def.module_deps)
  module_set
proc hash*(generic: ResolvedGeneric): Hash = generic.location.hash
proc `==`*(self: ResolvedGeneric, other: ResolvedGeneric): bool = self.hash == other.hash
proc asl*(generic: ResolvedGeneric): string = generic.name.asl

proc concrete_defs*(generic: ResolvedGeneric,
    module_ref: ResolvedModuleRef): seq[ResolvedFunctionDefinition] =
  var concrete_defs: seq[ResolvedFunctionDefinition]
  for def in generic.defs:
    let concrete_def = def.concretize(generic.parsed_generic, module_ref)
    concrete_defs.add(concrete_def)
  concrete_defs

proc find_function*(generic: ResolvedGeneric,
    def: ResolvedFunctionDefinition): Result[ResolvedFunctionDefinition, string] =
  let maybe_def = generic.defs_repo.find("def", def.hash)
  if maybe_def.is_ok: ok(maybe_def.get[0])
  else: err(fmt"failed to find function `{def.asl}`")

proc resolve*(file: parser.File, module: Option[parser.Module],
    generic: Generic, id: uint64): Result[ResolvedGeneric, string] =
  var resolved_fndefs: seq[ResolvedFunctionDefinition]
  for def in generic.defs:
    let resolved_fndef = ? resolve(file, module, generic, def)
    resolved_fndefs.add(resolved_fndef)
  new_resolved_generic(id, generic, resolved_fndefs, generic.location)

# =============================================================================
# ResolvedModule
# =============================================================================
type ResolvedModule* = ref object of RootObj
  id: uint64
  parsed_module: Module
  generics_repo: Repo[ResolvedGeneric]
  # structs: seq[ResolvedStruct]
  data: ResolvedData
  functions_repo: Repo[ResolvedFunction]

proc new_resolved_module*(id: uint64, parsed_module: Module, generics: seq[
    ResolvedGeneric], data: ResolvedData, functions: seq[
    ResolvedFunction]): Result[ResolvedModule, string] =
  let maybe_generics_repo = new_repo(generics, @[new_index[ResolvedGeneric](
      "name", parsed_generic, true)])
  if maybe_generics_repo.is_err: return err("new_resolved_module UNREACHABLE")
  let generics_repo = maybe_generics_repo.get

  let maybe_functions_repo = new_repo(functions, @[new_index[ResolvedFunction](
      "def", def, true)])
  if maybe_functions_repo.is_err: return err("new_resolved_module UNREACHABLE")
  let functions_repo = maybe_functions_repo.get

  ok(ResolvedModule(id: id, parsed_module: parsed_module,
      generics_repo: generics_repo, data: data,
      functions_repo: functions_repo))

proc id*(module: ResolvedModule): uint64 = module.id
proc location*(module: ResolvedModule): Location = module.parsed_module.location
proc parsed_module*(module: ResolvedModule): Module = module.parsed_module

proc name*(module: ResolvedModule): Identifier = module.parsed_module.name
proc generics*(module: ResolvedModule): seq[
    ResolvedGeneric] = module.generics_repo.items
# proc structs*(module: ResolvedModule): seq[ResolvedStruct] = module.structs
proc data*(module: ResolvedModule): ResolvedData = module.data
proc functions*(module: ResolvedModule): seq[
    ResolvedFunction] = module.functions_repo.items

proc module_deps*(module: ResolvedModule): HashSet[Module] =
  var module_set: HashSet[Module]
  for generic in module.generics: module_set.incl(generic.module_deps)
  # for struct in module.structs: module_set.incl(struct.module_deps)
  module_set.incl(module.data.module_deps)
  for function in module.functions: module_set.incl(function.module_deps)
  module_set

proc hash*(module: ResolvedModule): Hash = module.location.hash
proc `==`*(self: ResolvedModule, other: ResolvedModule): bool = self.hash == other.hash
proc asl*(module: ResolvedModule): string = module.name.asl

proc find_generic*(module: ResolvedModule, generic: Generic): Result[
    ResolvedGeneric, string] =
  let maybe_generic = module.generics_repo.find("name", generic)
  if maybe_generic.is_ok: return ok(maybe_generic.get[0])
  else: err(fmt"failed to find generic `{generic.name.asl}`")

proc find_function*(module: ResolvedModule,
    def: ResolvedFunctionDefinition): Result[ResolvedFunctionDefinition, string] =
  let maybe_function = module.functions_repo.find("def", def)
  if maybe_function.is_ok: ok(maybe_function.get[0].def)
  else: err(fmt"failed to find function `{def.name.asl}`")

proc resolve*(file: parser.File, module: parser.Module, id: uint64): Result[
    ResolvedModule, string] =
  # Generic resolution
  var resolved_generics: seq[ResolvedGeneric]
  for id, generic in module.generics:
    let resolved_generic = ? resolve(file, some(module), generic, id.uint64)
    resolved_generics.add(resolved_generic)

  let resolved_data = ? resolve(file, module, module.data)

  var resolved_functions: seq[ResolvedFunction]
  for function in module.functions:
    let resolved_function = ? resolve(file, module, function)
    resolved_functions.add(resolved_function)

  # TODO: Eliminate un-necessary case block once the ExternFunction is evened out.
  new_resolved_module(id, module, resolved_generics, resolved_data,
      resolved_functions)
