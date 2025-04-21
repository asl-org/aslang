import os, results, sequtils

import common
import grammar
import parser
import transformer

type Variable = ref object of RootObj
  name: Identifier
  module: ModuleRef

proc new_variable(name: Identifier, module: ModuleRef): Variable =
  Variable(name: name, module: module)

proc new_variable(name: string, module: string): Variable =
  new_variable(new_identifier(name), new_module_ref(@[module]))

type FunctionDefinition = ref object of RootObj
  variables: seq[Variable]

proc new_function_definition(variables: seq[Variable]): FunctionDefinition =
  FunctionDefinition(variables: variables)

proc new_function_definition(args: seq[(string, string)]): FunctionDefinition =
  args
    .map(proc(arg: (string, string)): Variable = new_variable(arg[0], arg[1]))
    .new_function_definition()

type FunctionImpl = ref object of RootObj
  def: FunctionDefinition
  statements: seq[Statement]

type FunctionKind = enum
  FK_BUILTIN, FK_ASL

type Function = ref object of RootObj
  name: Identifier
  returns: ModuleRef
  case kind: FunctionKind
  of FK_BUILTIN: defs: seq[FunctionDefinition]
  of FK_ASL: impls: seq[FunctionImpl]

proc new_builtin_function(name: Identifier, returns: ModuleRef, defs: seq[
    FunctionDefinition]): Function =
  Function(kind: FK_BUILTIN, name: name, returns: returns, defs: defs)

proc new_builtin_function(name, returns: string, defs: seq[seq[(string,
    string)]]): Function =
  var func_defs = defs.map(new_function_definition)
  new_builtin_function(new_identifier(name), new_module_ref(@[returns]), func_defs)

type Module = ref object of RootObj
  name: Identifier
  functions: seq[Function]

proc new_module(name: Identifier): Module = Module(name: name)
proc new_module(name: string): Module = new_module(new_identifier(name))

proc add_function(module: Module, fn: Function): void = module.functions.add(fn)

proc builtin_modules(): seq[Module] =
  let sys_module = new_module("System")
  sys_module.add_function(new_builtin_function(
    "unsafe_print", "S64", @[@[("value", "S64")], @[("value", "F64")]]))

  let s64_module = new_module("S64")
  s64_module.add_function(new_builtin_function("init", "S64", @[@[("value", "S64")]]))

  let f64_module = new_module("F64")
  f64_module.add_function(new_builtin_function("init", "F64", @[@[("value", "F64")]]))

  return @[sys_module, s64_module, f64_module]

type Scope = ref object of RootObj
  modules: seq[Module]
  variables: seq[Variable]

proc add_module(scope: Scope, module: Module): void = scope.modules.add(module)
proc add_variable(scope: Scope, variable: Variable): void = scope.variables.add(variable)

proc builtin_scope(): Scope =
  var scope = Scope()
  for module in builtin_modules():
    scope.add_module(module)

proc generate(program: Program): Result[string, string] =
  var scope = builtin_scope()
  for statement in program.statements:
    case statement.kind:
    of SK_INITIALIZER: echo statement.init
    of SK_FUNCTION_CALL: echo statement.fncall
  ok("")

proc write_c_file(code: string, filename: string): Result[void, string] =
  try: write_file(filename, code); ok()
  except OSError: err("An error occurred while trying to create the file")

proc compile(filename: string): Result[void, string] =
  let parse_result = ? rules.parse(filename, "program")
  let code = ? parse_result.program.generate
  code.write_c_file("asl.c")

when is_main_module:
  let maybe_compiled = "example.asl".absolute_path.compile
  if maybe_compiled.is_err:
    echo maybe_compiled.error
    quit(QuitFailure)
