import results, strutils, strformat, tables

import common

import "../rules/parse_result"

type Fields* = ref object of RootObj
  spaces: int
  field_defs: seq[ArgumentDefinition]
  field_defs_mapping: Table[string, ArgumentDefinition]

proc spaces*(fields_block: Fields): int = fields_block.spaces
proc field_defs*(fields_block: Fields): seq[
    ArgumentDefinition] = fields_block.field_defs

proc new_fields*(spaces: int): Fields =
  let field_defs_mapping = init_table[string, ArgumentDefinition]()
  Fields(field_defs: @[], field_defs_mapping: field_defs_mapping,
      spaces: spaces)

proc `$`*(fields_block: Fields): string =
  let prefix = prefix(fields_block.spaces)
  let child_prefix = child_prefix(fields_block.spaces)
  var content = @[prefix & "fields:"]
  for field_def in fields_block.field_defs:
    content.add(child_prefix & $(field_def))
  return content.join("\n")

proc add_field_def*(fields_block: Fields,
    field_def: ArgumentDefinition): Result[void, string] =
  if $(field_def.name) in fields_block.field_defs_mapping:
    return err(fmt"{field_def.name} already exists")

  fields_block.field_defs_mapping[$(field_def.name)] = field_def
  fields_block.field_defs.add(field_def)
  ok()

proc get_field_def*(fields: Fields, field_name: Identifier): Result[
    ArgumentDefinition, string] =
  if $(field_name) in fields.field_defs_mapping:
    return ok(fields.field_defs_mapping[$(field_name)])
  return err(fmt"Found unknown field {field_name}")

proc close*(fields_block: Fields): Result[void, string] =
  if fields_block.field_defs.len == 0:
    return err("Fields block must have at least 1 field definition")
  ok()

type Else* = ref object of RootObj
  spaces: int
  statements: seq[Statement]

proc spaces*(else_block: Else): int = else_block.spaces
proc statements*(else_block: Else): seq[Statement] = else_block.statements

proc new_else*(spaces: int): Else =
  Else(spaces: spaces)

proc `$`*(else_block: Else): string =
  let prefix = prefix(else_block.spaces)
  let child_prefix = child_prefix(else_block.spaces)
  var content = @[prefix & "else:"]
  for statement in else_block.statements:
    content.add(child_prefix & $(statement))
  return content.join("\n")

proc add_statement*(else_block: Else, statement: Statement): Result[void, string] =
  else_block.statements.add(statement)
  ok()

proc close*(else_block: Else): Result[void, string] =
  if else_block.statements.len == 0:
    return err("Case block must have at least 1 statement")
  ok()

type Case* = ref object of RootObj
  value: Atom
  spaces: int
  statements: seq[Statement]

proc spaces*(case_block: Case): int = case_block.spaces
proc statements*(case_block: Case): seq[Statement] = case_block.statements
proc value*(case_block: Case): Atom = case_block.value

proc new_case*(value: Atom, spaces: int): Case =
  Case(value: value, spaces: spaces)

proc `$`*(case_block: Case): string =
  let prefix = prefix(case_block.spaces)
  let child_prefix = child_prefix(case_block.spaces)
  var content = @[prefix & "case " & $(case_block.value) & ":"]
  for statement in case_block.statements:
    content.add(child_prefix & $(statement))
  return content.join("\n")

proc add_statement*(case_block: Case, statement: Statement): Result[void, string] =
  case_block.statements.add(statement)
  ok()

proc close*(case_block: Case): Result[void, string] =
  if case_block.statements.len == 0:
    return err("Case block must have at least 1 statement")
  ok()

type Match* = ref object of RootObj
  value: Identifier
  spaces: int
  cases: seq[Case]
  else_blocks: seq[Else]

proc value*(matcher: Match): Identifier = matcher.value
proc spaces*(matcher: Match): int = matcher.spaces
proc cases*(matcher: Match): seq[Case] = matcher.cases
proc else_blocks*(matcher: Match): seq[Else] = matcher.else_blocks

proc new_matcher*(value: Identifier, spaces: int): Match =
  Match(value: value, spaces: spaces)

proc add_case*(matcher: Match, case_block: Case): Result[void, string] =
  if matcher.else_blocks.len == 1:
    return err("Match block does not support case blocks after an else block")

  for cb in matcher.cases:
    if $(cb.value) == $(case_block.value):
      return err("Duplicate case block condition `case {case_block.value}:`")

  matcher.cases.add(case_block)
  ok()

proc add_else*(matcher: Match, else_block: Else): Result[void, string] =
  if matcher.else_blocks.len == 1:
    return err("Match block does not support multiple else blocks")
  matcher.else_blocks.add(else_block)
  ok()

proc `$`*(matcher: Match): string =
  let prefix = prefix(matcher.spaces)
  var content = @[fmt"{prefix}match {matcher.value}:"]
  for case_block in matcher.cases:
    content.add($(case_block))
  for else_block in matcher.else_blocks:
    content.add($(else_block))
  return content.join("\n")

proc close*(matcher: Match): Result[void, string] =
  if matcher.cases.len == 0:
    return err("Match block must have at least one case statement")
  ok()
