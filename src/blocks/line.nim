import token, function, case_block, else_block, match, struct, arg_def, statement

type
  LineKind* = enum
    LK_FUNCTION_DEFINITION, LK_STATEMENT,
    LK_MATCH_DEFINITION, LK_CASE_DEFINITION, LK_ELSE_DEFINITION
    LK_STRUCT_DEFINITION, LK_STRUCT_FIELD_DEFINITION
  Line* = ref object of RootObj
    case kind*: LineKind
    of LK_FUNCTION_DEFINITION: func_def*: FunctionDefinition
    of LK_STATEMENT: statement*: Statement
    of LK_MATCH_DEFINITION: match_def*: MatchDefinition
    of LK_CASE_DEFINITION: case_def*: CaseDefinition
    of LK_ELSE_DEFINITION: else_def*: ElseDefinition
    of LK_STRUCT_DEFINITION: struct_def*: StructDefinition
    of LK_STRUCT_FIELD_DEFINITION: struct_field_def*: ArgumentDefinition

proc location*(line: Line): Location =
  case line.kind:
  of LK_FUNCTION_DEFINITION: line.func_def.location
  of LK_STATEMENT: line.statement.location
  of LK_MATCH_DEFINITION: line.match_def.location
  of LK_CASE_DEFINITION: line.case_def.location
  of LK_ELSE_DEFINITION: line.else_def.location
  of LK_STRUCT_DEFINITION: line.struct_def.location
  of LK_STRUCT_FIELD_DEFINITION: line.struct_field_def.location

proc `$`*(line: Line): string =
  case line.kind:
  of LK_FUNCTION_DEFINITION: $(line.func_def)
  of LK_STATEMENT: $(line.statement)
  of LK_MATCH_DEFINITION: $(line.match_def)
  of LK_CASE_DEFINITION: $(line.case_def)
  of LK_ELSE_DEFINITION: $(line.else_def)
  of LK_STRUCT_DEFINITION: $(line.struct_def)
  of LK_STRUCT_FIELD_DEFINITION: $(line.struct_field_def)

proc new_line*(func_def: FunctionDefinition): Line =
  Line(kind: LK_FUNCTION_DEFINITION, func_def: func_def)

proc new_line*(statement: Statement): Line =
  Line(kind: LK_STATEMENT, statement: statement)

proc new_line*(match_def: MatchDefinition): Line =
  Line(kind: LK_MATCH_DEFINITION, match_def: match_def)

proc new_line*(case_def: CaseDefinition): Line =
  Line(kind: LK_CASE_DEFINITION, case_def: case_def)

proc new_line*(else_def: ElseDefinition): Line =
  Line(kind: LK_ELSE_DEFINITION, else_def: else_def)

proc new_line*(struct_def: StructDefinition): Line =
  Line(kind: LK_STRUCT_DEFINITION, struct_def: struct_def)

proc new_line*(struct_field_def: ArgumentDefinition): Line =
  Line(kind: LK_STRUCT_FIELD_DEFINITION, struct_field_def: struct_field_def)
