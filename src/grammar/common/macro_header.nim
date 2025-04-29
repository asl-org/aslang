import strformat, strutils, sequtils

import "../location"
import identifier

type FunctionMacro* = ref object of RootObj
  name: Identifier
  returns: Identifier
  location: Location

proc `$`*(fn_macro: FunctionMacro): string =
  fmt"fn {fn_macro.name} returns {fn_macro.returns}"

proc new_fn_macro*(name: Identifier, returns: Identifier,
    location: Location): FunctionMacro =
  FunctionMacro(name: name, returns: returns, location: location)

type ArgumentDef* = ref object of RootObj
  name: Identifier
  module: Identifier
  location: Location

proc `$`*(arg_def: ArgumentDef): string =
  fmt"{arg_def.module} {arg_def.name}"

proc new_args_def*(name: Identifier, module: Identifier,
    location: Location): ArgumentDef =
  ArgumentDef(name: name, module: module, location: location)

type ArgumentDefList* = ref object of RootObj
  arg_defs: seq[ArgumentDef]
  location: Location

proc `$`*(adl: ArgumentDefList): string =
  let arg_defs_str = adl.arg_defs.map(proc(ad: ArgumentDef): string = $(
      ad)).join(", ")
  "(" & arg_defs_str & ")"

proc new_args_def_list*(arg_defs: seq[ArgumentDef],
    location: Location): ArgumentDefList =
  ArgumentDefList(arg_defs: arg_defs, location: location)

type
  MacroHeaderKind = enum
    MHK_FN, MHK_ARGS
  MacroHeader* = ref object of RootObj
    case kind: MacroHeaderKind
    of MHK_FN: fn_macro: FunctionMacro
    of MHK_ARGS: args_macro: ArgumentDefList

proc `$`*(macro_header: MacroHeader): string =
  case macro_header.kind:
  of MHK_FN: $(macro_header.fn_macro)
  of MHK_ARGS: $(macro_header.args_macro)

proc new_fn_macro_header*(fn_macro: FunctionMacro): MacroHeader =
  MacroHeader(kind: MHK_FN, fn_macro: fn_macro)

proc new_args_macro_header*(args_macro: ArgumentDefList): MacroHeader =
  MacroHeader(kind: MHK_ARGS, args_macro: args_macro)
