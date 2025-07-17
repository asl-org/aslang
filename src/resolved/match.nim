import strformat, sets, strutils

import "../blocks"
import case_block
import else_block

import function_call

type ResolvedMatch* = ref object of RootObj
  parsed_match_block: Match
  destination*: Token
  operand: Token
  case_blocks: seq[ResolvedCase]
  # there can only be 1 else block
  else_blocks: seq[ResolvedElse]
  return_argument*: ArgumentDefinition

proc function_refs*(match: ResolvedMatch): HashSet[ResolvedFunctionRef] =
  var function_ref_set: Hashset[ResolvedFunctionRef]
  for case_block in match.case_blocks:
    function_ref_set.incl(case_block.function_refs)
  for else_block in match.else_blocks:
    function_ref_set.incl(else_block.function_refs)
  return function_ref_set

proc c*(resolved_match: ResolvedMatch): string =
  let match = resolved_match.parsed_match_block
  # TODO: Fix garbage value errors if the return argument is defined
  # within one of the blocks C compiler shows undefined behavior.
  # A potential fix is to prefix the variable names within that scope
  # with a scope specific `hash`, location can be used as hash.
  var lines = @[
    fmt"{resolved_match.return_argument.native_type} {resolved_match.return_argument.arg_name};",
    fmt"switch({match.operand}) " & "{",
  ]
  for case_block in resolved_match.case_blocks:
    lines.add(case_block.c(match.destination))
  for else_block in resolved_match.else_blocks:
    lines.add(else_block.c(match.destination))
  lines.add("}")
  return lines.join("\n")

proc new_resolved_match*(parsed_match_block: Match, destination: Token,
    operand: Token, case_blocks: seq[ResolvedCase], else_blocks: seq[
    ResolvedElse], return_argument: ArgumentDefinition): ResolvedMatch =
  ResolvedMatch(parsed_match_block: parsed_match_block,
      destination: destination, operand: operand, case_blocks: case_blocks,
      else_blocks: else_blocks, return_argument: return_argument)
