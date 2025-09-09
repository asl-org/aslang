import strutils, strformat, results, sequtils

import token, statement

type UnionPattern* = ref object of RootObj
  name*: Token
  fields*: seq[(Token, Token)]

proc new_union_pattern*(name: Token, fields: seq[(Token,
    Token)]): UnionPattern =
  UnionPattern(name: name, fields: fields)

proc location*(pattern: UnionPattern): Location =
  pattern.name.location

proc `$`*(union_pattern: UnionPattern): string =
  let fields_csv = union_pattern.fields.map_it(fmt"{it[0]}: {it[1]}").join(", ")
  let fields_str = "{ " & fields_csv & " }"
  fmt"{union_pattern.name} {fields_str}"

type
  PatternKind* = enum
    PK_LITERAL, PK_UNION
  Pattern* = ref object of RootObj
    case kind*: PatternKind
    of PK_LITERAL: literal*: Token
    of PK_UNION: union*: UnionPattern

proc new_pattern*(literal: Token): Pattern =
  Pattern(kind: PK_LITERAL, literal: literal)

proc new_pattern*(union: UnionPattern): Pattern =
  Pattern(kind: PK_UNION, union: union)

proc location*(pattern: Pattern): Location =
  case pattern.kind:
  of PK_LITERAL: pattern.literal.location
  of PK_UNION: pattern.union.location

proc `$`*(pattern: Pattern): string =
  case pattern.kind:
  of PK_LITERAL: $(pattern.literal)
  of PK_UNION: $(pattern.union)

type CaseDefinition* = ref object of RootObj
  pattern*: Pattern
  location*: Location

proc new_case_definition*(pattern: Pattern,
    location: Location): CaseDefinition =
  CaseDefinition(pattern: pattern, location: location)

proc `$`*(case_definition: CaseDefinition): string =
  fmt"case {case_definition.pattern}:"

type Case* = ref object of RootObj
  case_def: CaseDefinition
  statements*: seq[Statement]

proc new_case*(case_def: CaseDefinition): Case =
  Case(case_def: case_def)

proc location*(case_block: Case): Location =
  case_block.case_def.location

proc pattern*(case_block: Case): Pattern =
  case_block.case_def.pattern

proc `$`*(case_block: Case): string =
  let prefix = " ".repeat(case_block.case_def.location.column - 1)
  let child_prefix = " ".repeat(case_block.case_def.location.column + 1)
  var lines = @[prefix & $(case_block.case_def)]
  for statement in case_block.statements:
    lines.add(child_prefix & $(statement))
  return lines.join("\n")

proc add_statement*(case_block: Case, statement: Statement): Result[void, string] =
  case_block.statements.add(statement)
  ok()

proc close*(case_block: Case): Result[void, string] =
  if case_block.statements.len == 0:
    return err(fmt"{case_block.location} `case` must contain at least one statement")
  ok()
