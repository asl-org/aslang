import results, strformat, sets, options

import parser
import defs
import fncall
import initializer

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
proc new_resolved_expression(match: ResolvedMatch): ResolvedExpression =
  ResolvedExpression(kind: TEK_MATCH, match: match)

proc new_resolved_expression(fncall: ResolvedFunctionCall): ResolvedExpression =
  ResolvedExpression(kind: TEK_FNCALL, fncall: fncall)

proc new_resolved_expression(init: ResolvedInitializer): ResolvedExpression =
  ResolvedExpression(kind: TEK_INIT, init: init)

proc new_resolved_expression(struct_get: ResolvedStructGet): ResolvedExpression =
  ResolvedExpression(kind: TEK_STRUCT_GET, struct_get: struct_get)

proc new_resolved_expression(variable: ResolvedVariable): ResolvedExpression =
  ResolvedExpression(kind: TEK_VARIABLE, variable: variable)

# Forward declaration for mutual recursion
proc module_deps*(match: ResolvedMatch): HashSet[Module]

proc module_deps*(expression: ResolvedExpression): HashSet[Module] =
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

# Forward Declaration needed due to cyclic dependencies
proc resolve(file: parser.File, module: Option[parser.Module],
    match: Match): Result[ResolvedMatch, string]

# Expression
proc resolve(file: parser.File, module: Option[parser.Module],
    expression: Expression): Result[ResolvedExpression, string] =
  case expression.kind:
  of EK_MATCH:
    ok(new_resolved_expression( ? resolve(file, module, ? expression.match)))
  of EK_FNCALL:
    ok(new_resolved_expression( ? resolve(file, module, ? expression.fncall)))
  of EK_INIT:
    ok(new_resolved_expression( ? resolve(file, module, ? expression.init)))
  of EK_STRUCT_GET:
    let sg = ? expression.struct_get
    ok(new_resolved_expression(new_resolved_struct_get(sg.name, sg.field)))
  of EK_VARIABLE:
    ok(new_resolved_expression(new_resolved_variable( ? expression.variable)))

# ResolvedStatement
proc new_resolved_statement(arg: Identifier,
    expression: ResolvedExpression): ResolvedStatement =
  ResolvedStatement(arg: arg, expression: expression)

proc module_deps*(statement: ResolvedStatement): HashSet[Module] =
  statement.expression.module_deps

proc arg*(statement: ResolvedStatement): Identifier = statement.arg
proc expression*(statement: ResolvedStatement): ResolvedExpression = statement.expression
proc location*(statement: ResolvedStatement): Location = statement.arg.location

proc resolve(file: parser.File, module: Option[parser.Module],
    statement: Statement): Result[ResolvedStatement, string] =
  let resolved_expression = ? resolve(file, module, statement.expression)
  ok(new_resolved_statement(statement.arg, resolved_expression))

proc resolve*(file: parser.File, module: Option[parser.Module],
    statements: seq[Statement]): Result[seq[ResolvedStatement], string] =
  var resolved_statements: seq[ResolvedStatement]
  for statement in statements:
    let resolved_statement = ? resolve(file, module, statement)
    resolved_statements.add(resolved_statement)
  ok(resolved_statements)

# ResolvedCase
proc new_resolved_case(pattern: CasePattern, statements: seq[
    ResolvedStatement], location: Location): ResolvedCase =
  ResolvedCase(pattern: pattern, statements: statements, location: location)

proc location*(case_block: ResolvedCase): Location = case_block.location
proc pattern*(case_block: ResolvedCase): CasePattern = case_block.pattern
proc statements*(case_block: ResolvedCase): seq[
    ResolvedStatement] = case_block.statements

proc module_deps*(case_block: ResolvedCase): HashSet[Module] =
  var module_set: HashSet[Module]
  for statement in case_block.statements: module_set.incl(statement.module_deps)
  module_set

proc resolve(file: parser.File, module: Option[parser.Module],
    case_block: Case): Result[ResolvedCase, string] =
  let resolved_stmts = ? resolve(file, module,
      case_block.statements)
  ok(new_resolved_case(case_block.def.pattern, resolved_stmts,
      case_block.def.location))

# ResolvedElse
proc new_resolved_else(statements: seq[ResolvedStatement],
    location: Location): ResolvedElse =
  ResolvedElse(statements: statements, location: location)

proc location*(else_block: ResolvedElse): Location = else_block.location
proc statements*(else_block: ResolvedElse): seq[
    ResolvedStatement] = else_block.statements

proc module_deps*(else_block: ResolvedElse): HashSet[Module] =
  var module_set: HashSet[Module]
  for statement in else_block.statements: module_set.incl(statement.module_deps)
  module_set

proc resolve(file: parser.File, module: Option[parser.Module],
    else_block: Else): Result[ResolvedElse, string] =
  let resolved_stmts = ? resolve(file, module,
      else_block.statements)
  ok(new_resolved_else(resolved_stmts, else_block.location))

# ResolvedMatch
proc new_resolved_match(operand: Identifier, arg: Identifier, case_blocks: seq[
    ResolvedCase], location: Location): ResolvedMatch =
  ResolvedMatch(kind: TMK_CASE_ONLY, operand: operand, case_blocks: case_blocks,
      location: location)

proc new_resolved_match(operand: Identifier, arg: Identifier, case_blocks: seq[
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

proc module_deps*(match: ResolvedMatch): HashSet[Module] =
  var module_set: HashSet[Module]
  for case_block in match.case_blocks: module_set.incl(case_block.module_deps)
  case match.kind:
  of TMK_CASE_ONLY: discard
  of TMK_COMPLETE: module_set.incl(match.else_block.module_deps)
  module_set

proc resolve(file: parser.File, module: Option[parser.Module],
    match: Match): Result[ResolvedMatch, string] =
  var resolved_cases: seq[ResolvedCase]
  for case_block in match.case_blocks:
    let resolved_case = ? resolve(file, module, case_block)
    resolved_cases.add(resolved_case)

  case match.kind:
  of MK_CASE_ONLY:
    ok(new_resolved_match(match.def.operand, match.def.arg, resolved_cases,
        match.def.location))
  of MK_COMPLETE:
    let resolved_else = ? resolve(file, module, ? match.else_block)
    ok(new_resolved_match(match.def.operand, match.def.arg, resolved_cases,
        resolved_else, match.def.location))

# =============================================================================
# ResolvedUserFunction
# =============================================================================

type ResolvedUserFunction* = ref object of RootObj
  def: ResolvedFunctionDefinition
  steps: seq[ResolvedStatement]

proc new_resolved_user_function(def: ResolvedFunctionDefinition,
    steps: seq[ResolvedStatement]): ResolvedUserFunction =
  ResolvedUserFunction(def: def, steps: steps)

proc module_deps*(function: ResolvedUserFunction): HashSet[Module] =
  var module_set = function.def.module_deps
  for step in function.steps: module_set.incl(step.module_deps)
  module_set

proc def*(function: ResolvedUserFunction): ResolvedFunctionDefinition = function.def
proc steps*(function: ResolvedUserFunction): seq[
    ResolvedStatement] = function.steps

proc resolve*(file: parser.File, module: Option[parser.Module],
    function: Function): Result[ResolvedUserFunction, string] =
  let resolved_def = ? resolve(file, module, function.def)
  let resolved_steps = ? resolve(file, module, function.steps)
  ok(new_resolved_user_function(resolved_def, resolved_steps))

# =============================================================================
# ResolvedExternFunction
# =============================================================================
type ResolvedExternFunction* = ref object of RootObj
  extern: string
  def: ResolvedFunctionDefinition

proc new_resolved_extern_function(extern: string,
    def: ResolvedFunctionDefinition): ResolvedExternFunction =
  ResolvedExternFunction(extern: extern, def: def)

proc extern*(function: ResolvedExternFunction): string = function.extern
proc def*(function: ResolvedExternFunction): ResolvedFunctionDefinition = function.def
proc module_deps*(function: ResolvedExternFunction): HashSet[Module] =
  init_hashset[Module]()

# =============================================================================
# ResolvedFunction
# =============================================================================

type
  ResolvedFunctionKind* = enum
    RFK_USER, RFK_EXTERN
  ResolvedFunction* = ref object of RootObj
    case kind: ResolvedFunctionKind
    of RFK_EXTERN: extern: ResolvedExternFunction
    of RFK_USER: user: ResolvedUserFunction

proc new_resolved_function*(function: ResolvedUserFunction): ResolvedFunction =
  ResolvedFunction(kind: RFK_USER, user: function)

proc new_resolved_function*(function: ResolvedExternFunction): ResolvedFunction =
  ResolvedFunction(kind: RFK_EXTERN, extern: function)

proc kind*(function: ResolvedFunction): ResolvedFunctionKind = function.kind

proc extern_name*(function: ResolvedFunction): Option[string] =
  case function.kind:
  of RFK_EXTERN: some(function.extern.extern)
  of RFK_USER: none(string)

proc extern*(function: ResolvedFunction): ResolvedExternFunction =
  do_assert function.kind == RFK_EXTERN, "expected extern function"
  function.extern

proc user*(function: ResolvedFunction): ResolvedUserFunction =
  do_assert function.kind == RFK_USER, "expected user function"
  function.user

proc def*(function: ResolvedFunction): ResolvedFunctionDefinition =
  case function.kind:
  of RFK_EXTERN: function.extern.def
  of RFK_USER: function.user.def

proc module_deps*(function: ResolvedFunction): HashSet[Module] =
  case function.kind:
  of RFK_USER: function.user.module_deps
  of RFK_EXTERN: function.extern.module_deps

proc resolve*(file: parser.File, module: parser.Module,
    function: Function): Result[ResolvedFunction, string] =
  case function.kind:
  of FK_EXTERN:
    let resolved_def = ? resolve(file, some(module), function.def)
    let extern_function = new_resolved_extern_function(
        function.extern_func.extern, resolved_def)
    ok(new_resolved_function(extern_function))
  of FK_USER:
    let resolved_def = ? resolve(file, some(module), function.def)
    let resolved_steps = ? resolve(file, some(module), function.steps)
    let user_function = new_resolved_user_function(resolved_def, resolved_steps)
    ok(new_resolved_function(user_function))
