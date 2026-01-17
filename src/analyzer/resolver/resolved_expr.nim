# ResolvedExpression, ResolvedStatement, ResolvedCase, ResolvedElse, ResolvedMatch, ResolvedFunction
import results, strformat, sets

import resolved_call
export resolved_call

# =============================================================================
# Mutually Recursive Types: Expression, Statement, Case, Else, Match
# =============================================================================

type
  ResolvedExpressionKind* = enum
    TEK_MATCH, TEK_FNCALL, TEK_INIT, TEK_STRUCT_GET, TEK_VARIABLE
  ResolvedExpression* = ref object of RootObj
    case kind: ResolvedExpressionKind
    of TEK_MATCH: match: ResolvedMatch
    of TEK_FNCALL: fncall: ResolvedFunctionCall
    of TEK_INIT: init: ResolvedInitializer
    of TEK_STRUCT_GET: struct_get: ResolvedStructGet
    of TEK_VARIABLE: variable: ResolvedVariable
  ResolvedStatement* = ref object of RootObj
    arg: Identifier
    expression: ResolvedExpression
  ResolvedCase* = ref object of RootObj
    pattern: CasePattern
    location: Location
    statements: seq[ResolvedStatement]
  ResolvedElse* = ref object of RootObj
    location: Location
    statements: seq[ResolvedStatement]
  ResolvedMatchKind* = enum
    TMK_CASE_ONLY, TMK_COMPLETE
  ResolvedMatch* = ref object of RootObj
    location: Location
    operand: Identifier
    case_blocks: seq[ResolvedCase]
    case kind: ResolvedMatchKind
    of TMK_CASE_ONLY: discard
    of TMK_COMPLETE: else_block: ResolvedElse

# ResolvedExpression constructors
proc new_resolved_expression*(match: ResolvedMatch): ResolvedExpression =
  ResolvedExpression(kind: TEK_MATCH, match: match)

proc new_resolved_expression*(fncall: ResolvedFunctionCall): ResolvedExpression =
  ResolvedExpression(kind: TEK_FNCALL, fncall: fncall)

proc new_resolved_expression*(init: ResolvedInitializer): ResolvedExpression =
  ResolvedExpression(kind: TEK_INIT, init: init)

proc new_resolved_expression*(struct_get: ResolvedStructGet): ResolvedExpression =
  ResolvedExpression(kind: TEK_STRUCT_GET, struct_get: struct_get)

proc new_resolved_expression*(variable: ResolvedVariable): ResolvedExpression =
  ResolvedExpression(kind: TEK_VARIABLE, variable: variable)

# Forward declaration for mutual recursion
proc module_deps*(match: ResolvedMatch): HashSet[UserModule]

proc module_deps*(expression: ResolvedExpression): HashSet[UserModule] =
  case expression.kind:
  of TEK_MATCH: expression.match.module_deps
  of TEK_FNCALL: expression.fncall.module_deps
  of TEK_INIT: expression.init.module_deps
  of TEK_STRUCT_GET: expression.struct_get.module_deps
  of TEK_VARIABLE: expression.variable.module_deps

proc location*(match: ResolvedMatch): Location

proc location*(expression: ResolvedExpression): Location =
  case expression.kind:
  of TEK_MATCH: expression.match.location
  of TEK_FNCALL: expression.fncall.location
  of TEK_INIT: expression.init.location
  of TEK_STRUCT_GET: expression.struct_get.location
  of TEK_VARIABLE: expression.variable.location

proc kind*(expression: ResolvedExpression): ResolvedExpressionKind = expression.kind

proc match*(expression: ResolvedExpression): Result[ResolvedMatch, string] =
  case expression.kind:
  of TEK_MATCH: ok(expression.match)
  else: err(fmt"{expression.location} expected a match expression")

proc fncall*(expression: ResolvedExpression): Result[ResolvedFunctionCall, string] =
  case expression.kind:
  of TEK_FNCALL: ok(expression.fncall)
  else: err(fmt"{expression.location} expected a function call")

proc init*(expression: ResolvedExpression): Result[ResolvedInitializer, string] =
  case expression.kind:
  of TEK_INIT: ok(expression.init)
  else: err(fmt"{expression.location} expected an initilaizer")

proc struct_get*(expression: ResolvedExpression): Result[ResolvedStructGet, string] =
  case expression.kind:
  of TEK_STRUCT_GET: ok(expression.struct_get)
  else: err(fmt"{expression.location} expected a struct field accessor")

proc variable*(expression: ResolvedExpression): Result[ResolvedVariable, string] =
  case expression.kind:
  of TEK_VARIABLE: ok(expression.variable)
  else: err(fmt"{expression.location} expected a variable")

# ResolvedStatement
proc new_resolved_statement*(arg: Identifier,
    expression: ResolvedExpression): ResolvedStatement =
  ResolvedStatement(arg: arg, expression: expression)

proc module_deps*(statement: ResolvedStatement): HashSet[UserModule] =
  statement.expression.module_deps

proc arg*(statement: ResolvedStatement): Identifier = statement.arg
proc expression*(statement: ResolvedStatement): ResolvedExpression = statement.expression
proc location*(statement: ResolvedStatement): Location = statement.arg.location

# ResolvedCase
proc new_resolved_case*(pattern: CasePattern, statements: seq[
    ResolvedStatement], location: Location): ResolvedCase =
  ResolvedCase(pattern: pattern, statements: statements, location: location)

proc location*(case_block: ResolvedCase): Location = case_block.location
proc pattern*(case_block: ResolvedCase): CasePattern = case_block.pattern
proc statements*(case_block: ResolvedCase): seq[
    ResolvedStatement] = case_block.statements

proc module_deps*(case_block: ResolvedCase): HashSet[UserModule] =
  accumulate_module_deps(case_block.statements)

# ResolvedElse
proc new_resolved_else*(statements: seq[ResolvedStatement],
    location: Location): ResolvedElse =
  ResolvedElse(statements: statements, location: location)

proc location*(else_block: ResolvedElse): Location = else_block.location
proc statements*(else_block: ResolvedElse): seq[
    ResolvedStatement] = else_block.statements

proc module_deps*(else_block: ResolvedElse): HashSet[UserModule] =
  accumulate_module_deps(else_block.statements)

# ResolvedMatch
proc new_resolved_match*(operand: Identifier, arg: Identifier, case_blocks: seq[
    ResolvedCase], location: Location): ResolvedMatch =
  ResolvedMatch(kind: TMK_CASE_ONLY, operand: operand, case_blocks: case_blocks,
      location: location)

proc new_resolved_match*(operand: Identifier, arg: Identifier, case_blocks: seq[
    ResolvedCase], else_block: ResolvedElse,
        location: Location): ResolvedMatch =
  ResolvedMatch(kind: TMK_COMPLETE, operand: operand, case_blocks: case_blocks,
      else_block: else_block, location: location)

proc kind*(match: ResolvedMatch): ResolvedMatchKind = match.kind
proc location*(match: ResolvedMatch): Location = match.location
proc operand*(match: ResolvedMatch): Identifier = match.operand
proc case_blocks*(match: ResolvedMatch): seq[ResolvedCase] = match.case_blocks

proc else_block*(match: ResolvedMatch): Result[ResolvedElse, string] =
  case match.kind:
  of TMK_CASE_ONLY: err(fmt"{match.location} expected an else block")
  of TMK_COMPLETE: ok(match.else_block)

proc module_deps*(match: ResolvedMatch): HashSet[UserModule] =
  var module_set = accumulate_module_deps(match.case_blocks)
  case match.kind:
  of TMK_CASE_ONLY: discard
  of TMK_COMPLETE: module_set.incl(match.else_block.module_deps)
  module_set

# =============================================================================
# ResolvedFunction
# =============================================================================

type ResolvedFunction* = ref object of RootObj
  def: ResolvedFunctionDefinition
  steps: seq[ResolvedStatement]

proc new_resolved_function*(def: ResolvedFunctionDefinition, steps: seq[
    ResolvedStatement]): ResolvedFunction =
  ResolvedFunction(def: def, steps: steps)

proc module_deps*(function: ResolvedFunction): HashSet[UserModule] =
  var module_set = function.def.module_deps
  module_set.incl(accumulate_module_deps(function.steps))
  module_set

proc def*(function: ResolvedFunction): ResolvedFunctionDefinition = function.def
proc steps*(function: ResolvedFunction): seq[ResolvedStatement] = function.steps
