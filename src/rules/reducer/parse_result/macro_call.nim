import strformat, strutils, sequtils

type ArgumentDefintion* = ref object of RootObj
  module: string
  name: string

proc new_arg_def*(module: string, name: string): ArgumentDefintion =
  ArgumentDefintion(module: module, name: name)

proc `$`*(arg_def: ArgumentDefintion): string =
  fmt"{arg_def.module} {arg_def.name}"

type ArgumentDefintionList* = ref object of RootObj
  defs: seq[ArgumentDefintion]

proc new_arg_def_list*(defs: seq[ArgumentDefintion]): ArgumentDefintionList =
  ArgumentDefintionList(defs: defs)

proc `$`*(arg_def_list: ArgumentDefintionList): string =
  let defs = arg_def_list.defs.map(proc(x: ArgumentDefintion): string = $(
      x)).join(", ")
  "args(" & defs & "):"

type FunctionMacro* = ref object of RootObj
  name: string
  returns: string

proc new_fn_macro*(name: string, returns: string): FunctionMacro =
  FunctionMacro(name: name, returns: returns)

proc `$`*(fn_macro: FunctionMacro): string =
  fmt"function {fn_macro.name} returns {fn_macro.returns}:"

type AppMacro* = ref object of RootObj
  name: string

proc new_app_macro*(name: string): AppMacro =
  AppMacro(name: name)

proc `$`*(app_macro: AppMacro): string =
  fmt"app {app_macro.name}:"

type
  MacroCallKind = enum
    MCK_FN, MCK_ARGS, MCK_APP
  MacroCall* = ref object of RootObj
    case kind: MacroCallKind
    of MCK_FN: fn_macro: FunctionMacro
    of MCK_ARGS: arg_def_list: ArgumentDefintionList
    of MCK_APP: app_macro: AppMacro

proc new_macro_call*(fn_macro: FunctionMacro): MacroCall =
  MacroCall(kind: MCK_FN, fn_macro: fn_macro)

proc new_macro_call*(arg_def_list: ArgumentDefintionList): MacroCall =
  MacroCall(kind: MCK_ARGS, arg_def_list: arg_def_list)

proc new_macro_call*(app_macro: AppMacro): MacroCall =
  MacroCall(kind: MCK_APP, app_macro: app_macro)

proc `$`*(macro_call: MacroCall): string =
  case macro_call.kind:
  of MCK_FN: $(macro_call.fn_macro)
  of MCK_ARGS: $(macro_call.arg_def_list)
  of MCK_APP: $(macro_call.app_macro)
