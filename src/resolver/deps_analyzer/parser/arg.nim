import results, strformat, strutils

import core, identifier, module_ref, literal
export core, identifier, module_ref, literal

# =============================================================================
# Argument
# =============================================================================

type
  ArgumentKind* = enum
    AK_LITERAL, AK_VARIABLE
  Argument* = ref object of RootObj
    case kind: ArgumentKind
    of AK_LITERAL: literal: Literal
    of AK_VARIABLE: variable: Identifier

proc new_argument*(literal: Literal): Argument =
  Argument(kind: AK_LITERAL, literal: literal)

proc new_argument*(variable: Identifier): Argument =
  Argument(kind: AK_VARIABLE, variable: variable)

proc location*(arg: Argument): Location =
  case arg.kind:
  of AK_LITERAL: arg.literal.location
  of AK_VARIABLE: arg.variable.location

proc kind*(arg: Argument): ArgumentKind = arg.kind

proc variable*(arg: Argument): Result[Identifier, string] =
  case arg.kind:
  of AK_LITERAL: err(fmt"{arg.location} [PE118] expected argument to be a variable but found literal `{arg.literal.asl}`")
  of AK_VARIABLE: ok(arg.variable)

proc literal*(arg: Argument): Result[Literal, string] =
  case arg.kind:
  of AK_LITERAL: ok(arg.literal)
  of AK_VARIABLE: err(fmt"{arg.location} [PE119] expected argument to be a literal but found variable `{arg.variable.asl}`")

proc asl*(arg: Argument): string =
  case arg.kind:
  of AK_LITERAL: arg.literal.asl
  of AK_VARIABLE: arg.variable.asl

proc argument_spec*(parser: Parser): Result[Argument, ParserError] =
  var errors: seq[ParserError]

  let maybe_identifier = parser.expect(identifier_spec)
  if maybe_identifier.is_ok: return ok(new_argument(maybe_identifier.get))
  else: errors.add(maybe_identifier.error)

  let maybe_literal = parser.expect(literal_spec)
  if maybe_literal.is_ok: return ok(new_argument(maybe_literal.get))
  else: errors.add(maybe_literal.error)

  err(errors.max())

proc argument_list_spec*(parser: Parser): Result[seq[Argument], ParserError] =
  discard ? parser.expect(open_paren_bracket_spec)

  var args: seq[Argument]
  discard ? parser.expect(optional_space_spec)
  # NOTE: every function call must have at least one argument
  args.add( ? parser.expect(argument_spec))
  discard ? parser.expect(optional_space_spec)

  while parser.expect(comma_spec).is_ok:
    discard ? parser.expect(optional_space_spec)
    args.add( ? parser.expect(argument_spec))
    discard ? parser.expect(optional_space_spec)

  discard ? parser.expect(close_paren_bracket_spec)
  ok(args)

# =============================================================================
# FunctionRef
# =============================================================================

type
  FunctionRefKind* = enum
    FRK_LOCAL, FRK_MODULE
  FunctionRef* = ref object of RootObj
    name: Identifier
    case kind: FunctionRefKind
    of FRK_LOCAL: discard
    of FRK_MODULE: module: ModuleRef

proc new_function_ref*(name: Identifier): FunctionRef =
  FunctionRef(kind: FRK_LOCAL, name: name)

proc new_function_ref*(name: Identifier, module: ModuleRef): FunctionRef =
  FunctionRef(kind: FRK_MODULE, name: name, module: module)

proc location*(fnref: FunctionRef): Location =
  case fnref.kind:
  of FRK_LOCAL: fnref.name.location
  of FRK_MODULE: fnref.module.location

proc kind*(fnref: FunctionRef): FunctionRefKind = fnref.kind
proc name*(fnref: FunctionRef): Identifier = fnref.name

proc module*(fnref: FunctionRef): Result[ModuleRef, string] =
  case fnref.kind:
  of FRK_LOCAL: err(fmt"{fnref.location} expected a module function call but found local function call")
  of FRK_MODULE: ok(fnref.module)

proc asl*(fnref: FunctionRef): string =
  case fnref.kind:
  of FRK_LOCAL: fnref.name.asl
  of FRK_MODULE: fmt"{fnref.module.asl}.{fnref.name.asl}"

proc function_ref_local_spec*(parser: Parser): Result[FunctionRef, ParserError] =
  let name = ? parser.expect(identifier_spec)
  ok(new_function_ref(name))

proc function_ref_module_spec*(parser: Parser): Result[FunctionRef, ParserError] =
  let module_ref = ? parser.expect(module_ref_spec)
  discard ? parser.expect(dot_spec)
  let name = ? parser.expect(identifier_spec)
  ok(new_function_ref(name, module_ref))

proc function_ref_spec*(parser: Parser): Result[FunctionRef, ParserError] =
  var errors: seq[ParserError]

  let maybe_module_fnref = parser.expect(function_ref_module_spec)
  if maybe_module_fnref.is_ok: return maybe_module_fnref
  else: errors.add(maybe_module_fnref.error)

  let maybe_local_fnref = parser.expect(function_ref_local_spec)
  if maybe_local_fnref.is_ok: return maybe_local_fnref
  else: errors.add(maybe_local_fnref.error)

  err(errors.max())

# =============================================================================
# FunctionCall
# =============================================================================

type FunctionCall* = ref object of RootObj
  fnref: FunctionRef
  args: seq[Argument]

proc new_function_call*(fnref: FunctionRef, args: seq[Argument]): Result[
    FunctionCall, ParserError] =
  if args.len == 0:
    return err(err_parser_empty_arg_list(fnref.location))
  if args.len > MAX_ARGS_LENGTH:
    return err(err_parser_arg_list_too_long(fnref.location, args.len))
  ok(FunctionCall(fnref: fnref, args: args))

proc location*(fncall: FunctionCall): Location =
  fncall.fnref.location

proc fnref*(fncall: FunctionCall): FunctionRef = fncall.fnref
proc args*(fncall: FunctionCall): seq[Argument] = fncall.args
proc name*(fncall: FunctionCall): Identifier = fncall.fnref.name

proc asl*(fncall: FunctionCall): string =
  var args: seq[string]
  for arg in fncall.args:
    args.add(arg.asl)
  let args_str = args.join(", ")
  fmt"{fncall.fnref.asl}({args_str})"

proc function_call_spec*(parser: Parser): Result[FunctionCall, ParserError] =
  let fnref = ? parser.expect(function_ref_spec)
  let args = ? parser.expect(argument_list_spec)
  new_function_call(fnref, args)
