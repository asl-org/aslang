import strformat

import "../location"
import identifier, argument_list

type Functioncall* = ref object of RootObj
  name: Identifier
  result_var: Identifier
  module: Identifier
  arglist: ArgumentList
  location: Location

proc `$`*(fncall: Functioncall): string =
  fmt"{fncall.result_var} = {fncall.module}.{fncall.name}{fncall.arglist}"

proc name*(fncall: Functioncall): Identifier = fncall.name
proc result_var*(fncall: Functioncall): Identifier = fncall.result_var
proc module*(fncall: Functioncall): Identifier = fncall.module
proc arglist*(fncall: Functioncall): ArgumentList = fncall.arglist

proc c_name*(fncall: Functioncall): string =
  fmt"{fncall.module}_{fncall.name}"

proc new_function_call*(name: Identifier, dest: Identifier, module: Identifier,
    arglist: ArgumentList, location: Location): Functioncall =
  Functioncall(name: name, result_var: dest, module: module, arglist: arglist,
      location: location)
