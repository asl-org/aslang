import results, strformat, strutils, tables, sequtils

import module
import function
import matcher

import "../rules/parse_result"

# proc process_module(module: string): (string, int) =
#   let index = module.find("*")
#   if index == -1:
#     return (module, 0)
#   else:
#     return (module.substr(0, index), module.count("*"))

proc make_native_module(name: string, fns: seq[(string, string, seq[(
    string, string)])]): Result[Module, string] =
  let native_module = name.new_identifier().new_module_def().new_native_module()

  for (returns, fn_name, args) in fns:
    var arg_defs: seq[ArgumentDefinition]
    for (module, name) in args:
      # let (module_name, refcount) = module.process_module()
      # let arg_def = new_arg_def(new_identifier(module_name), new_identifier(name), refcount)
      let arg_def = new_arg_def(new_identifier(module), new_identifier(name))
      arg_defs.add(arg_def)

    let fn_def = new_fn_def(new_identifier(fn_name), new_identifier(
        returns), arg_defs)

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
  # U8 module
  let byte_module = ? make_native_module("U8", @[
    ("U8", "print", @[("U8", "value")])
  ])
  ? scope.add_native_module(byte_module)

  # U64 module
  let u64_module = ? make_native_module("U64", @[
    ("U64", "add", @[("U64", "a"), ("U64", "b")]),
    ("U64", "subtract", @[("U64", "a"), ("U64", "b")]),
    ("U64", "multiply", @[("U64", "a"), ("U64", "b")]),
    ("U64", "quotient", @[("U64", "a"), ("U64", "b")]),
    ("U64", "remainder", @[("U64", "a"), ("U64", "b")]),
    ("S64", "compare", @[("U64", "a"), ("U64", "b")]),
    ("U64", "print", @[("U64", "a")]),
  ])
  ? scope.add_native_module(u64_module)

  # S64 module
  let s64_module = ? make_native_module("S64", @[
    ("S64", "add", @[("S64", "a"), ("S64", "b")]),
    ("S64", "subtract", @[("S64", "a"), ("S64", "b")]),
    ("S64", "multiply", @[("S64", "a"), ("S64", "b")]),
    ("S64", "quotient", @[("S64", "a"), ("S64", "b")]),
    ("S64", "remainder", @[("S64", "a"), ("S64", "b")]),
    ("S64", "compare", @[("S64", "a"), ("S64", "b")]),
    ("U64", "print", @[("S64", "a")]),
  ])
  ? scope.add_native_module(s64_module)

  # Pointer module
  let ptr_module = ? make_native_module("Pointer", @[
    ("Pointer", "shift", @[("Pointer", "ptr"), ("U64", "offset")]),
    ("U64", "print", @[("Pointer", "ptr")]),
    ("U8", "read_U8", @[("Pointer", "ptr")]),
    ("U64", "read_U64", @[("Pointer", "ptr")]),
    ("S64", "read_S64", @[("Pointer", "ptr")]),
    ("Pointer", "write_U8", @[("Pointer", "ptr"), ("U8", "value")]),
    ("Pointer", "write_U64", @[("Pointer", "ptr"), ("U64", "value")]),
    ("Pointer", "write_S64", @[("Pointer", "ptr"), ("S64", "value")]),
    ("U8", "free", @[("Pointer", "ptr")]),
  ])
  ? scope.add_native_module(ptr_module)

  # S64 module
  let sys_module = ? make_native_module("System", @[
    ("Pointer", "allocate", @[("U64", "bytes")]),
    ("U8", "free", @[("Pointer", "ptr")]),
  ])
  ? scope.add_native_module(sys_module)

  # Bitset module
  # let bitset_module = ? make_native_module("Bitset", @[
  #   ("Bitset", "init", @[("U64", "bits")]),
  #   ("U64", "print", @[("Bitset*", "value")]),
  #   ("Byte", "get", @[("Bitset*", "value"), ("U64", "bit")]),
  #   ("Bitset*", "set", @[("Bitset*", "value"), ("U64", "bit")]),
  #   ("Bitset*", "unset", @[("Bitset*", "value"), ("U64", "bit")]),
  #   ("Bitset*", "toggle", @[("Bitset*", "value"), ("U64", "bit")]),
  #   ("U64", "free", @[("Bitset*", "value")]),
  # ])
  # ? scope.add_native_module(bitset_module)

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

proc resolve_function_definition(scope: Scope,
    fn_def: FunctionDefinition): Result[void, string] =
  discard ? scope.find_module(fn_def.returns)
  for arg in fn_def.arg_def_list:
    discard ? scope.find_module(arg.module)
  ok()

proc resolve_initializer(scope: Scope, module: Identifier,
    init: Initializer): Result[Module, string] =
  var module_name = init.module_name
  if $(module_name) == "MODULE": module_name = module
  # TODO: Resolve literal value for appropriate module
  return scope.find_module(module_name)

proc resolve_function_call_module(scope: Scope, module: Identifier,
    fncall: FunctionCall): Result[Module, string] =
  var module_name = fncall.module_name
  if $(module_name) == "MODULE": module_name = module

  return scope.find_module(module_name)

type FunctionScope* = ref object of RootObj
  mapping: Table[string, ArgumentDefinition] = initTable[string,
      ArgumentDefinition]()

proc add_arg(fn_scope: FunctionScope, arg_def: ArgumentDefinition): Result[
    void, string] =
  let arg_name = $(arg_def.name)
  if arg_name in fn_scope.mapping:
    return err(fmt"{arg_name} already exists in the scope")

  fn_scope.mapping[arg_name] = arg_def
  return ok()

proc get_arg(fn_scope: FunctionScope, arg_name: Identifier): Result[
    ArgumentDefinition, string] =
  let arg_name_str = $(arg_name)
  if not (arg_name_str in fn_scope.mapping):
    return err(fmt"{arg_name} is not present in the scope")
  ok(fn_scope.mapping[arg_name_str])

proc add_function_definition(fn_scope: FunctionScope,
    fn_def: FunctionDefinition): Result[void, string] =
  for arg in fn_def.arg_def_list:
    ? fn_scope.add_arg(arg)
  ok()

proc resolve_function_call_arg(fn_scope: FunctionScope, scope: Scope,
    arg: Argument, arg_def: ArgumentDefinition): Result[void, string] =
  case arg.kind:
  of AK_IDENTIFIER:
    let scope_arg_def = ? fn_scope.get_arg(arg.name)
    if $(arg_def.module) != $(scope_arg_def.module):
      return err(fmt"{arg.name} is expected to be of type {arg_def.module} but found {scope_arg_def.module}")
  of AK_LITERAL:
    # TODO: check if literal can be cast to the expected module
    let module = ? scope.find_module(arg_def.module)
    case module.kind:
    of MK_NATIVE: discard
    of MK_USER: discard
  return ok()

proc resolve_function_call_arglist(fn_scope: FunctionScope, scope: Scope,
    arg_def_list: seq[ArgumentDefinition], arglist: seq[
        Argument]): Result[void, string] =
  for (arg_def, actual_arg) in zip(arg_def_list, arglist):
    let maybe_resolved = fn_scope.resolve_function_call_arg(scope, actual_arg, arg_def)
    ? maybe_resolved
  ok()

proc resolve_function_call(fn_scope: FunctionScope, scope: Scope,
    fn_module: Module, fncall: FunctionCall): Result[Identifier, string] =
  for fn in fn_module.find_fn(fncall.fn_name, fncall.arglist.len):
    let maybe_resolved = fn_scope.resolve_function_call_arglist(scope,
        fn.def.arg_def_list, fncall.arglist)
    if maybe_resolved.is_ok:
      return ok(fn.def.returns)
  return err(fmt"None of the functions calls matched with {fncall}")

proc generate_statement(scope: Scope, s: Statement, module: Identifier,
    fn: Function, fn_scope: FunctionScope, last_statement: bool): Result[
    string, string] =
  var statements_code: seq[string]
  case s.kind:
  of SK_ASSIGNMENT:
    case s.assign.value.kind:
    of VK_INIT:
      let init = s.assign.value.init
      let module = ? scope.resolve_initializer(module, init)
      ? fn_scope.add_arg(new_arg_def(module.def.name, s.assign.dest))
      statements_code.add(fmt"{module.def.name} {s.assign.dest} = {init.literal};")
    of VK_FNCALL:
      let fncall = s.assign.value.fncall
      let fn_module = ? scope.resolve_function_call_module(module, fncall)
      let return_type = ? fn_scope.resolve_function_call(scope, fn_module, fncall)

      var fncall_args: seq[string]
      for arg in fncall.arglist:
        fncall_args.add($(arg))
      let fncall_args_str = fncall_args.join(", ")
      # TODO: Check the return type of function call in scope, for now using work around
      statements_code.add(fmt"{return_type} {s.assign.dest} = {fn_module.def.name}_{fncall.fn_name}({fncall_args_str});")
      let new_arg_def = new_arg_def(return_type, s.assign.dest)
      let arg_added = fn_scope.add_arg(new_arg_def)
      ? arg_added

    # last line must be a return
    if last_statement:
      statements_code.add(fmt"return {s.assign.dest};")
  of SK_FNCALL:
    let fncall = s.fncall

    let fn_module = ? scope.resolve_function_call_module(module, fncall)
    let return_type = ? fn_scope.resolve_function_call(scope, fn_module, fncall)

    var fncall_args: seq[string]
    for arg in fncall.arglist:
      fncall_args.add($(arg))
    let fncall_args_str = fncall_args.join(", ")

    var module_name = fncall.module_name
    if $(module_name) == "MODULE":
      module_name = module
    var fncall_code = fmt"{module_name}_{fncall.fn_name}({fncall_args_str});"

    # last line must be a return
    if last_statement:
      if $(return_type) != $(fn.def.returns):
        return err(fmt"Expected {fncall} to return {fn.def.returns} but found {return_type}")
      fncall_code = fmt"return {fncall_code}"

    statements_code.add(fncall_code)
  of SK_IDENTIFIER:
    discard ? fn_scope.get_arg(s.identifier)
    if last_statement:
      statements_code.add(fmt"return {s.identifier};")

  return ok(statements_code.join("\n"))

proc generate_case_block(fn_scope: FunctionScope, scope: Scope,
    module: Identifier, fn: Function, case_block: Case): Result[string, string] =
    # TODO: Make sure literal is of appropriate kind
  var case_block_code = @[fmt"case {case_block.value}:" & "{"]
  for i, s in case_block.statements:
    let scode = ? scope.generate_statement(s, module, fn, fn_scope, i ==
        case_block.statements.len - 1)
    case_block_code.add(scode)

  case_block_code.add("}")
  return ok(case_block_code.join("\n"))

proc generate_else_block(fn_scope: FunctionScope, scope: Scope,
    module: Identifier, fn: Function, else_block: Else): Result[string, string] =
  var else_block_code = @[fmt"default:" & "{"]
  for i, s in else_block.statements:
    let scode = ? scope.generate_statement(s, module, fn, fn_scope, i ==
        else_block.statements.len - 1)
    else_block_code.add(scode)
  else_block_code.add("}")
  return ok(else_block_code.join("\n"))

proc generate_match_block(fn_scope: FunctionScope, scope: Scope,
    module: Identifier, fn: Function, match_block: Matcher): Result[string, string] =
  discard ? fn_scope.get_arg(match_block.value)

  var match_block_code = @[fmt"switch({match_block.value})" & "{"]
  if match_block.cases.len == 0:
    # if this error shows up something is wrong with blockification logic
    return err(fmt"Match block should at least have 1 case block")

  for case_block in match_block.cases:
    let case_block_code = ? fn_scope.generate_case_block(scope, module, fn, case_block)
    match_block_code.add(case_block_code)

  if match_block.else_blocks.len > 1:
    # if this error shows up something is wrong with blockification logic
    return err(fmt"Match block can not have more than 1 else blocks")

  for else_block in match_block.else_blocks:
    let else_block_code = ? fn_scope.generate_else_block(scope, module, fn, else_block)
    match_block_code.add(else_block_code)

  match_block_code.add("}")
  match_block_code.add("UNREACHABLE();")
  return ok(match_block_code.join("\n"))

proc generate_function*(scope: Scope, fn: Function, module: Identifier): Result[
    string, string] =
  var fn_code: seq[string]
  var arg_code: seq[string]
  var fn_scope = FunctionScope()

  ? scope.resolve_function_definition(fn.def)
  ? fn_scope.add_function_definition(fn.def)

  # function signature c code
  for arg in fn.def.arg_def_list:
    arg_code.add(fmt"{arg.module} {arg.name}")

  let arg_code_str = arg_code.join(", ")
  fn_code.add(fmt"{fn.def.returns} {module}_{fn.def.name}(" & arg_code_str & ") {")

  let maybe_match_block = fn.match_block()

  # statement c code
  var statements_code: seq[string]
  let statements = ( ? fn.statements)
  for index, s in statements:
    var last_statement: bool
    if maybe_match_block.is_ok:
      last_statement = false
    else:
      last_statement = index == statements.len - 1
    let scode = ? scope.generate_statement(s, module, fn, fn_scope, last_statement)
    statements_code.add(scode)

  fn_code.add(statements_code.join("\n"))

  if maybe_match_block.is_ok:
    let match_block_code = ? fn_scope.generate_match_block(scope, module, fn,
        maybe_match_block.get)
    fn_code.add(match_block_code)

  fn_code.add("}")

  ok(fn_code.join("\n"))


proc generate_app*(scope: Scope): Result[string, string] =
  let app = scope.modules[0]
  var fn_code: seq[string]

  for fn in app.fns:
    let fnc = ? scope.generate_function(fn, app.def.name)
    fn_code.add(fnc)
  let fn_code_str = fn_code.join("\n")

  let code = @[
    """#include "runtime/asl.h"""",
    fn_code_str,
    "int main(int argc, char** argv) {",
    fmt"return {app.def.name}_start((U8)argc);",
    "}"
  ]

  ok(code.join("\n"))
