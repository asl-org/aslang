import results

import ../parser
import ../../utils

# Expression flattening: desugars nested expression arguments (AK_FNCALL,
# AK_STRUCT_INIT) into temp variable statements so downstream phases see
# only flat AK_VARIABLE/AK_LITERAL arguments.

proc as_string[T](r: Result[T, core.Error]): Result[T, string] =
  if r.is_err: err($r.error)
  else: ok(r.get)

proc flatten_arguments(args: seq[Argument]): Result[(seq[Statement], seq[
    Argument]), string]
proc flatten_keyword_arguments(kwargs: seq[KeywordArgument]): Result[(seq[
    Statement], seq[KeywordArgument]), string]
proc flatten_expression(expression: Expression): Result[(seq[Statement],
    Expression), string]
proc flatten_match(match: Match): Result[Match, string]
proc flatten_statements*(steps: seq[Statement]): Result[seq[Statement], string]

# --- Core: flatten a single argument ---

proc flatten_argument(arg: Argument): Result[(seq[Statement], Argument),
    string] =
  variant arg:
  of AK_LITERAL, AK_VARIABLE:
    return ok((@[], arg))
  of AK_FNCALL(fncall):
    let (inner_prefix, new_args) = ? flatten_arguments(fncall.args)
    let new_fncall = ? new_function_call(fncall.fnref, new_args).as_string
    let temp = new_identifier(fncall.location)
    let expr = new_expression(new_fncall)
    let stmt = new_statement(temp, expr)
    ok((inner_prefix & @[stmt], new_argument(temp)))
  of AK_STRUCT_INIT(struct_init):
    let (inner_prefix, new_kwargs) = ? flatten_keyword_arguments(
        struct_init.args)
    let new_si = ? new_struct_init(struct_init.struct_ref,
        new_kwargs).as_string
    let temp = new_identifier(struct_init.location)
    let expr = new_expression(new_initializer(new_si))
    let stmt = new_statement(temp, expr)
    ok((inner_prefix & @[stmt], new_argument(temp)))

proc flatten_arguments(args: seq[Argument]): Result[(seq[Statement], seq[
    Argument]), string] =
  var prefix: seq[Statement]
  var new_args: seq[Argument]
  for arg in args:
    let (arg_prefix, new_arg) = ? flatten_argument(arg)
    prefix.add(arg_prefix)
    new_args.add(new_arg)
  ok((prefix, new_args))

proc flatten_keyword_arguments(kwargs: seq[KeywordArgument]): Result[(seq[
    Statement], seq[KeywordArgument]), string] =
  var prefix: seq[Statement]
  var new_kwargs: seq[KeywordArgument]
  for kwarg in kwargs:
    let (arg_prefix, new_arg) = ? flatten_argument(kwarg.value)
    prefix.add(arg_prefix)
    new_kwargs.add(new_keyword_argument(kwarg.name, new_arg))
  ok((prefix, new_kwargs))

# --- Flatten an expression (recurse into match bodies) ---

proc flatten_expression(expression: Expression): Result[(seq[Statement],
    Expression), string] =
  variant expression:
  of EK_FNCALL(fncall):
    let (prefix, new_args) = ? flatten_arguments(fncall.args)
    if prefix.len == 0: return ok((@[], expression))
    let new_fncall = ? new_function_call(fncall.fnref,
        new_args).as_string
    ok((prefix, new_expression(new_fncall)))
  of EK_INIT(init):
    variant init:
    of IK_STRUCT(struct):
      let (prefix, new_kwargs) = ? flatten_keyword_arguments(
          struct.args)
      if prefix.len == 0: return ok((@[], expression))
      let new_si = ? new_struct_init(struct.struct_ref,
          new_kwargs).as_string
      ok((prefix, new_expression(new_initializer(new_si))))
    of IK_LITERAL:
      ok((@[], expression))
  of EK_MATCH(m):
    let new_match = ? flatten_match(m)
    ok((@[], new_expression(new_match)))
  of EK_STRUCT_GET, EK_VARIABLE:
    ok((@[], expression))

# --- Flatten match (recurse into case/else bodies) ---

proc flatten_match(match: Match): Result[Match, string] =
  var new_cases: seq[Case]
  for case_block in match.case_blocks:
    let new_stmts = ? flatten_statements(case_block.statements)
    new_cases.add( ? new_case(case_block.def, new_stmts).as_string)

  variant match:
  of MK_CASE_ONLY:
    new_match(match.def, new_cases).as_string
  of MK_COMPLETE:
    let new_else_stmts = ? flatten_statements(match.else_block.statements)
    let new_else = ? new_else(new_else_stmts, match.else_block.location).as_string
    new_match(match.def, new_cases, new_else).as_string

# --- Flatten a statement list ---

proc flatten_statements*(steps: seq[Statement]): Result[seq[Statement],
    string] =
  var flattened: seq[Statement]
  for step in steps:
    let (prefix, new_expr) = ? flatten_expression(step.expression)
    flattened.add(prefix)
    case step.kind:
    of SK_ASSIGNED:
      flattened.add(new_statement(step.arg, new_expr))
    of SK_AUTO:
      flattened.add(new_statement(new_expr))
  ok(flattened)
