import results, strutils, strformat

import common

import "../rules/parse_result"

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
