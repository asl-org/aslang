import results, strformat, strutils

import module
import function

import "../rules/parse_result"

proc make_native_module(name: string, fns: seq[(string, string, seq[(
    string, string)])]): Result[Module, string] =
  let native_module = name.new_identifier().new_module_def().new_native_module()

  for (fn_name, returns, args) in fns:
    var arg_defs: seq[ArgumentDefinition]
    for (module, name) in args:
      let arg_def = new_arg_def(new_identifier(module), new_identifier(name))
      arg_defs.add(arg_def)

    let arg_def_list = new_arg_def_list(arg_defs)
    let fn_def = new_fn_def(new_identifier(fn_name), new_identifier(
        returns), arg_def_list)

    ? native_module.add_fn(new_native_function(fn_def))

  return ok(native_module)

type Scope* = ref object of RootObj
  modules: seq[Module]
  native_modules: seq[Module]

proc spaces*(scope: Scope): int = scope.spaces

proc `$`*(scope: Scope): string =
  $(scope.modules[0])

# TODO: add duplicate block validation
proc add_module*(scope: Scope, new_module: Module): Result[void, string] =
  for module in scope.modules:
    if $(new_module.def.name) == $(module.def.name):
      return err(fmt"Module {new_module.def.name} is already defined in the scope")
  scope.modules.add(new_module)
  ok()

# TODO: add duplicate block validation
proc add_native_module*(scope: Scope, new_module: Module): Result[void, string] =
  for module in scope.native_modules:
    if $(new_module.def.name) == $(module.def.name):
      return err(fmt"Module {new_module.def.name} is already defined in the scope")
  scope.native_modules.add(new_module)
  ok()

proc new_scope*(): Result[Scope, string] =
  var scope = Scope()
  let byte_module = ? make_native_module("Byte", @[
    ("print", "Byte", @[("Byte", "value")])
  ])
  ? scope.add_native_module(byte_module)

  let s64_module = ? make_native_module("S64", @[
    ("add", "S64", @[("S64", "a"), ("S64", "b")]),
    ("subtract", "S64", @[("S64", "a"), ("S64", "b")]),
    ("multiply", "S64", @[("S64", "a"), ("S64", "b")]),
    ("quotient", "S64", @[("S64", "a"), ("S64", "b")]),
    ("print", "S64", @[("S64", "a")]),
  ])
  ? scope.add_native_module(s64_module)

  ok(scope)

# TODO: perform final validation
proc close*(scope: Scope): Result[void, string] =
  if scope.modules.len != 1:
    return err(fmt"root block must have an app block")
  ok()

proc find_module(scope: Scope, module_name: Identifier): Result[Module, string] =
  for module in scope.native_modules:
    if $(module.def.name) == $(module_name):
      return ok(module)

  for module in scope.modules:
    if $(module.def.name) == $(module_name):
      return ok(module)

  return err(fmt"{module_name} is not defined in scope")

proc generate_function*(fn: Function, module: Identifier, scope: Scope): Result[
    string, string] =
  var arg_code: seq[string]
  var fn_scope_args: seq[ArgumentDefinition]

  discard ? scope.find_module(fn.def.returns)
  for arg in fn.def.arg_def_list.defs:
    discard ? scope.find_module(arg.module)
    arg_code.add(fmt"{arg.module} {arg.name}")
    fn_scope_args.add(new_arg_def(arg.module, arg.name))

  let arg_code_str = arg_code.join(", ")

  var statements_code: seq[string]
  for index, s in ( ? fn.statements):
    case s.kind:
    of SK_ASSIGNMENT:
      case s.assign.value.kind:
      of VK_INIT:
        let init = s.assign.value.init

        var module_name = init.module_name
        if $(module_name) == "MODULE": module_name = module

        discard ? scope.find_module(init.module_name)
        # TODO: Also make sure that literal value matches with the module/struct definition
        statements_code.add(fmt"{module_name} {s.assign.dest} = {init.literal};")
        # TODO: Look into self assignment from within the function of the same module.
        # Basically ensure that MODULE init does not mess things up
        fn_scope_args.add(new_arg_def(module_name, s.assign.dest))
      of VK_FNCALL:
        let fncall = s.assign.value.fncall
        var module_name: Identifier
        if $(fncall.module_name) == "MODULE": module_name = module
        else: module_name = fncall.module_name

        let fn_module = ? scope.find_module(module_name)
        var fncall_arg_defs: seq[Identifier]
        for arg in fncall.arglist.args:
          var found = false
          for fn_scope_arg in fn_scope_args:
            if $(fn_scope_arg.name) == $(arg):
              found = true
              fncall_arg_defs.add(fn_scope_arg.module)
          if not found:
            return err(fmt"{arg} does not exist in function scope")

        var return_type: Identifier
        var found_signature = false
        for fn in fn_module.fns:
          if $(fn.def.name) != $(fncall.fn_name): continue
          if fncall_arg_defs.len != fn.def.arg_def_list.defs.len: continue
          var args_matched = true
          for index, arg_def in fn.def.arg_def_list.defs:
            let expected_module = arg_def.module
            let actual_module = fncall_arg_defs[index]
            if $(expected_module) != $(actual_module):
              args_matched = false
              break
          if args_matched:
            return_type = fn.def.returns
            found_signature = true
            break

        if not found_signature:
          return err(fmt"Could not find matching signature for {fncall}")

        var fncall_args: seq[string]
        for arg in fncall.arglist.args:
          fncall_args.add($(arg))
        let fncall_args_str = fncall_args.join(", ")
        # TODO: Check the return type of function call in scope, for now using work around
        statements_code.add(fmt"{return_type} {s.assign.dest} = {module_name}_{fncall.fn_name}({fncall_args_str});")
        fn_scope_args.add(new_arg_def(return_type, s.assign.dest))

      # last line must be a return
      if index == ( ? fn.statements).len - 1:
        statements_code.add(fmt"return {s.assign.dest};")
    of SK_FNCALL:
      let fncall = s.fncall

      var fncall_args: seq[string]
      for arg in fncall.arglist.args:
        fncall_args.add($(arg))
      let fncall_args_str = fncall_args.join(", ")

      var module_name = fncall.module_name
      if $(module_name) == "MODULE":
        module_name = module
      var fncall_code = fmt"{module_name}_{fncall.fn_name}({fncall_args_str});"

      # last line must be a return
      if index == ( ? fn.statements).len - 1:
        fncall_code = fmt"return {fncall_code}"

      statements_code.add(fncall_code)

    of SK_IDENTIFIER:
      let arg = s.identifier

      var found = false
      for fn_scope_arg in fn_scope_args:
        if $(fn_scope_arg.name) == $(arg):
          found = true
          break
      if not found:
        return err(fmt"{arg} does not exist in function scope")

      if index == ( ? fn.statements).len - 1:
        statements_code.add(fmt"return {arg};")

  let statements_code_str = statements_code.join("\n")
  let fn_code = @[
    fmt"{fn.def.returns} {module}_{fn.def.name}(" & arg_code_str & ") {",
    fmt"{statements_code_str}",
    "}"
  ]

  ok(fn_code.join("\n"))


proc generate_app*(scope: Scope): Result[string, string] =
  let app = scope.modules[0]
  var fn_code: seq[string]

  for fn in app.fns:
    let fnc = ? fn.generate_function(app.def.name, scope)
    fn_code.add(fnc)
  let fn_code_str = fn_code.join("\n")

  let code = @[
    """
#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
typedef uint8_t Byte;
typedef int64_t S64;

S64 S64_add(S64 a, S64 b)
{
  return a + b;
}

S64 S64_subtract(S64 a, S64 b)
{
  return a - b;
}

S64 S64_multiply(S64 a, S64 b)
{
  return a * b;
}

S64 S64_quotient(S64 a, S64 b)
{
  return a / b;
}

S64 S64_print(S64 value)
{
  return (S64)printf("%lld\n", value);
}

Byte Byte_print(Byte value) {
  return printf("%d\n", value);
}
""",
    fn_code_str,
    "int main(int argc, char** argv) {",
    fmt"return {app.def.name}_start((Byte)argc);",
    "}"
  ]

  ok(code.join("\n"))
