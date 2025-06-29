import strformat, strutils, tables

import token, arg_def, statement

type ElseDefinition* = ref object of RootObj
  location*: Location

proc `$`*(else_definition: ElseDefinition): string =
  fmt"else:"

proc new_else_definition*(location: Location): ElseDefinition =
  ElseDefinition(location: location)

type Else* = ref object of RootObj
  else_def*: ElseDefinition
  statements*: seq[Statement]
  scope*: Table[string, ArgumentDefinition]

proc location*(else_block: Else): Location =
  else_block.else_def.location

proc `$`*(else_block: Else): string =
  let prefix = " ".repeat(else_block.else_def.location.column - 1)
  let child_prefix = " ".repeat(else_block.else_def.location.column + 1)
  var lines = @[prefix & $(else_block.else_def)]
  for statement in else_block.statements:
    lines.add(child_prefix & $(statement))
  return lines.join("\n")

proc c*(else_block: Else, result_var: Token): string =
  var lines = @["default: {"]
  for statement in else_block.statements:
    let native_arg_type = else_block.scope[$(statement.destination)].native_type
    lines.add(fmt"{native_arg_type} {statement.destination} = {statement.function_call};")

  let return_arg = else_block.statements[^1].destination
  lines.add(fmt"{result_var} = {return_arg};")
  lines.add("break;")
  lines.add("}")
  return lines.join("\n")

proc add_statement*(else_block: Else, statement: Statement): void =
  else_block.statements.add(statement)

proc new_else*(else_def: ElseDefinition): Else =
  Else(else_def: else_def)
