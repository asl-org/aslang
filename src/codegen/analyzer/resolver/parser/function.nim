import results, strformat

import core, identifier, module_ref, defs, expression

# =============================================================================
# UserFunction
# =============================================================================

type UserFunction* = ref object of RootObj
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

type ExternFunction* = ref object of RootObj
  def: FunctionDefinition
  extern: string

proc new_extern_function*(extern: string, returns: string, name: string,
    args: seq[string]): Result[ExternFunction, core.Error] =
  var arg_defs: seq[ArgumentDefinition]
  for index, module in args.pairs:
    let module_id = new_identifier(module)
    let module_ref = new_module_ref(module_id)

    let arg_id = new_identifier(fmt"__asl__arg__{index}__")
    let arg_def = new_argument_definition(module_ref, arg_id)
    arg_defs.add(arg_def)

  var def = ? new_function_definition(
    new_identifier(name),                            # name
    arg_defs,
    new_module_ref(new_identifier(returns)),         # return type
    Location()
  )

  ok(ExternFunction(def: def, extern: extern))

proc new_extern_function*(def: FunctionDefinition,
    extern: string): ExternFunction =
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

proc new_function*(user_func: UserFunction): Function =
  Function(kind: FK_USER, user_func: user_func)

proc new_function*(extern_func: ExternFunction): Function =
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
  do_assert function.kind == FK_EXTERN, "expected extern function"
  function.extern_func

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
  discard ? parser.expect(strict_empty_line_spec)

  let steps = ? parser.one_or_more_spec(statement_spec, indent + 1,
      optional_empty_line_spec)
  new_user_function(def, steps)

proc extern_header_spec(parser: Parser, indent: int): Result[Identifier,
    core.Error] =
  discard ? parser.expect(indent_spec, indent)
  discard ? parser.expect(extern_keyword_spec)
  discard ? parser.expect(strict_space_spec)
  let extern = ? parser.expect(identifier_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(colon_spec)
  ok(extern)

proc extern_function_spec(parser: Parser, indent: int): Result[ExternFunction,
    core.Error] =
  let extern = ? parser.expect(extern_header_spec, indent)
  discard ? parser.expect(strict_empty_line_spec)
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
