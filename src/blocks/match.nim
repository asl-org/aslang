import strutils, options, strformat

import token, case_block, else_block

type MatchDefinition* = ref object of RootObj
  destination*: Token
  operand*: Token

proc location*(match_definition: MatchDefinition): Location =
  match_definition.destination.location

proc `$`*(match_definition: MatchDefinition): string =
  fmt"{match_definition.destination} = match {match_definition.operand}:"

proc new_match_definition*(destination: Token,
    operand: Token): MatchDefinition =
  MatchDefinition(destination: destination, operand: operand)

type Match* = ref object of RootObj
  match_def*: MatchDefinition
  case_blocks*: seq[Case]
  else_blocks*: seq[Else]
  return_type*: Option[Token]

proc location*(match: Match): Location =
  match.match_def.location

proc destination*(match: Match): Token =
  match.match_def.destination

proc operand*(match: Match): Token =
  match.match_def.operand

proc `$`*(match: Match): string =
  let prefix = " ".repeat(match.match_def.location.column - 3)
  let child_prefix = prefix
  var lines = @[prefix & $(match.match_def)]
  for case_block in match.case_blocks:
    lines.add(child_prefix & $(case_block))
  if match.else_blocks.len > 0:
    lines.add(child_prefix & $(match.else_blocks[0]))
  return lines.join("\n")

proc add_case*(match: Match, case_block: Case): void =
  match.case_blocks.add(case_block)

proc add_else*(match: Match, else_block: Else): void =
  match.else_blocks.add(else_block)

proc new_match*(match_def: MatchDefinition): Match =
  Match(match_def: match_def)
