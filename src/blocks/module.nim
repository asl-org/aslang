import strutils, results, strformat

import "../rules"

import common, function

type
  ModuleKind* = enum
    MK_USER, MK_NATIVE
  Module* = ref object of RootObj
    kind: ModuleKind
    def: ModuleDefinition
    fns: seq[Function]
    spaces: int

proc def*(module: Module): ModuleDefinition = module.def
proc fns*(module: Module): seq[Function] = module.fns
proc spaces*(module: Module): int = module.spaces

proc `$`*(module: Module): string =
  var content: seq[string] = @[prefix(module.spaces) & $(module.def)]
  for fn in module.fns:
    content.add($(fn))
  content.join("\n")

proc new_user_module*(def: ModuleDefinition, spaces: int): Module =
  Module(kind: MK_USER, def: def, spaces: spaces)

proc new_native_module*(def: ModuleDefinition): Module =
  Module(kind: MK_NATIVE, def: def, spaces: 0)

# TODO: add duplicate block validation
proc add_fn*(module: Module, new_fn: Function): Result[void, string] =
  for fn in module.fns:
    if fn.match_fn_def(new_fn):
      return err(fmt"Function {new_fn.def} is already defined")
  module.fns.add(new_fn)
  ok()

# TODO: perform final validation
proc close*(module: Module): Result[void, string] =
  if module.fns.len == 0:
    return err(fmt"app block must have at least one function block")
  ok()
