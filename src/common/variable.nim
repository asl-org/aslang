import strformat

import identifier

type Variable* = ref object of RootObj
  name: Identifier
  module: Identifier

proc name*(variable: Variable): Identifier = variable.name
proc module*(variable: Variable): Identifier = variable.module

proc `$`*(variable: Variable): string =
  fmt"{variable.module} {variable.name}"

proc new_variable*(name: Identifier, module: Identifier): Variable =
  Variable(name: name, module: module)

proc new_variable*(name: string, module: string): Variable =
  new_variable(new_identifier(name), new_identifier(module))
