import results, strformat, tables, options

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
  native_modules: seq[ResolvedNativeModule]
  native_modules_map: Table[NativeModule, ResolvedNativeModule]
  user_modules: seq[ResolvedUserModule]
  user_modules_map: Table[UserModule, ResolvedUserModule]
  modules: seq[ResolvedModule]
  functions: seq[ResolvedUserFunction]

proc new_resolved_file*(name: string, indent: int, maybe_start_def: Option[
    ResolvedUserFunctionDefinition], native_modules: seq[(NativeModule,
        ResolvedModule)], user_modules: seq[ResolvedModule],
    user_modules_map: Table[UserModule, ResolvedModule], functions: seq[
    ResolvedUserFunction]): ResolvedFile =
  var native_modules_map: Table[NativeModule, ResolvedNativeModule]
  var resolved_native_modules: seq[ResolvedNativeModule]
  for (native_module, resolved_module) in native_modules:
    do_assert(resolved_module.kind == TMK_NATIVE, "expected native module")
    let native = resolved_module.native.get
    native_modules_map[native_module] = native
    resolved_native_modules.add(native)
  var resolved_user_modules: seq[ResolvedUserModule]
  for resolved_module in user_modules:
    do_assert(resolved_module.kind == TMK_USER, "expected user module")
    resolved_user_modules.add(resolved_module.user.get)
  var resolved_user_modules_map: Table[UserModule, ResolvedUserModule]
  for user_module in user_modules_map.keys:
    let resolved_module = user_modules_map[user_module]
    do_assert(resolved_module.kind == TMK_USER, "expected user module")
    resolved_user_modules_map[user_module] = resolved_module.user.get

  var modules: seq[ResolvedModule]
  for (native_module, resolved_module) in native_modules:
    modules.add(resolved_module)
  for (user_module, resolved_module) in resolved_user_modules_map.pairs:
    let wrapper = new_resolved_module(resolved_module)
    modules.add(wrapper)

  ResolvedFile(name: name, indent: indent, maybe_start_def: maybe_start_def,
      native_modules: resolved_native_modules,
      native_modules_map: native_modules_map,
      user_modules: resolved_user_modules,
      user_modules_map: resolved_user_modules_map,
      modules: modules, functions: functions)

proc path*(file: ResolvedFile): string = file.name
proc indent*(file: ResolvedFile): int = file.indent
proc start_def*(file: ResolvedFile): Result[ResolvedUserFunctionDefinition, string] =
  case file.maybe_start_def.is_some
  of true: ok(file.maybe_start_def.get)
  of false: err(fmt"{file.path} failed to find `start` function")
proc native_modules*(file: ResolvedFile): seq[
    ResolvedNativeModule] = file.native_modules
proc user_modules*(file: ResolvedFile): seq[
    ResolvedUserModule] = file.user_modules
proc functions*(file: ResolvedFile): seq[ResolvedUserFunction] = file.functions

proc get_resolved_module*(file: ResolvedFile, module: parser.Module): Result[
    ResolvedModule, string] =
  case module.kind:
  of parser.MK_USER:
    let user = module.user_module
    if user in file.user_modules_map:
      ok(new_resolved_module(file.user_modules_map[user]))
    else:
      err("failed to find module `{user.name.asl}`")
  of parser.MK_NATIVE:
    let native = module.native_module
    if native in file.native_modules_map:
      ok(new_resolved_module(file.native_modules_map[native]))
    else:
      err("failed to find native module `{native.name.asl}`")

proc find_module*(file: ResolvedFile, module_name: Identifier): Result[
    ResolvedModule, string] =
  for m, resolved_native in file.native_modules_map.pairs:
    if m.name == module_name:
      return ok(new_resolved_module(resolved_native))
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

proc find_native_module*(file: ResolvedFile, module_name: Identifier): Result[
    ResolvedNativeModule, string] =
  for m, resolved_native in file.native_modules_map.pairs:
    if m.name == module_name:
      return ok(resolved_native)
  err(fmt"{module_name.location} failed to find native module `{module_name.asl}`")

proc find_module*(file: ResolvedFile, module: UserModule): Result[
    ResolvedUserModule, string] =
  if module in file.user_modules_map:
    ok(file.user_modules_map[module])
  else:
    err("failed to find module `{module.name.asl}`")

proc find_module*(file: ResolvedFile, module: NativeModule): Result[
    ResolvedNativeModule, string] =
  if module in file.native_modules_map:
    ok(file.native_modules_map[module])
  else:
    err("failed to find native module `{module.name.asl}`")

proc find_module*(file: ResolvedFile, module: parser.Module): Result[
    ResolvedModule, string] =
  case module.kind:
  of parser.MK_USER:
    let user = module.user_module
    let resolved = ? find_module(file, user)
    ok(new_resolved_module(resolved))
  of parser.MK_NATIVE:
    let native = module.native_module
    let resolved = ? find_module(file, native)
    ok(new_resolved_module(resolved))
