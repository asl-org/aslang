import results

import core, identifier, defs, expression
import ../../utils

# =============================================================================
# UserFunction
# =============================================================================

struct UserFunction:
  def: FunctionDefinition
  steps: seq[Statement]

proc new_user_function*(def: FunctionDefinition, steps: seq[Statement]): Result[
    UserFunction, core.Error] =
  if steps.len == 0:
    return err(err_parser_empty_function(def.location, def.name.asl))
  ok(UserFunction(def: def, steps: steps))

# =============================================================================
# ExternFunction
# =============================================================================

struct ExternFunction:
  def: FunctionDefinition
  extern: string
  expanded: bool

proc new_extern_function*(def: FunctionDefinition,
    extern: string, expanded: bool = false): ExternFunction =
  ExternFunction(def: def, extern: extern, expanded: expanded)

proc name*(function: ExternFunction): Identifier = function.def.name

# =============================================================================
# Function (Unified)
# =============================================================================

union Function:
  FK_USER:
    user_func: UserFunction
  FK_EXTERN:
    extern_func: ExternFunction

proc new_function*(user_func: UserFunction): Function =
  Function(kind: FK_USER, user_func: user_func)

proc new_function*(extern_func: ExternFunction): Function =
  Function(kind: FK_EXTERN, extern_func: extern_func)

proc def*(function: Function): FunctionDefinition =
  variant function:
  of FK_USER(user_func): user_func.def
  of FK_EXTERN(extern_func): extern_func.def

proc steps*(function: Function): seq[Statement] =
  variant function:
  of FK_USER(user_func): user_func.steps
  of FK_EXTERN: @[]

proc location*(function: Function): Location = function.def.location
proc name*(function: Function): Identifier = function.def.name

proc asl*(function: Function, indent: string): seq[string] =
  let header = function.def.asl

  var lines: seq[string]
  for step in steps(function):
    for line in step.asl(indent):
      lines.add(indent & line)

  return (@[header] & lines)

proc user_function_spec(parser: Parser, indent: int): Result[UserFunction,
    core.Error] =
  let def = ? parser.expect(function_definition_spec, indent)
  discard ? parser.expect_at_least_one(empty_line_spec)

  let steps = ? parser.non_empty_list_spec(statement_spec, indent + 1,
      optional_empty_line_spec)
  new_user_function(def, steps)

proc extern_header_spec(parser: Parser, indent: int): Result[Identifier,
    core.Error] =
  discard ? parser.expect(indent_spec, indent)
  discard ? parser.expect(extern_keyword_spec)
  discard ? parser.expect_at_least_one(space_spec)
  let extern = ? parser.expect(identifier_spec)
  discard ? parser.expect_any(space_spec)
  discard ? parser.expect(colon_spec)
  ok(extern)

proc extern_function_spec(parser: Parser, indent: int): Result[ExternFunction,
    core.Error] =
  let extern = ? parser.expect(extern_header_spec, indent)
  discard ? parser.expect_at_least_one(empty_line_spec)
  let def = ? parser.expect(function_definition_spec, indent + 1)
  ok(new_extern_function(def, extern.asl))

proc function_spec*(parser: Parser, indent: int): Result[Function,
    core.Error] =
  var errors: seq[core.Error]
  let maybe_user_func = parser.expect(user_function_spec, indent)
  if maybe_user_func.is_ok: return ok(new_function(maybe_user_func.get))
  else: errors.add(maybe_user_func.error)

  let maybe_extern_func = parser.expect(extern_function_spec, indent)
  if maybe_extern_func.is_ok: return ok(new_function(maybe_extern_func.get))
  else: errors.add(maybe_extern_func.error)

  err(errors.max())
