import strformat, results, strutils

import common

type Variable = ref object of RootObj
  name: Identifier
  module: Identifier

proc `$`*(variable: Variable): string =
  fmt"{variable.module} {variable.name}"

proc new_variable(name: Identifier, module: Identifier): Variable =
  Variable(name: name, module: module)

type FunctionDefinition = ref object of RootObj
  variables: seq[Variable]

type FunctionImpl = ref object of RootObj
  def: FunctionDefinition
  statements: seq[Statement]

type FunctionKind = enum
  FK_BUILTIN, FK_ASL

type Function = ref object of RootObj
  name: Identifier
  returns: Identifier
  case kind: FunctionKind
  of FK_BUILTIN: defs: seq[FunctionDefinition]
  of FK_ASL: impls: seq[FunctionImpl]

type Module = ref object of RootObj
  name: Identifier
  functions: seq[Function]

type Scope = ref object of RootObj
  modules: seq[Module]
  variables: seq[Variable]

proc find_module(scope: Scope, module_name: Identifier): Result[Module, string] =
  for scoped_module in scope.modules:
    if $(scoped_module.name) == $(module_name):
      return ok(scoped_module)
  err(fmt"{module_name} is undefined the scope")

proc add_module(scope: Scope, module: Module): Result[void, string] =
  let maybe_module = scope.find_module(module.name)
  if maybe_module.is_ok:
    return err(fmt"{module.name} is already defined in the scope")

  scope.modules.add(module)
  return ok()

proc find_variable(scope: Scope, variable: Identifier): Result[Variable, string] =
  for var_in_scope in scope.variables:
    if $(var_in_scope.name) == $(variable):
      return ok(var_in_scope)
  return err(fmt"{variable} already exists in the scope")

proc add_variable(scope: Scope, name: Identifier,
    module_ref: Identifier): Result[void, string] =
  let maybe_variable = scope.find_variable(name)
  if maybe_variable.is_ok:
    return err(fmt"{maybe_variable.get} is already defined in the scope.")
  scope.variables.add(new_variable(name, module_ref))
  ok()

proc s64_module(): Module =
  Module(name: new_identifier("S64"), functions: @[])

proc f64_module(): Module =
  Module(name: new_identifier("F64"), functions: @[])

proc generate*(program: Program): Result[string, string] =
  var code: seq[string]
  var scope = Scope()
  ? scope.add_module(s64_module())
  ? scope.add_module(f64_module())

  for statement in program.statements:
    case statement.kind:
    of SK_INITIALIZER:
      let module = ? scope.find_module(statement.init.module)
      ? scope.add_variable(statement.init.result, statement.init.module)
      code.add(fmt"{statement.init.module} {statement.init.result} = {statement.init.struct.kwargs[0].value};")
    of SK_FUNCTION_CALL:
      let c_fncall =
        case $(statement.fncall.result):
        of "_":
          fmt"{statement.fncall.c_name}{statement.fncall.arglist};"
        else:
          fmt"{statement.fncall.result} = {statement.fncall.c_name}{statement.fncall.arglist};"
      code.add(c_fncall)

  let c = @[
    "#include \"runtime/asl.h\"",
    "",
    "int main(int argc, char** argv) {",
    code.join("\n"),
    "return 0;",
    "}"
  ].join("\n")

  ok(c)
