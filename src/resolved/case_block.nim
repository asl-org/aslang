import strformat, sets, strutils

import "../blocks"
import function_call, statement

type ResolvedCase* = ref object of RootObj
  pattern: Pattern
  statements: seq[ResolvedStatement]

proc return_argument*(case_block: ResolvedCase): ArgumentDefinition =
  case_block.statements[^1].return_argument

proc function_refs*(case_block: ResolvedCase): Hashset[ResolvedFunctionRef] =
  var function_ref_set: Hashset[ResolvedFunctionRef]
  for statement in case_block.statements:
    function_ref_set.incl(statement.function_refs)
  function_ref_set

proc c*(resolved_case: ResolvedCase, result_var: Token): string =
  var lines = @[fmt"case {resolved_case.pattern}: " & "{"]
  for statement in resolved_case.statements:
    lines.add(statement.c)

  let return_arg = resolved_case.return_argument.arg_name
  lines.add(fmt"{result_var} = {return_arg};")
  lines.add("break;")
  lines.add("}")
  return lines.join("\n")

proc new_resolved_case*(pattern: Pattern, statements: seq[
    ResolvedStatement]): ResolvedCase =
  ResolvedCase(pattern: pattern, statements: statements)
