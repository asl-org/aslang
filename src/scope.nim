import strformat, results, strutils, options

import grammar/common/main

type Scope = ref object of RootObj
  modules: seq[Module]
  variables: seq[Variable]

proc find_module(scope: Scope, module_name: Identifier): Result[Module, string] =
  for scoped_module in scope.modules:
    if $(scoped_module.name) == $(module_name):
      return ok(scoped_module)
  err(fmt"{module_name} is undefined the scope")

proc add_module(scope: Scope, module: Module): Result[Scope, string] =
  let maybe_module = scope.find_module(module.name)
  if maybe_module.is_ok:
    return err(fmt"{module.name} is already defined in the scope")

  scope.modules.add(module)
  return ok(scope)

proc find_variable(scope: Scope, variable: Identifier): Result[Variable, string] =
  for var_in_scope in scope.variables:
    if $(var_in_scope.name) == $(variable):
      return ok(var_in_scope)
  return err(fmt"{variable} is undefined in the scope")

proc add_variable(scope: Scope, name: Identifier,
    module_ref: Identifier): Result[void, string] =
  let maybe_variable = scope.find_variable(name)
  if maybe_variable.is_ok:
    return err(fmt"{maybe_variable.get} is already defined in the scope.")
  scope.variables.add(new_variable(name, module_ref))
  ok()

proc extract_blocks*(program: Program): Result[Program, string] =
  var scope = Scope()
  let native_modules = ? modules()
  for module in native_modules:
    scope = ? scope.add_module(module)
  for line in program.lines:
    case line.kind:
    of LK_STATEMENT:
      # TODO: ASL only support 2 spaced indentation
      if line.statement.level mod 2 == 1:
        let msg = [
          fmt"Indentation error encounted at {line.statement.location}",
          $(line.statement)
        ].join("\n")
        return err(msg)
    else:
      discard
  ok(program)

proc generate*(program: Program): Result[string, string] =
  var code: seq[string]
  var scope = Scope()
  let native_modules = ? modules()
  for module in native_modules:
    scope = ? scope.add_module(module)

  for line in program.lines:
    case line.kind:
    of LK_STATEMENT:
      let statement = line.statement
      case statement.kind:
      of SK_INITIALIZER:
        let module = ? scope.find_module(statement.init.module)
        case module.kind:
        of MK_NATIVE:
          let value =
            case $(module.name):
            of "S64": ( ? statement.init.literal.as_integer())
            of "F64": ( ? statement.init.literal.as_float())
            else: return err(fmt"Native module {module.name} is not yet supported")

          ? scope.add_variable(statement.init.result_var(),
              statement.init.module)
          code.add(fmt"{module.name} {statement.init.result_var()} = {value};")

        of MK_ASL:
          return err(fmt"ASL Modules are not yet supported.")
      of SK_FUNCTION_CALL:
        let module = ? scope.find_module(statement.fncall.module)
        let def = ? module.find_function_def(statement.fncall.name)

        var return_module: Option[Identifier]
        for sign_index, sign in def.signatures:
          if sign.variables.len != statement.fncall.arglist.arguments.len:
            continue

          var matched = true
          for arg_index, arg in statement.fncall.arglist.arguments:
            case arg.kind:
            of AK_IDENTIFIER:
              let variable = ? scope.find_variable(arg.identifier)
              if variable.module != sign.variables[arg_index].module:
                matched = false
                break
            of AK_LITERAL:
              case arg.literal.kind:
              of NLK_FLOAT:
                let maybe_float = arg.literal.as_float()
                if maybe_float.is_err or $(sign.variables[arg_index].module) != "F64":
                  matched = false
                  break
              of NLK_INTEGER:
                let maybe_integer = arg.literal.as_integer()
                if maybe_integer.is_err or $(sign.variables[
                    arg_index].module) != "S64":
                  matched = false
                  break
              else:
                return err(fmt"Function calls do not yet support string literals yet")

            if matched:
              return_module = some(sign.returns)
        if return_module.is_none:
          return err(fmt"Failed to find matching signatures for the function call {statement.fncall}")

        let result_var = statement.fncall.result_var
        let c_fncall =
          case $(result_var):
          of "_":
            fmt"{statement.fncall.c_name}{statement.fncall.arglist};"
          else:
            ? scope.add_variable(result_var, return_module.get)
            fmt"{return_module.get} {result_var} = {statement.fncall.c_name}{statement.fncall.arglist};"
        code.add(c_fncall)
    else:
      discard

  let c = @[
    "#include \"runtime/asl.h\"",
    "",
    "int main(int argc, char** argv) {",
    code.join("\n"),
    "return 0;",
    "}"
  ].join("\n")

  ok(c)
