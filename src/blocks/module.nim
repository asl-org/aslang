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
proc kind*(module: Module): ModuleKind = module.kind

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
    if fn == new_fn:
      return err(fmt"Function {new_fn.def} is already defined")
  module.fns.add(new_fn)
  ok()

proc find_fn*(module: Module, name: Identifier, arity: int): seq[Function] =
  var matching_fns: seq[Function]
  for fn in module.fns:
    if $(fn.def.name) != $(name): continue
    if fn.def.arg_def_list.len != arity: continue
    matching_fns.add(fn)
  return matching_fns

# TODO: perform final validation
proc close*(module: Module): Result[void, string] =
  if module.fns.len == 0:
    return err(fmt"app block must have at least one function block")
  case module.kind:
  of MK_NATIVE:
    return err(fmt"Something went wrong because an asl module can not be used as native")
  of MK_USER:
    case module.def.kind:
    of MDK_APP: discard
    of MDK_MODULE: discard
    of MDK_STRUCT: discard
    of MDK_UNION: discard
  ok()
