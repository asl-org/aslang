import results

import ../parser

# Expression flattening: desugars nested expression arguments (AK_FNCALL,
# AK_STRUCT_INIT) into temp variable statements so downstream phases see
# only flat AK_VARIABLE/AK_LITERAL arguments.

proc flatten_arguments(args: seq[Argument]): (seq[Statement], seq[Argument])
proc flatten_keyword_arguments(kwargs: seq[
    KeywordArgument]): (seq[Statement], seq[KeywordArgument])
proc flatten_expression(expression: Expression): (seq[Statement], Expression)
proc flatten_match(match: Match): Match
proc flatten_statements*(steps: seq[Statement]): seq[Statement]

# --- Core: flatten a single argument ---

proc flatten_argument(arg: Argument): (seq[Statement], Argument) =
  case arg.kind:
  of AK_LITERAL, AK_VARIABLE:
    return (@[], arg)
  of AK_FNCALL:
    # Recursively flatten the inner call's arguments first
    let (inner_prefix, new_args) = flatten_arguments(arg.fncall.args)
    let new_fncall = new_function_call(arg.fncall.fnref, new_args).get
    let temp = new_identifier(arg.fncall.location)
    let expr = new_expression(new_fncall)
    let stmt = new_statement(temp, expr)
    return (inner_prefix & @[stmt], new_argument(temp))
  of AK_STRUCT_INIT:
    # Recursively flatten the keyword argument values
    let (inner_prefix, new_kwargs) = flatten_keyword_arguments(
        arg.struct_init.args)
    let new_si = new_struct_init(arg.struct_init.struct_ref, new_kwargs).get
    let temp = new_identifier(arg.struct_init.location)
    let expr = new_expression(new_initializer(new_si))
    let stmt = new_statement(temp, expr)
    return (inner_prefix & @[stmt], new_argument(temp))

proc flatten_arguments(args: seq[Argument]): (seq[Statement], seq[Argument]) =
  var prefix: seq[Statement]
  var new_args: seq[Argument]
  for arg in args:
    let (arg_prefix, new_arg) = flatten_argument(arg)
    prefix.add(arg_prefix)
    new_args.add(new_arg)
  return (prefix, new_args)

proc flatten_keyword_arguments(kwargs: seq[
    KeywordArgument]): (seq[Statement], seq[KeywordArgument]) =
  var prefix: seq[Statement]
  var new_kwargs: seq[KeywordArgument]
  for kwarg in kwargs:
    let (arg_prefix, new_arg) = flatten_argument(kwarg.value)
    prefix.add(arg_prefix)
    new_kwargs.add(new_keyword_argument(kwarg.name, new_arg))
  return (prefix, new_kwargs)

# --- Flatten an expression (recurse into match bodies) ---

proc flatten_expression(expression: Expression): (seq[Statement], Expression) =
  case expression.kind:
  of EK_FNCALL:
    let (prefix, new_args) = flatten_arguments(expression.fncall.args)
    if prefix.len == 0: return (@[], expression)
    let new_fncall = new_function_call(expression.fncall.fnref, new_args).get
    return (prefix, new_expression(new_fncall))
  of EK_INIT:
    case expression.init.kind:
    of IK_STRUCT:
      let (prefix, new_kwargs) = flatten_keyword_arguments(
          expression.init.struct.args)
      if prefix.len == 0: return (@[], expression)
      let new_si = new_struct_init(expression.init.struct.struct_ref,
          new_kwargs).get
      return (prefix, new_expression(new_initializer(new_si)))
    of IK_LITERAL:
      return (@[], expression)
  of EK_MATCH:
    let new_match = flatten_match(expression.match)
    return (@[], new_expression(new_match))
  of EK_STRUCT_GET, EK_VARIABLE:
    return (@[], expression)

# --- Flatten match (recurse into case/else bodies) ---

proc flatten_match(match: Match): Match =
  var new_cases: seq[Case]
  for case_block in match.case_blocks:
    let new_stmts = flatten_statements(case_block.statements)
    new_cases.add(new_case(case_block.def, new_stmts).get)

  case match.kind:
  of MK_CASE_ONLY:
    new_match(match.def, new_cases).get
  of MK_COMPLETE:
    let new_else_stmts = flatten_statements(match.else_block.statements)
    let new_else = new_else(new_else_stmts, match.else_block.location).get
    new_match(match.def, new_cases, new_else).get

# --- Flatten a statement list ---

proc flatten_statements*(steps: seq[Statement]): seq[Statement] =
  var flattened: seq[Statement]
  for step in steps:
    let (prefix, new_expr) = flatten_expression(step.expression)
    flattened.add(prefix)
    case step.kind:
    of SK_ASSIGNED:
      flattened.add(new_statement(step.arg, new_expr))
    of SK_AUTO:
      flattened.add(new_statement(new_expr))
  return flattened
