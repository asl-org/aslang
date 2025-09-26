import strformat, sets, strutils, tables

import case_block
import else_block

import function_ref, arg

const ASL_UNION_ID = "__asl_union_id__"

type ResolvedMatch* = ref object of RootObj
  parsed_match_block: Match
  destination*: Token
  operand: ArgumentDefinition
  case_blocks: seq[ResolvedCase]
  # there can only be 1 else block
  else_blocks: seq[ResolvedElse]
  return_argument*: ArgumentDefinition
  resolved_return_argument*: ResolvedArgumentDefinition

proc function_refs*(match: ResolvedMatch): HashSet[ResolvedFunctionRef] =
  var function_ref_set: Hashset[ResolvedFunctionRef]
  for case_block in match.case_blocks:
    function_ref_set.incl(case_block.function_refs)
  for else_block in match.else_blocks:
    function_ref_set.incl(else_block.function_refs)
  return function_ref_set

proc generic_impls*(match: ResolvedMatch): Table[string, Table[string,
    HashSet[string]]] =
  var impls: Table[string, Table[string, HashSet[string]]]
  for case_block in match.case_blocks:
    for (module_name, impl_map) in case_block.generic_impls.pairs:
      if module_name notin impls:
        impls[module_name] = init_table[string, HashSet[string]]()
      for (generic, concrete) in impl_map.pairs:
        if generic notin impls[module_name]:
          impls[module_name][generic] = init_hashset[string]()
        impls[module_name][generic].incl(concrete)

  for else_block in match.else_blocks:
    for (module_name, impl_map) in else_block.generic_impls.pairs:
      if module_name notin impls:
        impls[module_name] = init_table[string, HashSet[string]]()
      for (generic, concrete) in impl_map.pairs:
        if generic notin impls[module_name]:
          impls[module_name][generic] = init_hashset[string]()
        impls[module_name][generic].incl(concrete)
  return impls

proc c*(resolved_match: ResolvedMatch): string =
  let match = resolved_match.parsed_match_block
  # TODO: Fix garbage value errors if the return argument is defined
  # within one of the blocks C compiler shows undefined behavior.
  # A potential fix is to prefix the variable names within that scope
  # with a scope specific `hash`, location can be used as hash.
  var lines = @[fmt"{resolved_match.return_argument.native_type} {resolved_match.return_argument.name};"]

  let match_expr =
    case $(resolved_match.operand.typ):
    of "U8", "U16", "U32", "U64", "S8", "S16", "S32", "S64":
      $(resolved_match.operand.name)
    else:
      fmt"{resolved_match.operand.typ.parent}_get_{ASL_UNION_ID}({resolved_match.operand.name})"

  lines.add(fmt"switch({match_expr}) " & "{")
  for case_block in resolved_match.case_blocks:
    lines.add(case_block.c(match.destination))
  for else_block in resolved_match.else_blocks:
    lines.add(else_block.c(match.destination))
  lines.add("}")
  return lines.join("\n")

proc new_resolved_match*(parsed_match_block: Match, destination: Token,
    operand: ArgumentDefinition, case_blocks: seq[ResolvedCase],
    else_blocks: seq[ResolvedElse], return_argument: ArgumentDefinition,
    resolved_return_argument: ResolvedArgumentDefinition): ResolvedMatch =
  ResolvedMatch(parsed_match_block: parsed_match_block,
      destination: destination, operand: operand, case_blocks: case_blocks,
      else_blocks: else_blocks, return_argument: return_argument,
      resolved_return_argument: resolved_return_argument)
