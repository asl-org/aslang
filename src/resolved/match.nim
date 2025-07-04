import results, strformat, sequtils, sets, strutils

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

proc function_set*(match: ResolvedMatch): HashSet[ExternalFunction] =
  var function_set: Hashset[ExternalFunction]
  for case_block in match.case_blocks:
    function_set.incl(case_block.function_set)
  for else_block in match.else_blocks:
    function_set.incl(else_block.function_set)
  return function_set

proc c*(resolved_match: ResolvedMatch): string =
  let match = resolved_match.parsed_match_block
  # TODO: Fix garbage value errors if the return argument is defined
  # within one of the blocks C compiler shows undefined behavior.
  var lines = @[
    fmt"{resolved_match.return_argument};",
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
        ResolvedElse]): Result[ResolvedMatch, string] =
  let return_type = case_blocks[0].return_argument.arg_type
  let case_return_args = case_blocks.map_it(it.return_argument)
  let else_return_args = else_blocks.map_it(it.return_argument)
  for return_arg in (case_return_args & else_return_args):
    if $(return_type) != $(return_arg.arg_type):
      return err(fmt"{return_arg.location} block is expected to return {return_type} but found {return_arg.arg_type}")

  let return_argument = new_argument_definition(return_type, destination)
  ok(ResolvedMatch(parsed_match_block: parsed_match_block,
      destination: destination, operand: operand, case_blocks: case_blocks,
      else_blocks: else_blocks, return_argument: return_argument))
