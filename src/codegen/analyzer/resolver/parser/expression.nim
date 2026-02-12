import results, strformat

import core, identifier, arg, initializer, pattern

# =============================================================================
# Mutually Recursive Types: Expression, Statement, Case, Else, Match
# =============================================================================

type
  ExpressionKind* = enum
    EK_MATCH, EK_FNCALL, EK_INIT, EK_STRUCT_GET, EK_VARIABLE
  StatementKind* = enum
    SK_ASSIGNED, SK_AUTO
  MatchKind* = enum
    MK_CASE_ONLY, MK_COMPLETE

# Mutually recursive types - all defined together
type
  Expression* = ref object of RootObj
    case kind: ExpressionKind
    of EK_MATCH: match: Match
    of EK_FNCALL: fncall: FunctionCall
    of EK_INIT: init: Initializer
    of EK_STRUCT_GET: struct_get: StructGet
    of EK_VARIABLE: variable: Identifier

  Statement* = ref object of RootObj
    kind: StatementKind
    arg: Identifier
    expression: Expression

  Case* = ref object of RootObj
    def: CaseDefinition
    statements: seq[Statement]

  Else* = ref object of RootObj
    statements: seq[Statement]
    location: Location

  Match* = ref object of RootObj
    def: MatchDefinition
    case_blocks: seq[Case]
    case kind: MatchKind
    of MK_CASE_ONLY: discard
    of MK_COMPLETE: else_block: Else


# =============================================================================
# Forward declarations for procs with mutual recursion
# =============================================================================

proc location*(match: Match): Location
proc asl*(match: Match, indent: string): seq[string]
proc match_spec*(parser: Parser, indent: int): Result[Match, core.Error]

# =============================================================================
# Expression
# =============================================================================

proc new_expression*(match: Match): Expression =
  Expression(kind: EK_MATCH, match: match)

proc new_expression*(fncall: FunctionCall): Expression =
  Expression(kind: EK_FNCALL, fncall: fncall)

proc new_expression*(init: Initializer): Expression =
  Expression(kind: EK_INIT, init: init)

proc new_expression*(struct_get: StructGet): Expression =
  Expression(kind: EK_STRUCT_GET, struct_get: struct_get)

proc new_expression*(variable: Identifier): Expression =
  Expression(kind: EK_VARIABLE, variable: variable)

proc location*(expression: Expression): Location =
  case expression.kind:
  of EK_MATCH: expression.match.location
  of EK_FNCALL: expression.fncall.location
  of EK_INIT: expression.init.location
  of EK_STRUCT_GET: expression.struct_get.location
  of EK_VARIABLE: expression.variable.location

proc asl*(expression: Expression, indent: string): seq[string] =
  case expression.kind:
  of EK_MATCH: expression.match.asl(indent)
  of EK_FNCALL: @[expression.fncall.asl]
  of EK_INIT: @[expression.init.asl]
  of EK_STRUCT_GET: @[expression.struct_get.asl]
  of EK_VARIABLE: @[expression.variable.asl]

proc kind*(expression: Expression): ExpressionKind = expression.kind

proc match*(expression: Expression): Match =
  do_assert expression.kind == EK_MATCH, fmt"{expression.location} expression is not a match"
  expression.match

proc fncall*(expression: Expression): FunctionCall =
  do_assert expression.kind == EK_FNCALL, fmt"{expression.location} expression is not a function call"
  expression.fncall

proc init*(expression: Expression): Initializer =
  do_assert expression.kind == EK_INIT, fmt"{expression.location} expression is not an initializer"
  expression.init

proc struct_get*(expression: Expression): StructGet =
  do_assert expression.kind == EK_STRUCT_GET, fmt"{expression.location} expression is not a struct get"
  expression.struct_get

proc variable*(expression: Expression): Identifier =
  do_assert expression.kind == EK_VARIABLE, fmt"{expression.location} expression is not a variable"
  expression.variable

proc expression_spec*(parser: Parser, indent: int): Result[Expression,
    core.Error] =
  var errors: seq[core.Error]

  let maybe_match = parser.expect(match_spec, indent)
  if maybe_match.is_ok: return ok(new_expression(maybe_match.get))
  else: errors.add(maybe_match.error)

  let maybe_fncall = parser.expect(function_call_spec)
  if maybe_fncall.is_ok: return ok(new_expression(maybe_fncall.get))
  else: errors.add(maybe_fncall.error)

  let maybe_init = parser.expect(initializer_spec)
  if maybe_init.is_ok: return ok(new_expression(maybe_init.get))
  else: errors.add(maybe_init.error)

  let maybe_struct_get = parser.expect(struct_get_spec)
  if maybe_struct_get.is_ok: return ok(new_expression(maybe_struct_get.get))
  else: errors.add(maybe_struct_get.error)

  let maybe_variable = parser.expect(identifier_spec)
  if maybe_variable.is_ok: return ok(new_expression(maybe_variable.get))
  else: errors.add(maybe_variable.error)

  return err(errors.max())

# =============================================================================
# Statement
# =============================================================================

proc new_statement*(expression: Expression): Statement =
  let arg = new_identifier(expression.location)
  Statement(kind: SK_AUTO, arg: arg, expression: expression)

proc new_statement*(arg: Identifier, expression: Expression): Statement =
  Statement(kind: SK_ASSIGNED, arg: arg, expression: expression)

proc location*(statement: Statement): Location = statement.arg.location
proc expression*(statement: Statement): Expression = statement.expression
proc arg*(statement: Statement): Identifier = statement.arg

proc asl*(statement: Statement, indent: string): seq[string] =
  var lines = statement.expression.asl(indent)
  case statement.kind:
  of SK_AUTO: discard
  of SK_ASSIGNED: lines[0] = fmt"{statement.arg.asl} = {lines[0]}"
  return lines

proc assignment_spec(parser: Parser, indent: int): Result[Statement,
    core.Error] =
  let arg = ? parser.expect(identifier_spec)
  discard ? parser.expect_any(space_spec)
  discard ? parser.expect(equal_spec)
  discard ? parser.expect_any(space_spec)
  let expression = ? parser.expect(expression_spec, indent)
  ok(new_statement(arg, expression))

proc statement_spec*(parser: Parser, indent: int): Result[Statement,
    core.Error] =
  var errors: seq[core.Error]
  discard ? parser.expect(indent_spec, indent)

  let maybe_assignment = parser.expect(assignment_spec, indent)
  if maybe_assignment.is_ok: return maybe_assignment
  else: errors.add(maybe_assignment.error)

  let maybe_expression = parser.expect(expression_spec, indent)
  if maybe_expression.is_ok: return ok(new_statement(maybe_expression.get))
  else: errors.add(maybe_expression.error)

  err(errors.max())

# =============================================================================
# Case
# =============================================================================

proc new_case*(def: CaseDefinition, statements: seq[Statement]): Result[Case,
    core.Error] =
  if statements.len == 0: return err(err_parser_empty_case(def.location))
  ok(Case(def: def, statements: statements))

proc location*(case_block: Case): Location =
  case_block.def.location

proc def*(case_block: Case): CaseDefinition = case_block.def
proc statements*(case_block: Case): seq[Statement] = case_block.statements

proc asl*(case_block: Case, indent: string): seq[string] =
  let header = case_block.def.asl
  var statements: seq[string]
  for statement in case_block.statements:
    for line in statement.asl(indent):
      statements.add(indent & line)
  return (@[header] & statements)

proc case_spec(parser: Parser, indent: int): Result[Case, core.Error] =
  discard ? parser.expect(indent_spec, indent)
  let case_def = ? parser.expect(case_definition_spec)
  discard ? parser.expect_any(empty_line_spec)
  let statements = ? parser.non_empty_list_spec(statement_spec, indent + 1,
      optional_empty_line_spec)
  new_case(case_def, statements)

# =============================================================================
# Else
# =============================================================================

proc new_else*(statements: seq[Statement], location: Location): Result[Else,
    core.Error] =
  if statements.len == 0:
    return err(err_parser_empty_else(location))

  ok(Else(statements: statements, location: location))

proc location*(else_block: Else): Location = else_block.location
proc statements*(else_block: Else): seq[Statement] = else_block.statements

proc asl*(else_block: Else, indent: string): seq[string] =
  let header = "else: "

  var statements: seq[string]
  for statement in else_block.statements:
    for line in statement.asl(indent):
      statements.add(indent & line)

  return (@[header] & statements)

proc else_spec(parser: Parser, indent: int): Result[Else, core.Error] =
  discard ? parser.expect(indent_spec, indent)

  let else_def = ? parser.expect(else_keyword_spec)
  discard ? parser.expect_any(space_spec)
  discard ? parser.expect(colon_spec)
  discard ? parser.expect_any(empty_line_spec)

  let statements = ? parser.non_empty_list_spec(statement_spec, indent + 1,
      optional_empty_line_spec)
  new_else(statements, else_def.location)

# =============================================================================
# Match
# =============================================================================

proc new_match*(def: MatchDefinition, case_blocks: seq[Case]): Result[Match,
    core.Error] =
  if case_blocks.len < 2:
    return err(err_parser_empty_match(def.location))
  ok(Match(kind: MK_CASE_ONLY, def: def, case_blocks: case_blocks))

proc new_match*(def: MatchDefinition, case_blocks: seq[Case],
    else_block: Else): Result[Match, core.Error] =
  if case_blocks.len < 1:
    return err(err_parser_empty_match_with_else(def.location))

  ok(Match(kind: MK_COMPLETE, def: def, case_blocks: case_blocks,
      else_block: else_block))

proc location*(match: Match): Location =
  match.def.location

proc def*(match: Match): MatchDefinition = match.def

proc kind*(match: Match): MatchKind = match.kind
proc case_blocks*(match: Match): seq[Case] = match.case_blocks

proc else_block*(match: Match): Else =
  do_assert match.kind == MK_COMPLETE, fmt"{match.location} match block does not have any else block"
  match.else_block

proc asl*(match: Match, indent: string): seq[string] =
  let header = match.def.asl

  var lines: seq[string]
  for case_block in match.case_blocks:
    for line in case_block.asl(indent):
      lines.add(indent & line)

  case match.kind:
  of MK_CASE_ONLY: discard
  of MK_COMPLETE:
    for line in match.else_block.asl(indent):
      lines.add(indent & line)

  return (@[header] & lines)

proc match_spec*(parser: Parser, indent: int): Result[Match, core.Error] =
  let match_def = ? parser.expect(match_definition_spec)

  discard ? parser.expect_any(empty_line_spec)
  let cases = ? parser.non_empty_list_spec(case_spec, indent + 1,
      optional_empty_line_spec)

  var maybe_else = parser.expect(else_spec, indent + 1)
  if maybe_else.is_ok:
    return new_match(match_def, cases, maybe_else.get)

  return new_match(match_def, cases)
