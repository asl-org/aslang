import strformat, sets, strutils, tables

import statement, function_ref, arg

type ResolvedElse* = ref object of RootObj
  statements: seq[ResolvedStatement]

proc return_argument*(else_block: ResolvedElse): ArgumentDefinition =
  else_block.statements[^1].return_argument

proc resolved_return_argument*(else_block: ResolvedElse): ResolvedArgumentDefinition =
  else_block.statements[^1].resolved_return_argument

proc function_refs*(else_block: ResolvedElse): Hashset[ResolvedFunctionRef] =
  var function_ref_set: Hashset[ResolvedFunctionRef]
  for statement in else_block.statements:
    function_ref_set.incl(statement.function_refs)
  function_ref_set

proc generic_impls*(else_block: ResolvedElse): Table[string, Table[string,
    HashSet[string]]] =
  var impls: Table[string, Table[string, HashSet[string]]]
  for statement in else_block.statements:
    for (module_name, impl_map) in statement.generic_impls.pairs:
      if module_name notin impls:
        impls[module_name] = init_table[string, HashSet[string]]()
      for (generic, concrete) in impl_map.pairs:
        if generic notin impls[module_name]:
          impls[module_name][generic] = init_hashset[string]()
        impls[module_name][generic].incl(concrete)
  return impls

proc c*(resolved_else_block: ResolvedElse, result_var: Token): string =
  var lines = @["default: {"]
  for statement in resolved_else_block.statements:
    lines.add(statement.c)

  let return_arg = resolved_else_block.return_argument.name
  lines.add(fmt"{result_var} = {return_arg};")
  lines.add("break;")
  lines.add("}")
  return lines.join("\n")

proc new_resolved_else*(statements: seq[
    ResolvedStatement]): ResolvedElse =
  ResolvedElse(statements: statements)
