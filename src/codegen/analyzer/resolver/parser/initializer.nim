import results, strformat, strutils, tables

import core, identifier, module_ref, literal, arg

# =============================================================================
# LiteralInit
# =============================================================================

type LiteralInit* = ref object of RootObj
  module: ModuleRef
  literal: Literal

proc new_literal_init*(module: ModuleRef, literal: Literal): LiteralInit =
  LiteralInit(module: module, literal: literal)

proc location*(init: LiteralInit): Location =
  init.module.location

proc module*(init: LiteralInit): ModuleRef = init.module
proc literal*(init: LiteralInit): Literal = init.literal

proc asl*(init: LiteralInit): string =
  fmt"{init.module.asl} {init.literal.asl}"

proc literal_init_spec*(parser: Parser): Result[LiteralInit, core.Error] =
  let module_ref = ? parser.expect(module_ref_spec)
  discard ? parser.expect(strict_space_spec)
  let literal = ? parser.expect(literal_spec)
  ok(new_literal_init(module_ref, literal))

# =============================================================================
# StructRef
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

proc struct*(struct_ref: StructRef): Result[Identifier, string] =
  case struct_ref.kind:
  of SRK_DEFAULT: err(fmt"{struct_ref.location} expected named struct but found default")
  of SRK_NAMED: ok(struct_ref.struct)

proc asl*(struct_ref: StructRef): string =
  case struct_ref.kind:
  of SRK_DEFAULT: struct_ref.module.asl
  of SRK_NAMED: fmt"{struct_ref.module.asl}.{struct_ref.struct.asl}"

proc struct_ref_spec*(parser: Parser): Result[StructRef, core.Error] =
  let module = ? parser.expect(module_ref_spec)

  let maybe_dot = parser.expect(dot_spec)
  if maybe_dot.is_ok:
    let struct = ? parser.expect(identifier_spec)
    ok(new_struct_ref(module, struct))
  else:
    ok(new_struct_ref(module))

# =============================================================================
# KeywordArgument
# =============================================================================

type KeywordArgument* = ref object of RootObj
  name: Identifier
  value: Argument

proc new_keyword_argument*(name: Identifier, value: Argument): KeywordArgument =
  KeywordArgument(name: name, value: value)

proc location*(kwarg: KeywordArgument): Location =
  kwarg.name.location

proc name*(kwarg: KeywordArgument): Identifier = kwarg.name
proc value*(kwarg: KeywordArgument): Argument = kwarg.value

proc asl*(kwarg: KeywordArgument): string =
  fmt"{kwarg.name.asl}: {kwarg.value.asl}"

proc keyword_argument_spec*(parser: Parser): Result[KeywordArgument,
    core.Error] =
  let name = ? parser.expect(identifier_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(colon_spec)
  discard ? parser.expect(optional_space_spec)
  let value = ? parser.expect(argument_spec)
  ok(new_keyword_argument(name, value))

proc keyword_argument_list_spec*(parser: Parser): Result[seq[KeywordArgument],
    core.Error] =
  parser.list_spec(open_curly_bracket_spec, keyword_argument_spec,
      close_curly_bracket_spec)

# =============================================================================
# StructInit
# =============================================================================

type StructInit* = ref object of RootObj
  struct_ref: StructRef
  args: seq[KeywordArgument]

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
    let predefined_arg_location = error.previous.location
    return err(err_parser_arg_already_defined(arg.location, arg.name.asl,
        predefined_arg_location))

  ok(StructInit(struct_ref: struct_ref, args: args))

proc struct_ref*(init: StructInit): StructRef = init.struct_ref
proc args*(init: StructInit): seq[KeywordArgument] = init.args

proc location*(init: StructInit): Location =
  init.struct_ref.location

proc asl*(init: StructInit): string =
  var args: seq[string]
  for arg in init.args:
    args.add(arg.asl)
  [init.struct_ref.asl, "{", args.join(", "), "}"].join(" ")

proc struct_init_spec*(parser: Parser): Result[StructInit, core.Error] =
  let struct_ref = ? parser.expect(struct_ref_spec)
  discard ? parser.expect(optional_space_spec)
  let kwargs = ? parser.expect(keyword_argument_list_spec)
  new_struct_init(struct_ref, kwargs)

# =============================================================================
# Initializer
# =============================================================================

type
  InitializerKind* = enum
    IK_LITERAL, IK_STRUCT
  Initializer* = ref object of RootObj
    case kind: InitializerKind
    of IK_LITERAL: literal: LiteralInit
    of IK_STRUCT: struct: StructInit

proc new_initializer*(literal: LiteralInit): Initializer =
  Initializer(kind: IK_LITERAL, literal: literal)

proc new_initializer*(struct: StructInit): Initializer =
  Initializer(kind: IK_STRUCT, struct: struct)

proc location*(init: Initializer): Location =
  case init.kind:
  of IK_LITERAL: init.literal.location
  of IK_STRUCT: init.struct.location

proc kind*(init: Initializer): InitializerKind = init.kind

proc literal*(init: Initializer): Result[LiteralInit, string] =
  case init.kind:
  of IK_LITERAL: ok(init.literal)
  of IK_STRUCT: err(fmt"{init.location} [PE170] expected literal but found struct initializer")

proc struct*(init: Initializer): Result[StructInit, string] =
  case init.kind:
  of IK_LITERAL: err(fmt"{init.location} [PE171] expected struct but found literal initializer")
  of IK_STRUCT: ok(init.struct)

proc asl*(init: Initializer): string =
  case init.kind:
  of IK_LITERAL: init.literal.asl
  of IK_STRUCT: init.struct.asl

proc initializer_spec*(parser: Parser): Result[Initializer, core.Error] =
  var errors: seq[core.Error]
  let maybe_literal_init = parser.expect(literal_init_spec)
  if maybe_literal_init.is_ok: return ok(new_initializer(
      maybe_literal_init.get))
  else: errors.add(maybe_literal_init.error)

  let maybe_struct_init = parser.expect(struct_init_spec)
  if maybe_struct_init.is_ok: return ok(new_initializer(maybe_struct_init.get))
  else: errors.add(maybe_struct_init.error)

  err(errors.max())

# =============================================================================
# StructGet
# =============================================================================

type StructGet* = ref object of RootObj
  name: Identifier
  field: Identifier

proc new_struct_get*(name: Identifier, field: Identifier): StructGet =
  StructGet(name: name, field: field)

proc location*(struct_get: StructGet): Location = struct_get.name.location
proc name*(struct_get: StructGet): Identifier = struct_get.name
proc field*(struct_get: StructGet): Identifier = struct_get.field

proc asl*(struct_get: StructGet): string =
  fmt"{struct_get.name.asl}.{struct_get.field.asl}"

proc struct_get_spec*(parser: Parser): Result[StructGet, core.Error] =
  let name = ? parser.expect(identifier_spec)
  discard ? parser.expect(dot_spec)
  let field = ? parser.expect(identifier_spec)
  ok(new_struct_get(name, field))
