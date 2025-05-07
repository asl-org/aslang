import strformat

import arglist

type FunctionCall* = ref object of RootObj
  module_name: string
  fn_name: string
  arglist: ArgumentList

proc new_fncall*(module_name: string, fn_name: string,
    arglist: ArgumentList): FunctionCall =
  FunctionCall(module_name: module_name, fn_name: fn_name, arglist: arglist)

proc `$`*(fncall: FunctionCall): string =
  fmt"{fncall.module_name}.{fncall.fn_name}{fncall.arglist}"
