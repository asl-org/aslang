import sets

import "../blocks"
import function_call
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

proc function_set*(function_step: ResolvedFunctionStep): Hashset[
    ExternalFunction] =
  case function_step.kind:
  of RFSK_STATEMENT: function_step.statement.function_set
  of RFSK_MATCH: function_step.match.function_set

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
