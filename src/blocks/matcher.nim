import results, strutils, strformat, tables

import common

import "../rules/parse_result"

type Union* = ref object of RootObj
  spaces: int
  union_defs: seq[UnionDef]
  union_defs_mapping: Table[string, UnionDef]
  union_def_fields_mapping: Table[string, Table[string, ArgumentDefinition]]

proc spaces*(fields_block: Union): int = fields_block.spaces
proc union_defs*(fields_block: Union): seq[
    UnionDef] = fields_block.union_defs

proc new_union*(spaces: int): Union =
  let union_defs_mapping = init_table[string, UnionDef]()
  let union_def_fields_mapping = init_table[string, Table[string,
      ArgumentDefinition]]()
  Union(
    union_defs: @[],
    union_defs_mapping: union_defs_mapping,
    union_def_fields_mapping: union_def_fields_mapping,
    spaces: spaces
  )

proc `$`*(union_block: Union): string =
  let prefix = prefix(union_block.spaces)
  let child_prefix = child_prefix(union_block.spaces)
  var content = @[prefix & "union:"]
  for field_def in union_block.union_defs:
    content.add(child_prefix & $(field_def))
  return content.join("\n")

proc add_union_def*(union_block: Union,
    union_def: UnionDef): Result[void, string] =
  if $(union_def.name) in union_block.union_defs_mapping:
    return err(fmt"{union_def.name} already exists")

  # union def mapping
  union_block.union_defs_mapping[$(union_def.name)] = union_def

  # union def field mapping
  union_block.union_def_fields_mapping[$(union_def.name)] = init_table[string,
      ArgumentDefinition]()
  for field_def in union_def.fields:
    union_block.union_def_fields_mapping[$(union_def.name)][$(
        field_def.name)] = field_def

  union_block.union_defs.add(union_def)
  ok()

proc get_union_def*(union: Union, union_name: Identifier): Result[
    UnionDef, string] =
  if $(union_name) in union.union_defs_mapping:
    return ok(union.union_defs_mapping[$(union_name)])
  return err(fmt"Found unknown union {union_name}")

proc get_union_def_field*(union: Union, union_name: Identifier,
    field_name: Identifier): Result[ArgumentDefinition, string] =
  if $(union_name) notin union.union_defs_mapping:
    return err(fmt"Found unknown union {union_name}")
  let union_def_fields = union.union_def_fields_mapping[$(union_name)]
  if $(field_name) notin union_def_fields:
    return err(fmt"Found unknown field {field_name} in union {union_name}")
  return ok(union_def_fields[$(field_name)])

proc close*(union_block: Union): Result[void, string] =
  if union_block.union_defs.len == 0:
    return err("struct block must have at least 1 union definition")
  ok()

type StructDef* = ref object of RootObj
  spaces: int
  field_defs: seq[ArgumentDefinition]
  field_defs_mapping: Table[string, ArgumentDefinition]

proc spaces*(fields_block: StructDef): int = fields_block.spaces
proc field_defs*(fields_block: StructDef): seq[
    ArgumentDefinition] = fields_block.field_defs

proc new_struct_def*(spaces: int): StructDef =
  let field_defs_mapping = init_table[string, ArgumentDefinition]()
  StructDef(field_defs: @[], field_defs_mapping: field_defs_mapping,
      spaces: spaces)

proc `$`*(fields_block: StructDef): string =
  let prefix = prefix(fields_block.spaces)
  let child_prefix = child_prefix(fields_block.spaces)
  var content = @[prefix & "struct:"]
  for field_def in fields_block.field_defs:
    content.add(child_prefix & $(field_def))
  return content.join("\n")

proc add_field_def*(fields_block: StructDef,
    field_def: ArgumentDefinition): Result[void, string] =
  if $(field_def.name) in fields_block.field_defs_mapping:
    return err(fmt"{field_def.name} already exists")

  fields_block.field_defs_mapping[$(field_def.name)] = field_def
  fields_block.field_defs.add(field_def)
  ok()

proc get_field_def*(fields: StructDef, field_name: Identifier): Result[
    ArgumentDefinition, string] =
  if $(field_name) in fields.field_defs_mapping:
    return ok(fields.field_defs_mapping[$(field_name)])
  return err(fmt"Found unknown field {field_name}")

proc close*(fields_block: StructDef): Result[void, string] =
  if fields_block.field_defs.len == 0:
    return err("struct block must have at least 1 field definition")
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
