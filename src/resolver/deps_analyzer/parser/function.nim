import results, strformat

import core, identifier, module_ref, defs, expression
export core, identifier, module_ref, defs, expression

# =============================================================================
# UserFunction
# =============================================================================

type UserFunction* = ref object of RootObj
  def: FunctionDefinition
  steps: seq[Statement]

# =============================================================================
# ExternFunction
# =============================================================================

type ExternFunction* = ref object of RootObj
  def: FunctionDefinition
  extern: string

proc new_extern_function*(extern: string, returns: string, name: string,
    args: seq[string]): Result[ExternFunction, string] =
  var arg_defs: seq[ArgumentDefinition]
  for index, module in args.pairs:
    let module_id = ? new_identifier(module)
    let module_ref = new_module_ref(module_id)

    let arg_id = ? new_identifier(fmt"__asl__arg__{index}__")
    let arg_def = new_argument_definition(module_ref, arg_id)
    arg_defs.add(arg_def)

  var def = ? new_function_definition(
    ? new_identifier(name),                             # name
    arg_defs,
    new_module_ref( ? new_identifier(returns)),         # return type
    Location()
  )

  ok(ExternFunction(def: def, extern: extern))

proc new_extern_function*(def: FunctionDefinition, extern: string): ExternFunction =
  ExternFunction(def: def, extern: extern)

proc name*(function: ExternFunction): Identifier = function.def.name
proc def*(function: ExternFunction): FunctionDefinition = function.def
proc extern*(function: ExternFunction): string = function.extern

# =============================================================================
# Function (Unified)
# =============================================================================

type FunctionKind* = enum
  FK_USER, FK_EXTERN

type Function* = ref object of RootObj
  case kind*: FunctionKind
  of FK_USER:
    user_func: UserFunction
  of FK_EXTERN:
    extern_func: ExternFunction

proc make_user_function*(def: FunctionDefinition, steps: seq[
    Statement]): Function =
  Function(kind: FK_USER, user_func: UserFunction(def: def, steps: steps))

proc function*(extern_func: ExternFunction): Function =
  Function(kind: FK_EXTERN, extern_func: extern_func)

proc def*(function: Function): FunctionDefinition =
  case function.kind:
  of FK_USER: function.user_func.def
  of FK_EXTERN: function.extern_func.def

proc steps*(function: Function): seq[Statement] =
  case function.kind:
  of FK_USER: function.user_func.steps
  of FK_EXTERN: @[]

proc location*(function: Function): Location = function.def.location
proc name*(function: Function): Identifier = function.def.name

proc extern_func*(function: Function): ExternFunction =
  doAssert function.kind == FK_EXTERN, "expected extern function"
  function.extern_func

proc new_function*(def: FunctionDefinition, steps: seq[Statement]): Result[
    Function, string] =
  if steps.len == 0:
    return err(fmt"{def.location} [PE134] function `{def.name.asl}` must have at least one statement")
  ok(make_user_function(def, steps))

proc asl*(function: Function, indent: string): seq[string] =
  let header = function.def.asl

  var lines: seq[string]
  for step in steps(function):
    for line in step.asl(indent):
      lines.add(indent & line)

  return (@[header] & lines)

proc function_spec*(parser: Parser, indent: int): Result[Function, string] =
  let def = ? parser.expect(function_definition_spec, indent)
  discard ? parser.expect(strict_empty_line_spec)

  var steps: seq[Statement]
  # NOTE: Function must have at least 1 expression.
  steps.add( ? parser.expect(statement_spec, indent + 1))
  discard ? parser.expect(optional_empty_line_spec)

  var maybe_expression = parser.expect(statement_spec, indent + 1)
  while maybe_expression.is_ok:
    steps.add(maybe_expression.get)
    discard ? parser.expect(optional_empty_line_spec)
    maybe_expression = parser.expect(statement_spec, indent + 1)

  new_function(def, steps)
