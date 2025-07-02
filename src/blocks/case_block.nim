import strutils, strformat

import token, statement

type CaseDefinition* = ref object of RootObj
  value*: Token
  location*: Location

proc `$`*(case_definition: CaseDefinition): string =
  fmt"case {case_definition.value}:"

proc new_case_definition*(value: Token, location: Location): CaseDefinition =
  CaseDefinition(value: value, location: location)

type Case* = ref object of RootObj
  case_def: CaseDefinition
  statements*: seq[Statement]

proc location*(case_block: Case): Location =
  case_block.case_def.location

proc value*(case_block: Case): Token =
  case_block.case_def.value

proc `$`*(case_block: Case): string =
  let prefix = " ".repeat(case_block.case_def.location.column - 1)
  let child_prefix = " ".repeat(case_block.case_def.location.column + 1)
  var lines = @[prefix & $(case_block.case_def)]
  for statement in case_block.statements:
    lines.add(child_prefix & $(statement))
  return lines.join("\n")

proc add_statement*(case_block: Case, statement: Statement): void =
  case_block.statements.add(statement)

proc new_case*(case_def: CaseDefinition): Case =
  Case(case_def: case_def)
