import results, strformat, strutils

import core, identifier, module_ref, literal

# =============================================================================
# StructRef (no Argument dependency — separate type block)
# =============================================================================

type
  StructRefKind* = enum
    SRK_DEFAULT, SRK_NAMED
  StructRef* = ref object of RootObj
    module: ModuleRef
    case kind: StructRefKind
    of SRK_DEFAULT: discard
    of SRK_NAMED: struct: Identifier

proc new_struct_ref*(module: ModuleRef): StructRef =
  StructRef(kind: SRK_DEFAULT, module: module)

proc new_struct_ref*(module: ModuleRef, struct: Identifier): StructRef =
  StructRef(kind: SRK_NAMED, module: module, struct: struct)

proc location*(struct_ref: StructRef): Location =
  struct_ref.module.location

proc kind*(struct_ref: StructRef): StructRefKind = struct_ref.kind
proc module*(struct_ref: StructRef): ModuleRef = struct_ref.module

proc struct*(struct_ref: StructRef): Identifier =
  do_assert struct_ref.kind == SRK_NAMED, fmt"{struct_ref.location} expected named struct"
  struct_ref.struct

proc asl*(struct_ref: StructRef): string =
  case struct_ref.kind:
  of SRK_DEFAULT: struct_ref.module.asl
  of SRK_NAMED: fmt"{struct_ref.module.asl}.{struct_ref.struct.asl}"

# =============================================================================
# FunctionRef (no Argument dependency — separate type block)
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

proc module*(fnref: FunctionRef): ModuleRef =
  do_assert fnref.kind == FRK_MODULE, fmt"{fnref.location} expected a module function call"
  fnref.module

proc asl*(fnref: FunctionRef): string =
  case fnref.kind:
  of FRK_LOCAL: fnref.name.asl
  of FRK_MODULE: fmt"{fnref.module.asl}.{fnref.name.asl}"

# =============================================================================
# Mutually recursive types: Argument, FunctionCall, KeywordArgument, StructInit
# =============================================================================

type
  ArgumentKind* = enum
    AK_LITERAL, AK_VARIABLE, AK_FNCALL, AK_STRUCT_INIT
  Argument* = ref object of RootObj
    case kind: ArgumentKind
    of AK_LITERAL: literal: Literal
    of AK_VARIABLE: variable: Identifier
    of AK_FNCALL: fncall: FunctionCall
    of AK_STRUCT_INIT: struct_init: StructInit
  FunctionCall* = ref object of RootObj
    fnref: FunctionRef
    args: seq[Argument]
  KeywordArgument* = ref object of RootObj
    name: Identifier
    value: Argument
  StructInit* = ref object of RootObj
    struct_ref: StructRef
    args: seq[KeywordArgument]

# --- Argument ---

proc new_argument*(literal: Literal): Argument =
  Argument(kind: AK_LITERAL, literal: literal)

proc new_argument*(variable: Identifier): Argument =
  Argument(kind: AK_VARIABLE, variable: variable)

proc new_argument*(fncall: FunctionCall): Argument =
  Argument(kind: AK_FNCALL, fncall: fncall)

proc new_argument*(struct_init: StructInit): Argument =
  Argument(kind: AK_STRUCT_INIT, struct_init: struct_init)

proc location*(arg: Argument): Location =
  case arg.kind:
  of AK_LITERAL: arg.literal.location
  of AK_VARIABLE: arg.variable.location
  of AK_FNCALL: arg.fncall.fnref.location
  of AK_STRUCT_INIT: arg.struct_init.struct_ref.location

proc kind*(arg: Argument): ArgumentKind = arg.kind

proc variable*(arg: Argument): Identifier =
  do_assert arg.kind == AK_VARIABLE, fmt"{arg.location} [PE118] expected argument to be a variable"
  arg.variable

proc literal*(arg: Argument): Literal =
  do_assert arg.kind == AK_LITERAL, fmt"{arg.location} [PE119] expected argument to be a literal"
  arg.literal

proc fncall*(arg: Argument): FunctionCall =
  do_assert arg.kind == AK_FNCALL, fmt"{arg.location} expected argument to be a function call"
  arg.fncall

proc struct_init*(arg: Argument): StructInit =
  do_assert arg.kind == AK_STRUCT_INIT, fmt"{arg.location} expected argument to be a struct init"
  arg.struct_init

proc asl*(arg: Argument): string

# --- FunctionCall ---

proc new_function_call*(fnref: FunctionRef, args: seq[Argument]): Result[
    FunctionCall, core.Error] =
  if args.len == 0:
    return err(err_parser_empty_arg_list(fnref.location))
  if args.len > MAX_ARGS_LENGTH:
    return err(err_parser_arg_list_too_long(fnref.location, args.len))
  ok(FunctionCall(fnref: fnref, args: args))

proc location*(fncall: FunctionCall): Location = fncall.fnref.location
proc fnref*(fncall: FunctionCall): FunctionRef = fncall.fnref
proc args*(fncall: FunctionCall): seq[Argument] = fncall.args
proc name*(fncall: FunctionCall): Identifier = fncall.fnref.name

proc asl*(fncall: FunctionCall): string =
  var args: seq[string]
  for arg in fncall.args:
    args.add(arg.asl)
  let args_str = args.join(", ")
  fmt"{fncall.fnref.asl}({args_str})"

# --- KeywordArgument ---

proc new_keyword_argument*(name: Identifier, value: Argument): KeywordArgument =
  KeywordArgument(name: name, value: value)

proc location*(kwarg: KeywordArgument): Location = kwarg.name.location
proc name*(kwarg: KeywordArgument): Identifier = kwarg.name
proc value*(kwarg: KeywordArgument): Argument = kwarg.value

proc asl*(kwarg: KeywordArgument): string =
  fmt"{kwarg.name.asl}: {kwarg.value.asl}"

# --- StructInit ---

proc new_struct_init*(struct_ref: StructRef, args: seq[
    KeywordArgument]): Result[StructInit, core.Error] =
  if args.len == 0:
    return err(err_parser_empty_arg_list(struct_ref.location))
  if args.len > MAX_ARGS_LENGTH:
    return err(err_parser_arg_list_too_long(struct_ref.location, args.len))
  var maybe_args_repo = new_repo(args, @[new_index[KeywordArgument]("name",
      name, true)])
  if maybe_args_repo.is_err:
    let error = maybe_args_repo.error
    let arg = error.current
    return err(err_parser_arg_already_defined(arg.location, arg.name.asl,
        error.previous.location))
  ok(StructInit(struct_ref: struct_ref, args: args))

proc struct_ref*(init: StructInit): StructRef = init.struct_ref
proc args*(init: StructInit): seq[KeywordArgument] = init.args
proc location*(init: StructInit): Location = init.struct_ref.location

proc asl*(init: StructInit): string =
  var args: seq[string]
  for arg in init.args:
    args.add(arg.asl)
  [init.struct_ref.asl, "{", args.join(", "), "}"].join(" ")

# --- Argument asl (deferred due to mutual recursion) ---

proc asl*(arg: Argument): string =
  case arg.kind:
  of AK_LITERAL: arg.literal.asl
  of AK_VARIABLE: arg.variable.asl
  of AK_FNCALL: arg.fncall.asl
  of AK_STRUCT_INIT: arg.struct_init.asl

# =============================================================================
# Parser specs (with forward declarations for mutual recursion)
# =============================================================================

proc function_call_spec*(parser: Parser): Result[FunctionCall, core.Error]
proc struct_init_argument_spec(parser: Parser): Result[Argument, core.Error]

proc argument_spec*(parser: Parser): Result[Argument, core.Error] =
  var errors: seq[core.Error]

  let maybe_fncall = parser.expect(function_call_spec)
  if maybe_fncall.is_ok: return ok(new_argument(maybe_fncall.get))
  else: errors.add(maybe_fncall.error)

  let maybe_struct_init = parser.expect(struct_init_argument_spec)
  if maybe_struct_init.is_ok: return maybe_struct_init
  else: errors.add(maybe_struct_init.error)

  let maybe_identifier = parser.expect(identifier_spec)
  if maybe_identifier.is_ok: return ok(new_argument(maybe_identifier.get))
  else: errors.add(maybe_identifier.error)

  let maybe_literal = parser.expect(literal_spec)
  if maybe_literal.is_ok: return ok(new_argument(maybe_literal.get))
  else: errors.add(maybe_literal.error)

  err(errors.max())

proc argument_list_spec*(parser: Parser): Result[seq[Argument], core.Error] =
  parser.container_spec(open_paren_bracket_spec, argument_spec,
      close_paren_bracket_spec)

# --- FunctionRef specs ---

proc function_ref_local_spec(parser: Parser): Result[FunctionRef,
    core.Error] =
  let name = ? parser.expect(identifier_spec)
  ok(new_function_ref(name))

proc function_ref_module_spec(parser: Parser): Result[FunctionRef,
    core.Error] =
  let module_ref = ? parser.expect(module_ref_spec)
  discard ? parser.expect(dot_spec)
  let name = ? parser.expect(identifier_spec)
  ok(new_function_ref(name, module_ref))

proc function_ref_spec*(parser: Parser): Result[FunctionRef, core.Error] =
  parser.expect_one_of([function_ref_module_spec, function_ref_local_spec])

# --- FunctionCall spec ---

proc function_call_spec*(parser: Parser): Result[FunctionCall, core.Error] =
  let fnref = ? parser.expect(function_ref_spec)
  let args = ? parser.expect(argument_list_spec)
  new_function_call(fnref, args)

# --- StructRef spec ---

proc struct_ref_spec*(parser: Parser): Result[StructRef, core.Error] =
  let module = ? parser.expect(module_ref_spec)
  let maybe_dot = parser.expect(dot_spec)
  if maybe_dot.is_ok:
    let struct = ? parser.expect(identifier_spec)
    ok(new_struct_ref(module, struct))
  else:
    ok(new_struct_ref(module))

# --- KeywordArgument specs ---

proc keyword_argument_spec*(parser: Parser): Result[KeywordArgument,
    core.Error] =
  let name = ? parser.expect(identifier_spec)
  discard ? parser.expect_any(space_spec)
  discard ? parser.expect(colon_spec)
  discard ? parser.expect_any(space_spec)
  let value = ? parser.expect(argument_spec)
  ok(new_keyword_argument(name, value))

proc keyword_argument_list_spec*(parser: Parser): Result[seq[KeywordArgument],
    core.Error] =
  parser.container_spec(open_curly_bracket_spec, keyword_argument_spec,
      close_curly_bracket_spec)

# --- StructInit specs ---

proc struct_init_spec*(parser: Parser): Result[StructInit, core.Error] =
  let struct_ref = ? parser.expect(struct_ref_spec)
  discard ? parser.expect_any(space_spec)
  let kwargs = ? parser.expect(keyword_argument_list_spec)
  new_struct_init(struct_ref, kwargs)

proc struct_init_argument_spec(parser: Parser): Result[Argument, core.Error] =
  let si = ? parser.expect(struct_init_spec)
  ok(new_argument(si))
