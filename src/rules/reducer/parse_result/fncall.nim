import strformat

import location
import arglist
import identifier

type FunctionCall* = ref object of RootObj
  module_name: Identifier
  fn_name: Identifier
  arglist: ArgumentList
  location: Location

proc new_fncall*(module_name: Identifier, fn_name: Identifier,
    arglist: ArgumentList): FunctionCall =
  FunctionCall(module_name: module_name, fn_name: fn_name, arglist: arglist)

proc `$`*(fncall: FunctionCall): string =
  fmt"{fncall.module_name}.{fncall.fn_name}{fncall.arglist}"
