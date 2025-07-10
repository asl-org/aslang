import strformat, strutils, results

import token, statement

type ElseDefinition* = ref object of RootObj
  location*: Location

proc `$`*(else_definition: ElseDefinition): string =
  fmt"else:"

proc new_else_definition*(location: Location): ElseDefinition =
  ElseDefinition(location: location)

type Else* = ref object of RootObj
  else_def*: ElseDefinition
  statements*: seq[Statement]

proc location*(else_block: Else): Location =
  else_block.else_def.location

proc `$`*(else_block: Else): string =
  let prefix = " ".repeat(else_block.else_def.location.column - 1)
  let child_prefix = " ".repeat(else_block.else_def.location.column + 1)
  var lines = @[prefix & $(else_block.else_def)]
  for statement in else_block.statements:
    lines.add(child_prefix & $(statement))
  return lines.join("\n")

proc add_statement*(else_block: Else, statement: Statement): Result[void, string] =
  else_block.statements.add(statement)
  ok()

proc new_else*(else_def: ElseDefinition): Else =
  Else(else_def: else_def)

proc close*(else_block: Else): Result[void, string] =
  if else_block.statements.len == 0:
    return err(fmt"{else_block.location} `else` must contain at least one statement")
  ok()
