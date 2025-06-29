import tables, strutils, strformat

import token, arg_def, statement

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
  scope*: Table[string, ArgumentDefinition]

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

proc c*(case_block: Case, result_var: Token): string =
  var lines = @[fmt"case {case_block.value}: " & "{"]
  for statement in case_block.statements:
    let native_arg_type = case_block.scope[$(statement.destination)].native_type
    lines.add(fmt"{native_arg_type} {statement.destination} = {statement.function_call};")

  let return_arg = case_block.statements[^1].destination
  lines.add(fmt"{result_var} = {return_arg};")
  lines.add("break;")
  lines.add("}")
  return lines.join("\n")

proc add_statement*(case_block: Case, statement: Statement): void =
  case_block.statements.add(statement)

proc new_case*(case_def: CaseDefinition): Case =
  Case(case_def: case_def)
