import sets, tables

import "../blocks"
import function_ref
import statement
import match


type
  ResolvedFunctionStepKind* = enum
    RFSK_STATEMENT, RFSK_MATCH
  ResolvedFunctionStep* = ref object of RootObj
    case kind: ResolvedFunctionStepKind
    of RFSK_STATEMENT:
      statement: ResolvedStatement
    of RFSK_MATCH:
      match: ResolvedMatch

proc function_refs*(function_step: ResolvedFunctionStep): Hashset[
    ResolvedFunctionRef] =
  case function_step.kind:
  of RFSK_STATEMENT: function_step.statement.function_refs
  of RFSK_MATCH: function_step.match.function_refs

proc generic_impls*(function_step: ResolvedFunctionStep): Table[string, Table[
    string, HashSet[string]]] =
  case function_step.kind:
  of RFSK_STATEMENT: function_step.statement.generic_impls
  of RFSK_MATCH: function_step.match.generic_impls

proc destination*(function_step: ResolvedFunctionStep): Token =
  case function_step.kind:
  of RFSK_STATEMENT: function_step.statement.destination
  of RFSK_MATCH: function_step.match.destination

proc return_argument*(function_step: ResolvedFunctionStep): ArgumentDefinition =
  case function_step.kind:
  of RFSK_STATEMENT: function_step.statement.return_argument
  of RFSK_MATCH: function_step.match.return_argument

proc c*(function_step: ResolvedFunctionStep): string =
  case function_step.kind:
  of RFSK_STATEMENT: function_step.statement.c
  of RFSK_MATCH: function_step.match.c

proc new_resolved_function_step*(statement: ResolvedStatement): ResolvedFunctionStep =
  ResolvedFunctionStep(kind: RFSK_STATEMENT, statement: statement)

proc new_resolved_function_step*(match: ResolvedMatch): ResolvedFunctionStep =
  ResolvedFunctionStep(kind: RFSK_MATCH, match: match)
