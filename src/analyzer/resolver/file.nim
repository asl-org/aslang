import results, strformat, tables, options, sequtils

import parser
import module
export module

# =============================================================================
# ResolvedFile
# =============================================================================
type ResolvedFile* = ref object of RootObj
  name: string
  indent: int
  maybe_start_def: Option[ResolvedUserFunctionDefinition]
  user_modules: seq[ResolvedUserModule]
  user_modules_map: Table[Module, ResolvedUserModule]
  modules: seq[ResolvedModule]
  functions: seq[ResolvedUserFunction]

proc new_resolved_file*(name: string, indent: int, maybe_start_def: Option[
    ResolvedUserFunctionDefinition], user_modules: seq[ResolvedModule],
    user_modules_map: Table[Module, ResolvedModule], functions: seq[
    ResolvedUserFunction]): ResolvedFile =
  var resolved_user_modules: seq[ResolvedUserModule]
  for resolved_module in user_modules:
    do_assert(resolved_module.kind == TMK_USER, "expected user module")
    resolved_user_modules.add(resolved_module.user.get)
  var resolved_user_modules_map: Table[Module, ResolvedUserModule]
  for module in user_modules_map.keys:
    let resolved_module = user_modules_map[module]
    do_assert(resolved_module.kind == TMK_USER, "expected user module")
    resolved_user_modules_map[module] = resolved_module.user.get

  var modules: seq[ResolvedModule]
  for (module, resolved_module) in resolved_user_modules_map.pairs:
    let wrapper = new_resolved_module(resolved_module)
    modules.add(wrapper)

  ResolvedFile(name: name, indent: indent, maybe_start_def: maybe_start_def,
      user_modules: resolved_user_modules,
      user_modules_map: resolved_user_modules_map,
      modules: modules, functions: functions)

proc path*(file: ResolvedFile): string = file.name
proc indent*(file: ResolvedFile): int = file.indent
proc start_def*(file: ResolvedFile): Result[ResolvedUserFunctionDefinition, string] =
  case file.maybe_start_def.is_some
  of true: ok(file.maybe_start_def.get)
  of false: err(fmt"{file.path} failed to find `start` function")
proc user_modules*(file: ResolvedFile): seq[
    ResolvedUserModule] = file.user_modules
proc functions*(file: ResolvedFile): seq[
    ResolvedFunction] = file.functions.map_it(new_resolved_function(it))

proc get_resolved_module*(file: ResolvedFile,
    module: parser.Module): Result[ResolvedModule, string] =
  if module in file.user_modules_map:
    ok(new_resolved_module(file.user_modules_map[module]))
  else:
    err("failed to find module `{user.name.asl}`")

proc find_module*(file: ResolvedFile, module_name: Identifier): Result[
    ResolvedModule, string] =
  for m, resolved_user in file.user_modules_map.pairs:
    if m.name == module_name:
      return ok(new_resolved_module(resolved_user))
  err(fmt"{module_name.location} failed to find module `{module_name.asl}`")

proc find_user_module*(file: ResolvedFile, module_name: Identifier): Result[
    ResolvedUserModule, string] =
  for m, resolved_user in file.user_modules_map.pairs:
    if m.name == module_name:
      return ok(resolved_user)
  err(fmt"{module_name.location} failed to find module `{module_name.asl}`")

proc find_module*(file: ResolvedFile, module: Module): Result[
    ResolvedModule, string] =
  if module in file.user_modules_map:
    ok(new_resolved_module(file.user_modules_map[module]))
  else:
    err("failed to find module `{module.name.asl}`")
