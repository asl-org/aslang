import strformat, sets, strutils, sequtils, tables

import statement, arg, function_ref

type
  ResolvedPatternKind = enum
    RPK_LITERAL, RPK_UNION
  ResolvedPattern* = ref object of RootObj
    case kind*: ResolvedPatternKind
    of RPK_LITERAL:
      literal: ResolvedLiteral
    of RPK_UNION:
      module: UserModule
      union: UnionFieldDefinition
      id: int
      args: seq[(ResolvedArgumentDefinition, Token)]

proc new_resolved_pattern*(literal: ResolvedLiteral): ResolvedPattern =
  ResolvedPattern(kind: RPK_LITERAL, literal: literal)

proc new_resolved_pattern*(module: UserModule, union: UnionFieldDefinition,
    id: int, args: seq[(ResolvedArgumentDefinition,
        Token)]): ResolvedPattern =
  ResolvedPattern(kind: RPK_UNION, module: module, union: union, id: id, args: args)

proc args*(pattern: ResolvedPattern): seq[ResolvedArgumentDefinition] =
  case pattern.kind:
  of RPK_LITERAL: @[]
  of RPK_UNION: pattern.args.map_it(it[0])

proc `$`*(resolved_pattern: ResolvedPattern): string =
  case resolved_pattern.kind:
  of RPK_LITERAL: $(resolved_pattern.literal.value)
  of RPK_UNION: $(resolved_pattern.id)

type ResolvedCase* = ref object of RootObj
  pattern: ResolvedPattern
  operand: Token
  statements: seq[ResolvedStatement]

proc resolved_return_argument*(case_block: ResolvedCase): ResolvedArgumentDefinition =
  case_block.statements[^1].resolved_return_argument

proc function_refs*(case_block: ResolvedCase): Hashset[ResolvedFunctionRef] =
  var function_ref_set: Hashset[ResolvedFunctionRef]
  for statement in case_block.statements:
    function_ref_set.incl(statement.function_refs)
  function_ref_set

proc generic_impls*(case_block: ResolvedCase): Table[string, Table[string,
    HashSet[string]]] =
  var impls: Table[string, Table[string, HashSet[string]]]
  for statement in case_block.statements:
    for (module_name, impl_map) in statement.generic_impls.pairs:
      if module_name notin impls:
        impls[module_name] = init_table[string, HashSet[string]]()
      for (generic, concrete) in impl_map.pairs:
        if generic notin impls[module_name]:
          impls[module_name][generic] = init_hashset[string]()
        impls[module_name][generic].incl(concrete)
  return impls

proc c*(resolved_case: ResolvedCase, result_var: Token): string =
  var lines: seq[string] = @[fmt"case {resolved_case.pattern}: " & "{"]

  case resolved_case.pattern.kind:
  of RPK_LITERAL: discard
  of RPK_UNION:
    for (resolved_arg, field) in resolved_case.pattern.args:
      lines.add(fmt"{resolved_arg.c} = {resolved_case.pattern.module.name}_{resolved_case.pattern.union.name}_get_{field}({resolved_case.operand});")

  for statement in resolved_case.statements:
    lines.add(statement.c)

  let return_arg = resolved_case.resolved_return_argument.name
  lines.add(fmt"{result_var} = {return_arg};")
  lines.add("break;")
  lines.add("}")
  return lines.join("\n")

proc new_resolved_case*(pattern: ResolvedPattern, operand: Token,
    statements: seq[ResolvedStatement]): ResolvedCase =
  ResolvedCase(pattern: pattern, operand: operand, statements: statements)
