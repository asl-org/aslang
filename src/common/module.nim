import sequtils, strformat, results

import identifier, function, function_def, statement

type ModuleKind* = enum
  MK_NATIVE, MK_ASL

type Module* = ref object of RootObj
  name: Identifier
  case kind: ModuleKind
  of MK_ASL: fns: seq[Function]
  of MK_NATIVE: defs: seq[FunctionDef]

proc name*(module: Module): Identifier = module.name
proc kind*(module: Module): ModuleKind = module.kind

proc `$`*(module: Module): string =
  var acc: string
  case module.kind:
    of MK_NATIVE:
      for def in module.defs: acc.add("  " & $(def) & "\n")
    of MK_ASL:
      for fn in module.fns: acc.add("  " & $(fn) & "\n")
  "module " & $(module.name) & ":\n" & $(acc)

proc new_native_module*(name: Identifier): Module =
  Module(kind: MK_NATIVE, name: name)

proc new_native_module*(name: string): Module =
  new_native_module(new_identifier(name))

proc find_function_def*(module: Module, name: Identifier): Result[FunctionDef, string] =
  let defs =
    case module.kind:
    of MK_NATIVE: module.defs
    of MK_ASL: module.fns.map(proc(x: Function): FunctionDef = x.def)

  for def in defs:
    if def.name == name:
      return ok(def)

  return err(fmt"Module {module.name} does not have any function {name}")

proc add_function*(module: Module, def: FunctionDef, impl: seq[
    Statement] = @[]): Result[Module, string] =
  let maybe_def = module.find_function_def(def.name)
  if maybe_def.is_ok:
    return err(fmt"Function {def} is already defined in scope")

  case module.kind:
  of MK_NATIVE: module.defs.add(def)
  of MK_ASL: module.fns.add(new_function(def, impl))

  ok(module)
