# TypedExpression, TypedStatement, TypedCase, TypedElse, TypedMatch, TypedFunction
import results, strformat, sets

import typed_call
export typed_call

# =============================================================================
# Mutually Recursive Types: Expression, Statement, Case, Else, Match
# =============================================================================

type
  TypedExpressionKind* = enum
    TEK_MATCH, TEK_FNCALL, TEK_INIT, TEK_STRUCT_GET, TEK_VARIABLE
  TypedExpression* = ref object of RootObj
    case kind: TypedExpressionKind
    of TEK_MATCH: match: TypedMatch
    of TEK_FNCALL: fncall: TypedFunctionCall
    of TEK_INIT: init: TypedInitializer
    of TEK_STRUCT_GET: struct_get: TypedStructGet
    of TEK_VARIABLE: variable: TypedVariable
  TypedStatement* = ref object of RootObj
    arg: Identifier
    expression: TypedExpression
  TypedCase* = ref object of RootObj
    pattern: CasePattern
    location: Location
    statements: seq[TypedStatement]
  TypedElse* = ref object of RootObj
    location: Location
    statements: seq[TypedStatement]
  TypedMatchKind* = enum
    TMK_CASE_ONLY, TMK_COMPLETE
  TypedMatch* = ref object of RootObj
    location: Location
    operand: Identifier
    case_blocks: seq[TypedCase]
    case kind: TypedMatchKind
    of TMK_CASE_ONLY: discard
    of TMK_COMPLETE: else_block: TypedElse

# TypedExpression constructors
proc new_typed_expression*(match: TypedMatch): TypedExpression =
  TypedExpression(kind: TEK_MATCH, match: match)

proc new_typed_expression*(fncall: TypedFunctionCall): TypedExpression =
  TypedExpression(kind: TEK_FNCALL, fncall: fncall)

proc new_typed_expression*(init: TypedInitializer): TypedExpression =
  TypedExpression(kind: TEK_INIT, init: init)

proc new_typed_expression*(struct_get: TypedStructGet): TypedExpression =
  TypedExpression(kind: TEK_STRUCT_GET, struct_get: struct_get)

proc new_typed_expression*(variable: TypedVariable): TypedExpression =
  TypedExpression(kind: TEK_VARIABLE, variable: variable)

# Forward declaration for mutual recursion
proc module_deps*(match: TypedMatch): HashSet[UserModule]

proc module_deps*(expression: TypedExpression): HashSet[UserModule] =
  case expression.kind:
  of TEK_MATCH: expression.match.module_deps
  of TEK_FNCALL: expression.fncall.module_deps
  of TEK_INIT: expression.init.module_deps
  of TEK_STRUCT_GET: expression.struct_get.module_deps
  of TEK_VARIABLE: expression.variable.module_deps

proc location*(match: TypedMatch): Location

proc location*(expression: TypedExpression): Location =
  case expression.kind:
  of TEK_MATCH: expression.match.location
  of TEK_FNCALL: expression.fncall.location
  of TEK_INIT: expression.init.location
  of TEK_STRUCT_GET: expression.struct_get.location
  of TEK_VARIABLE: expression.variable.location

proc kind*(expression: TypedExpression): TypedExpressionKind = expression.kind

proc match*(expression: TypedExpression): Result[TypedMatch, string] =
  case expression.kind:
  of TEK_MATCH: ok(expression.match)
  else: err(fmt"{expression.location} expected a match expression")

proc fncall*(expression: TypedExpression): Result[TypedFunctionCall, string] =
  case expression.kind:
  of TEK_FNCALL: ok(expression.fncall)
  else: err(fmt"{expression.location} expected a function call")

proc init*(expression: TypedExpression): Result[TypedInitializer, string] =
  case expression.kind:
  of TEK_INIT: ok(expression.init)
  else: err(fmt"{expression.location} expected an initilaizer")

proc struct_get*(expression: TypedExpression): Result[TypedStructGet, string] =
  case expression.kind:
  of TEK_STRUCT_GET: ok(expression.struct_get)
  else: err(fmt"{expression.location} expected a struct field accessor")

proc variable*(expression: TypedExpression): Result[TypedVariable, string] =
  case expression.kind:
  of TEK_VARIABLE: ok(expression.variable)
  else: err(fmt"{expression.location} expected a variable")

# TypedStatement
proc new_typed_statement*(arg: Identifier,
    expression: TypedExpression): TypedStatement =
  TypedStatement(arg: arg, expression: expression)

proc module_deps*(statement: TypedStatement): HashSet[UserModule] =
  statement.expression.module_deps

proc arg*(statement: TypedStatement): Identifier = statement.arg
proc expression*(statement: TypedStatement): TypedExpression = statement.expression
proc location*(statement: TypedStatement): Location = statement.arg.location

# TypedCase
proc new_typed_case*(pattern: CasePattern, statements: seq[TypedStatement],
    location: Location): TypedCase =
  TypedCase(pattern: pattern, statements: statements, location: location)

proc location*(case_block: TypedCase): Location = case_block.location
proc pattern*(case_block: TypedCase): CasePattern = case_block.pattern
proc statements*(case_block: TypedCase): seq[
    TypedStatement] = case_block.statements

proc module_deps*(case_block: TypedCase): HashSet[UserModule] =
  accumulate_module_deps(case_block.statements)

# TypedElse
proc new_typed_else*(statements: seq[TypedStatement],
    location: Location): TypedElse =
  TypedElse(statements: statements, location: location)

proc location*(else_block: TypedElse): Location = else_block.location
proc statements*(else_block: TypedElse): seq[
    TypedStatement] = else_block.statements

proc module_deps*(else_block: TypedElse): HashSet[UserModule] =
  accumulate_module_deps(else_block.statements)

# TypedMatch
proc new_typed_match*(operand: Identifier, arg: Identifier, case_blocks: seq[
    TypedCase], location: Location): TypedMatch =
  TypedMatch(kind: TMK_CASE_ONLY, operand: operand, case_blocks: case_blocks,
      location: location)

proc new_typed_match*(operand: Identifier, arg: Identifier, case_blocks: seq[
    TypedCase], else_block: TypedElse, location: Location): TypedMatch =
  TypedMatch(kind: TMK_COMPLETE, operand: operand, case_blocks: case_blocks,
      else_block: else_block, location: location)

proc kind*(match: TypedMatch): TypedMatchKind = match.kind
proc location*(match: TypedMatch): Location = match.location
proc operand*(match: TypedMatch): Identifier = match.operand
proc case_blocks*(match: TypedMatch): seq[TypedCase] = match.case_blocks

proc else_block*(match: TypedMatch): Result[TypedElse, string] =
  case match.kind:
  of TMK_CASE_ONLY: err(fmt"{match.location} expected an else block")
  of TMK_COMPLETE: ok(match.else_block)

proc module_deps*(match: TypedMatch): HashSet[UserModule] =
  var module_set = accumulate_module_deps(match.case_blocks)
  case match.kind:
  of TMK_CASE_ONLY: discard
  of TMK_COMPLETE: module_set.incl(match.else_block.module_deps)
  module_set

# =============================================================================
# TypedFunction
# =============================================================================

type TypedFunction* = ref object of RootObj
  def: TypedFunctionDefinition
  steps: seq[TypedStatement]

proc new_typed_function*(def: TypedFunctionDefinition, steps: seq[
    TypedStatement]): TypedFunction =
  TypedFunction(def: def, steps: steps)

proc module_deps*(function: TypedFunction): HashSet[UserModule] =
  var module_set = function.def.module_deps
  module_set.incl(accumulate_module_deps(function.steps))
  module_set

proc def*(function: TypedFunction): TypedFunctionDefinition = function.def
proc steps*(function: TypedFunction): seq[TypedStatement] = function.steps
