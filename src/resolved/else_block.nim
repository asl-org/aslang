import strformat, sets, strutils

import "../blocks"
import statement, function_call

type ResolvedElse* = ref object of RootObj
  statements: seq[ResolvedStatement]

proc return_argument*(else_block: ResolvedElse): ArgumentDefinition =
  else_block.statements[^1].return_argument

proc function_refs*(else_block: ResolvedElse): Hashset[ResolvedFunctionRef] =
  var function_ref_set: Hashset[ResolvedFunctionRef]
  for statement in else_block.statements:
    function_ref_set.incl(statement.function_refs)
  function_ref_set

proc c*(resolved_else_block: ResolvedElse, result_var: Token): string =
  var lines = @["default: {"]
  for statement in resolved_else_block.statements:
    lines.add(statement.c)

  let return_arg = resolved_else_block.return_argument.arg_name
  lines.add(fmt"{result_var} = {return_arg};")
  lines.add("break;")
  lines.add("}")
  return lines.join("\n")

proc new_resolved_else*(statements: seq[
    ResolvedStatement]): ResolvedElse =
  ResolvedElse(statements: statements)
