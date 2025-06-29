import tables, strutils, strformat, hashes, sequtils

import token, statement, match, arg_def

type FunctionDefinition* = ref object of RootObj
  name*: Token
  arg_def_list*: seq[ArgumentDefinition]
  return_type*: Token
  location*: Location

proc native_return_type*(function_def: FunctionDefinition): string =
  case $(function_def.return_type):
  of "S8", "S16", "S32", "S64", "U8", "U16", "U32", "U64", "F32", "F64",
      "Pointer": $(function_def.return_type)
  else: "Pointer"

proc hash*(func_def: FunctionDefinition): Hash =
  var essence = func_def.name.hash !& func_def.location.hash
  for arg_def in func_def.arg_def_list:
    essence = essence !& arg_def.hash
  return essence

proc `$`*(func_def: FunctionDefinition): string =
  let arg_def_list_str = func_def.arg_def_list.map_it($(it)).join(", ")
  fmt"fn {func_def.name}({arg_def_list_str}): {func_def.return_type}"

proc c*(func_def: FunctionDefinition): string =
  let args_def_str = func_def.arg_def_list.map_it($(it.native_type)).join(", ")
  fmt"{func_def.native_return_type} {func_def.name}({args_def_str});"

proc new_function_definition*(name: Token, arg_def_list: seq[
    ArgumentDefinition], return_type: Token,
        location: Location = Location()): FunctionDefinition =
  FunctionDefinition(name: name, arg_def_list: arg_def_list,
      return_type: return_type, location: location)

proc new_function_definition*(name: string, arg_def_list: seq[(string, string)],
    return_type: string): FunctionDefinition =
  let name_token = new_id_token(name)
  let return_type_token = new_id_token(return_type)
  let arg_def_list_token = arg_def_list.map_it(new_argument_definition(it[0], it[1]))
  new_function_definition(name_token, arg_def_list_token, return_type_token,
      Location())

type
  FunctionStepKind* = enum
    FSK_STATEMENT, FSK_MATCH
  FunctionStep* = ref object of RootObj
    case kind*: FunctionStepKind
    of FSK_STATEMENT:
      statement*: Statement
    of FSK_MATCH:
      match*: Match

proc `$`*(step: FunctionStep): string =
  case step.kind:
  of FSK_STATEMENT: $(step.statement)
  of FSK_MATCH: $(step.match)

proc new_function_step*(statement: Statement): FunctionStep =
  FunctionStep(kind: FSK_STATEMENT, statement: statement)

proc new_function_step*(match: Match): FunctionStep =
  FunctionStep(kind: FSK_MATCH, match: match)

type Function* = ref object of RootObj
  definition*: FunctionDefinition
  function_steps*: seq[FunctionStep]
  # statements*: seq[(uint, Statement)]
  # matches*: seq[(uint, Match)]
  scope*: Table[string, ArgumentDefinition]

proc location*(function: Function): Location =
  function.definition.location

proc name*(function: Function): string =
  $(function.definition.name)

proc return_type*(function: Function): string =
  $(function.definition.return_type)

proc steps*(function: Function): uint =
  function.function_steps.len.uint

proc native_return_type*(function: Function): string =
  case $(function.definition.return_type):
  of "S8", "S16", "S32", "S64", "U8", "U16", "U32", "U64", "F32", "F64",
      "Pointer": $(function.definition.return_type)
  else: "Pointer"

proc arity*(function: Function): int =
  function.definition.arg_def_list.len

proc arg_def_list*(function: Function): seq[ArgumentDefinition] =
  function.definition.arg_def_list

proc hash*(function: Function): Hash = function.definition.hash

proc `$`*(function: Function): string =
  let prefix = " ".repeat(function.definition.location.column - 1)
  let child_prefix = " ".repeat(function.definition.location.column + 1)
  var lines = @[prefix & $(function.definition)]

  # var sindex = 0
  # var mindex = 0
  # for step in 0..<function.steps:
  #   if sindex < function.statements.len and function.statements[sindex][0] == step:
  #     let (_, statement) = function.statements[sindex]
  #     lines.add(child_prefix & $(statement))
  #     sindex += 1
  #   else:
  #     let (_, match) = function.matches[mindex]
  #     lines.add(child_prefix & $(match))
  #     mindex += 1

  for step in function.function_steps:
    lines.add(child_prefix & $(step))

  lines.join("\n")

proc c*(function: Function): string =
  let args_def_str = function.definition.arg_def_list.map_it(
      fmt"{it.native_type} {it.arg_name}").join(", ")
  let signature = fmt"{function.native_return_type} {function.name}({args_def_str})"
  var body: seq[string]

  for step in function.function_steps:
    case step.kind:
    of FSK_STATEMENT:
      let statement = step.statement
      let native_arg_type = function.scope[$(statement.destination)].native_type
      body.add(fmt"{native_arg_type} {statement.destination} = {statement.function_call};")
    of FSK_MATCH:
      body.add(step.match.c)

  let last_step = function.function_steps[^1]
  case last_step.kind:
  of FSK_STATEMENT:
    body.add(fmt"return {last_step.statement.destination};")
  of FSK_MATCH:
    body.add(fmt"return {last_step.match.destination};")

  @[signature, "{", body.join("\n"), "}"].join("\n")

proc is_start*(function: Function): bool =
  let name = $(function.definition.name)
  let return_type = $(function.definition.return_type)
  let arity = function.definition.arg_def_list.len
  let first_arg_type = $(function.definition.arg_def_list[0].arg_type)
  return name == "start" and return_type == "U8" and arity == 1 and
      first_arg_type == "U8"

proc new_function*(definition: FunctionDefinition): Function =
  Function(definition: definition)

proc add_statement*(function: Function, statement: Statement): void =
  function.function_steps.add(new_function_step(statement))

proc add_match*(function: Function, match: Match): void =
  function.function_steps.add(new_function_step(match))

proc add_arg_to_scope*(function: Function, arg_def: ArgumentDefinition): void =
  function.scope[$(arg_def.arg_name)] = arg_def
