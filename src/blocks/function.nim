import results, strformat, strutils
import "../rules"

import common

type Function* = ref object of RootObj
  def: FunctionDefinition
  statements: seq[Statement]
  spaces: int

proc `$`*(fn: Function): string =
  let prefix = prefix(fn.spaces)
  let child_prefix = child_prefix(fn.spaces)
  var content: seq[string] = @[prefix & $(fn.def)]
  for statement in fn.statements:
    content.add((child_prefix & $(statement)))
  return content.join("\n")

proc new_function*(def: FunctionDefinition,
    spaces: int): Function =
  Function(def: def, spaces: spaces)

# TODO: add duplicate block validation
proc add_statement*(fn: Function, statement: Statement): void =
  fn.statements.add(statement)

# TODO: perform final validation
proc close*(fn: Function): Result[void, string] =
  if fn.statements.len == 0:
    return err(fmt"function block must have at least one statement")
  ok()

proc c*(fn: Function, module: Identifier): Result[string, string] =
  var arg_code: seq[string]
  for arg in fn.def.arg_def_list.defs:
    arg_code.add(fmt"{arg.module} {arg.name}")

  let arg_code_str = arg_code.join(", ")

  var statements_code: seq[string]
  for index, s in fn.statements:
    case s.kind:
    of SK_ASSIGNMENT:
      case s.assign.value.kind:
      of VK_INIT:
        let init = s.assign.value.init
        statements_code.add(fmt"{init.module_name} {s.assign.dest} = {init.literal};")
      of VK_FNCALL:
        let fncall = s.assign.value.fncall
        var fncall_args: seq[string]
        for arg in fncall.arglist.args:
          fncall_args.add($(arg))
        let fncall_args_str = fncall_args.join(", ")
        statements_code.add(fmt"{fncall.module_name}_{fncall.fn_name}({fncall_args_str});")

      # last line must be a return
      if index == fn.statements.len - 1:
        statements_code.add(fmt"return {s.assign.dest};")
    of SK_FNCALL:
      let fncall = s.fncall

      var fncall_args: seq[string]
      for arg in fncall.arglist.args:
        fncall_args.add($(arg))
      let fncall_args_str = fncall_args.join(", ")
      var fncall_code = fmt"{fncall.module_name}_{fncall.fn_name}({fncall_args_str});"

      # last line must be a return
      if index == fn.statements.len - 1:
        fncall_code = fmt"return {fncall_code}"

      statements_code.add(fncall_code)

  let statements_code_str = statements_code.join("\n")
  let fn_code = @[
    fmt"{fn.def.returns} {module}_{fn.def.name}(" & arg_code_str & ") {",
    fmt"{statements_code_str}",
    "}"
  ]

  ok(fn_code.join("\n"))
