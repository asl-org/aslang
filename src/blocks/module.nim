import results, strformat, sequtils, options

import token

import module/[module_def, builtin_module, user_module]
export module_def, builtin_module, user_module

import struct, function

type
  ModuleKind* = enum
    MK_BUILTIN, MK_USER
  Module* = ref object of RootObj
    case kind*: ModuleKind
    of MK_BUILTIN: builtin_mod*: BuiltinModule
    of MK_USER: user_mod*: UserModule

proc location*(module: Module): Location =
  case module.kind:
  of MK_BUILTIN: module.builtin_mod.location
  of MK_USER: module.user_mod.location

proc name*(module: Module): Token =
  case module.kind:
  of MK_BUILTIN: module.builtin_mod.name
  of MK_USER: module.user_mod.name

proc is_struct*(module: Module): bool =
  case module.kind:
  of MK_BUILTIN: false
  of MK_USER: module.user_mod.is_struct

proc struct*(module: Module): Struct = module.user_mod.struct.get

proc function_defs*(module: Module): seq[FunctionDefinition] =
  case module.kind:
  of MK_BUILTIN: module.builtin_mod.functions
  of MK_USER: module.user_mod.functions.map_it(it.definition)

proc functions*(module: Module): seq[Function] =
  module.user_mod.functions

proc `$`*(module: Module): string =
  case module.kind:
  of MK_BUILTIN: $(module.builtin_mod)
  of MK_USER: $(module.user_mod)

proc new_module*(builtin_mod: BuiltinModule): Module =
  Module(kind: MK_BUILTIN, builtin_mod: builtin_mod)

proc new_module*(module_def: ModuleDefinition): Module =
  Module(kind: MK_USER, user_mod: new_user_module(module_def))

proc add_function*(module: Module, function: Function): Result[void, string] =
  case module.kind:
  of MK_BUILTIN:
    # NOTE: This error indicates that there is an error in blockification logic
    err(fmt"Module `{module.name}` is a builtin module therefore function can not be added.")
  of MK_USER:
    # TODO: Check for duplicate function signature
    ? module.user_mod.add_function(function)
    ok()

proc add_struct*(module: Module, struct: Struct): Result[void, string] =
  case module.kind:
  of MK_BUILTIN:
    # NOTE: This error indicates that there is an error in blockification logic
    err(fmt"Module `{module.name}` is a builtin module therefore struct can not be added.")
  of MK_USER:
    # TODO: Check for multiple struct blocks
    ? module.user_mod.add_struct(struct)
    ok()

proc close*(module: Module): Result[void, string] =
  case module.kind:
  of MK_BUILTIN:
    # NOTE: This error indicates that there is an error in blockification logic
    err(fmt"Module `{module.name}` is a builtin module and is already closed.")
  of MK_USER:
    if module.user_mod.functions.len == 0 and (not module.user_mod.is_struct):
      err(fmt"{module.location} Module `{module.name}` must contain at least one function.")
    else:
      ok()
