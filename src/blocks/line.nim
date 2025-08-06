import token, arg_def, statement
import case_block, else_block, match
import struct, function
import module

type
  LineKind* = enum
    LK_FUNCTION_DEFINITION, LK_STATEMENT
    LK_MATCH_DEFINITION, LK_CASE_DEFINITION, LK_ELSE_DEFINITION
    LK_STRUCT_DEFINITION, LK_STRUCT_FIELD_DEFINITION
    LK_UNION_DEFINITION, LK_UNION_FIELD_DEFINITION
    LK_MODULE_DEFINITION
  Line* = ref object of RootObj
    indent*: int
    case kind*: LineKind
    of LK_FUNCTION_DEFINITION: func_def*: FunctionDefinition
    of LK_STATEMENT: statement*: Statement
    of LK_MATCH_DEFINITION: match_def*: MatchDefinition
    of LK_CASE_DEFINITION: case_def*: CaseDefinition
    of LK_ELSE_DEFINITION: else_def*: ElseDefinition
    of LK_STRUCT_DEFINITION: struct_def*: StructDefinition
    of LK_STRUCT_FIELD_DEFINITION: struct_field_def*: ArgumentDefinition
    of LK_UNION_DEFINITION: union_def*: UnionDefinition
    of LK_UNION_FIELD_DEFINITION: union_field_def*: UnionFieldDefinition
    of LK_MODULE_DEFINITION: module_def*: ModuleDefinition

proc new_line*(indent: int, func_def: FunctionDefinition): Line =
  Line(kind: LK_FUNCTION_DEFINITION, indent: indent, func_def: func_def)

proc new_line*(indent: int, statement: Statement): Line =
  Line(kind: LK_STATEMENT, indent: indent, statement: statement)

proc new_line*(indent: int, match_def: MatchDefinition): Line =
  Line(kind: LK_MATCH_DEFINITION, indent: indent, match_def: match_def)

proc new_line*(indent: int, case_def: CaseDefinition): Line =
  Line(kind: LK_CASE_DEFINITION, indent: indent, case_def: case_def)

proc new_line*(indent: int, else_def: ElseDefinition): Line =
  Line(kind: LK_ELSE_DEFINITION, indent: indent, else_def: else_def)

proc new_line*(indent: int, struct_def: StructDefinition): Line =
  Line(kind: LK_STRUCT_DEFINITION, indent: indent, struct_def: struct_def)

proc new_line*(indent: int, struct_field_def: ArgumentDefinition): Line =
  Line(kind: LK_STRUCT_FIELD_DEFINITION, indent: indent,
      struct_field_def: struct_field_def)

proc new_line*(indent: int, union_def: UnionDefinition): Line =
  Line(kind: LK_UNION_DEFINITION, indent: indent, union_def: union_def)

proc new_line*(indent: int, union_field_def: UnionFieldDefinition): Line =
  Line(kind: LK_UNION_FIELD_DEFINITION, indent: indent,
      union_field_def: union_field_def)

proc new_line*(indent: int, module_def: ModuleDefinition): Line =
  Line(kind: LK_MODULE_DEFINITION, indent: indent, module_def: module_def)

proc location*(line: Line): Location =
  case line.kind:
  of LK_FUNCTION_DEFINITION: line.func_def.location
  of LK_STATEMENT: line.statement.location
  of LK_MATCH_DEFINITION: line.match_def.location
  of LK_CASE_DEFINITION: line.case_def.location
  of LK_ELSE_DEFINITION: line.else_def.location
  of LK_STRUCT_DEFINITION: line.struct_def.location
  of LK_STRUCT_FIELD_DEFINITION: line.struct_field_def.location
  of LK_UNION_DEFINITION: line.union_def.location
  of LK_UNION_FIELD_DEFINITION: line.union_field_def.location
  of LK_MODULE_DEFINITION: line.module_def.location

proc `$`*(line: Line): string =
  case line.kind:
  of LK_FUNCTION_DEFINITION: $(line.func_def)
  of LK_STATEMENT: $(line.statement)
  of LK_MATCH_DEFINITION: $(line.match_def)
  of LK_CASE_DEFINITION: $(line.case_def)
  of LK_ELSE_DEFINITION: $(line.else_def)
  of LK_STRUCT_DEFINITION: $(line.struct_def)
  of LK_STRUCT_FIELD_DEFINITION: $(line.struct_field_def)
  of LK_UNION_DEFINITION: $(line.union_def)
  of LK_UNION_FIELD_DEFINITION: $(line.union_field_def)
  of LK_MODULE_DEFINITION: $(line.module_def)
