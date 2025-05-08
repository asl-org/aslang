import strformat, strutils, sequtils, results

import location
import identifier

type ArgumentDefintion* = ref object of RootObj
  module: Identifier
  name: Identifier
  location: Location

proc new_arg_def*(module: Identifier, name: Identifier): ArgumentDefintion =
  ArgumentDefintion(module: module, name: name)

proc `$`*(arg_def: ArgumentDefintion): string =
  fmt"{arg_def.module} {arg_def.name}"

type ArgumentDefintionList* = ref object of RootObj
  defs: seq[ArgumentDefintion]
  location: Location

proc defs*(arg_def_list: ArgumentDefintionList): seq[
    ArgumentDefintion] = arg_def_list.defs

proc new_arg_def_list*(defs: seq[ArgumentDefintion]): ArgumentDefintionList =
  ArgumentDefintionList(defs: defs)

proc `$`*(arg_def_list: ArgumentDefintionList): string =
  let defs = arg_def_list.defs.map(proc(x: ArgumentDefintion): string = $(
      x)).join(", ")
  "args(" & defs & "):"

type FunctionMacro* = ref object of RootObj
  name: Identifier
  returns: Identifier
  location: Location

proc name*(fn_macro: FunctionMacro): Identifier = fn_macro.name
proc returns*(fn_macro: FunctionMacro): Identifier = fn_macro.returns

proc new_fn_macro*(name: Identifier, returns: Identifier): FunctionMacro =
  FunctionMacro(name: name, returns: returns)

proc `$`*(fn_macro: FunctionMacro): string =
  fmt"function {fn_macro.name} returns {fn_macro.returns}:"

type AppMacro* = ref object of RootObj
  name: Identifier
  location: Location

proc name*(app_macro: AppMacro): Identifier = app_macro.name

proc new_app_macro*(name: Identifier): AppMacro =
  AppMacro(name: name)

proc `$`*(app_macro: AppMacro): string =
  fmt"app {app_macro.name}:"

type
  MacroCallKind* = enum
    MCK_FN, MCK_ARGS, MCK_APP
  MacroCall* = ref object of RootObj
    case kind: MacroCallKind
    of MCK_FN: fn_macro: FunctionMacro
    of MCK_ARGS: arg_def_list: ArgumentDefintionList
    of MCK_APP: app_macro: AppMacro

proc `$`*(macro_call: MacroCall): string =
  case macro_call.kind:
  of MCK_FN: $(macro_call.fn_macro)
  of MCK_ARGS: $(macro_call.arg_def_list)
  of MCK_APP: $(macro_call.app_macro)

proc kind*(macro_call: MacroCall): MacroCallKind = macro_call.kind
proc app_macro*(macro_call: MacroCall): AppMacro = macro_call.app_macro
proc fn_macro*(macro_call: MacroCall): FunctionMacro = macro_call.fn_macro
proc arg_def_list*(macro_call: MacroCall): ArgumentDefintionList = macro_call.arg_def_list

proc safe_app_macro*(macro_call: MacroCall): Result[AppMacro, string] =
  case macro_call.kind:
  of MCK_APP: ok(macro_call.app_macro)
  else: return err(fmt"Macro {macro_call} is not an app macro")

proc safe_fn_macro*(macro_call: MacroCall): Result[FunctionMacro, string] =
  case macro_call.kind:
  of MCK_FN: ok(macro_call.fn_macro)
  else: return err(fmt"Macro {macro_call} is not an app macro")

proc safe_args_macro*(macro_call: MacroCall): Result[ArgumentDefintionList, string] =
  case macro_call.kind:
  of MCK_ARGS: ok(macro_call.arg_def_list)
  else: return err(fmt"Macro {macro_call} is not an app macro")

proc new_macro_call*(fn_macro: FunctionMacro): MacroCall =
  MacroCall(kind: MCK_FN, fn_macro: fn_macro)

proc new_macro_call*(arg_def_list: ArgumentDefintionList): MacroCall =
  MacroCall(kind: MCK_ARGS, arg_def_list: arg_def_list)

proc new_macro_call*(app_macro: AppMacro): MacroCall =
  MacroCall(kind: MCK_APP, app_macro: app_macro)
