import results, strformat, tables, options

import parser
import typed_module
export typed_module

# =============================================================================
# TypedFile
# =============================================================================
type TypedFile* = ref object of RootObj
  name: string
  indent: int
  maybe_start_def: Option[TypedFunctionDefinition]
  native_modules: seq[TypedNativeModule]
  native_modules_map: Table[NativeModule, TypedNativeModule]
  user_modules: seq[TypedUserModule]
  user_modules_map: Table[UserModule, TypedUserModule]
  modules: seq[TypedModule]
  functions: seq[TypedFunction]

proc new_typed_file*(name: string, indent: int, maybe_start_def: Option[
    TypedFunctionDefinition], native_modules: seq[(NativeModule,
        TypedModule)], user_modules: seq[TypedModule],
    user_modules_map: Table[UserModule, TypedModule], functions: seq[
    TypedFunction]): TypedFile =
  var native_modules_map: Table[NativeModule, TypedNativeModule]
  var typed_native_modules: seq[TypedNativeModule]
  for (native_module, typed_module) in native_modules:
    do_assert(typed_module.kind == TMK_NATIVE, "expected native module")
    let native = typed_module.native.get
    native_modules_map[native_module] = native
    typed_native_modules.add(native)
  var typed_user_modules: seq[TypedUserModule]
  for typed_module in user_modules:
    do_assert(typed_module.kind == TMK_USER, "expected user module")
    typed_user_modules.add(typed_module.user.get)
  var typed_user_modules_map: Table[UserModule, TypedUserModule]
  for user_module in user_modules_map.keys:
    let typed_module = user_modules_map[user_module]
    do_assert(typed_module.kind == TMK_USER, "expected user module")
    typed_user_modules_map[user_module] = typed_module.user.get

  var modules: seq[TypedModule]
  for (native_module, typed_module) in native_modules:
    modules.add(typed_module)
  for (user_module, typed_module) in typed_user_modules_map.pairs:
    let wrapper = new_typed_module(typed_module)
    modules.add(wrapper)

  TypedFile(name: name, indent: indent, maybe_start_def: maybe_start_def,
      native_modules: typed_native_modules,
      native_modules_map: native_modules_map,
      user_modules: typed_user_modules, user_modules_map: typed_user_modules_map,
      modules: modules, functions: functions)

proc path*(file: TypedFile): string = file.name
proc indent*(file: TypedFile): int = file.indent
proc start_def*(file: TypedFile): Result[TypedFunctionDefinition, string] =
  case file.maybe_start_def.is_some
  of true: ok(file.maybe_start_def.get)
  of false: err(fmt"{file.path} failed to find `start` function")
proc native_modules*(file: TypedFile): seq[
    TypedNativeModule] = file.native_modules
proc user_modules*(file: TypedFile): seq[TypedUserModule] = file.user_modules
proc functions*(file: TypedFile): seq[TypedFunction] = file.functions

proc get_typed_module*(file: TypedFile, module: parser.Module): Result[
    TypedModule, string] =
  case module.kind:
  of parser.MK_USER:
    let user = ? module.user_module
    if user in file.user_modules_map:
      ok(new_typed_module(file.user_modules_map[user]))
    else:
      err("failed to find module `{user.name.asl}`")
  of parser.MK_NATIVE:
    let native = ? module.native_module
    if native in file.native_modules_map:
      ok(new_typed_module(file.native_modules_map[native]))
    else:
      err("failed to find native module `{native.name.asl}`")

proc find_module*(file: TypedFile, module_name: Identifier): Result[
    TypedModule, string] =
  for m, typed_native in file.native_modules_map.pairs:
    if m.name == module_name:
      return ok(new_typed_module(typed_native))
  for m, typed_user in file.user_modules_map.pairs:
    if m.name == module_name:
      return ok(new_typed_module(typed_user))
  err(fmt"{module_name.location} failed to find module `{module_name.asl}`")

proc find_user_module*(file: TypedFile, module_name: Identifier): Result[
    TypedUserModule, string] =
  for m, typed_user in file.user_modules_map.pairs:
    if m.name == module_name:
      return ok(typed_user)
  err(fmt"{module_name.location} failed to find module `{module_name.asl}`")

proc find_native_module*(file: TypedFile, module_name: Identifier): Result[
    TypedNativeModule, string] =
  for m, typed_native in file.native_modules_map.pairs:
    if m.name == module_name:
      return ok(typed_native)
  err(fmt"{module_name.location} failed to find native module `{module_name.asl}`")

proc find_module*(file: TypedFile, module: UserModule): Result[
    TypedUserModule, string] =
  if module in file.user_modules_map:
    ok(file.user_modules_map[module])
  else:
    err("failed to find module `{module.name.asl}`")

proc find_module*(file: TypedFile, module: NativeModule): Result[
    TypedNativeModule, string] =
  if module in file.native_modules_map:
    ok(file.native_modules_map[module])
  else:
    err("failed to find native module `{module.name.asl}`")

proc find_module*(file: TypedFile, module: parser.Module): Result[
    TypedModule, string] =
  case module.kind:
  of parser.MK_USER:
    let user = ? module.user_module
    let typed = ? find_module(file, user)
    ok(new_typed_module(typed))
  of parser.MK_NATIVE:
    let native = ? module.native_module
    let typed = ? find_module(file, native)
    ok(new_typed_module(typed))
