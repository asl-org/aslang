import results, strformat, strutils, tables, hashes

import core, identifier, module_ref

# =============================================================================
# StructDefinition
# =============================================================================

type
  StructDefinitionKind* = enum
    SDK_DEFAULT, SDK_NAMED
  StructDefinition* = ref object of RootObj
    location: Location
    case kind: StructDefinitionKind
    of SDK_DEFAULT: discard
    of SDK_NAMED: name: Identifier

proc new_struct_definition*(location: Location): StructDefinition =
  StructDefinition(kind: SDK_DEFAULT, location: location)

proc new_struct_definition*(name: Identifier,
    location: Location): StructDefinition =
  StructDefinition(kind: SDK_NAMED, name: name, location: location)

proc kind*(def: StructDefinition): StructDefinitionKind = def.kind

proc location*(def: StructDefinition): Location = def.location

proc name*(def: StructDefinition): Identifier =
  do_assert def.kind == SDK_NAMED, "expected extern function"
  def.name

proc asl*(def: StructDefinition): string =
  case def.kind:
  of SDK_DEFAULT: "struct:"
  of SDK_NAMED: fmt"struct {def.name.asl}:"

proc struct_default_definition_spec*(parser: Parser): Result[
    StructDefinition, core.Error] =
  let struct_keyword = ? parser.expect(struct_keyword_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(colon_spec)
  ok(new_struct_definition(struct_keyword.location))

proc struct_named_definition_spec*(parser: Parser): Result[
    StructDefinition, core.Error] =
  let struct_keyword = ? parser.expect(struct_keyword_spec)
  discard ? parser.expect(strict_space_spec)
  let name = ? parser.expect(identifier_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(colon_spec)
  ok(new_struct_definition(name, struct_keyword.location))

# =============================================================================
# ArgumentDefinition
# =============================================================================

type ArgumentDefinition* = ref object of RootObj
  name: Identifier
  module_ref: ModuleRef

proc new_argument_definition*(module_ref: ModuleRef,
    name: Identifier): ArgumentDefinition =
  ArgumentDefinition(name: name, module_ref: module_ref)

proc new_argument_definition*(module_ref: string, name: string): Result[
    ArgumentDefinition, core.Error] =
  let module_ref_id = new_module_ref(module_ref)
  let name_id = new_identifier(name)
  ok(new_argument_definition(module_ref_id, name_id))

proc module_ref*(def: ArgumentDefinition): ModuleRef =
  def.module_ref

proc location*(def: ArgumentDefinition): Location =
  def.module_ref.location

proc asl*(def: ArgumentDefinition): string =
  let name_str = def.name.asl
  let ref_str = def.module_ref.asl
  fmt"{ref_str} {name_str}"

proc name*(def: ArgumentDefinition): Identifier = def.name
proc hash*(def: ArgumentDefinition): Hash = hash(def.module_ref)

proc argument_definition_spec*(parser: Parser): Result[
    ArgumentDefinition, core.Error] =
  let module_ref = ? parser.expect(module_ref_spec)
  discard ? parser.expect(strict_space_spec)
  let name = ? parser.expect(identifier_spec)
  ok(new_argument_definition(module_ref, name))

# TODO: Fix this later.
proc struct_field_definition_spec*(parser: Parser, indent: int): Result[
    ArgumentDefinition, core.Error] =
  discard ? parser.expect(indent_spec, indent)
  let field = ? parser.expect(argument_definition_spec)
  ok(field)

# =============================================================================
# FunctionDefinition
# =============================================================================

type FunctionDefinition* = ref object of RootObj
  name: Identifier
  returns: ModuleRef
  args: seq[ArgumentDefinition]
  location: Location

proc new_function_definition*(fn_name: Identifier, args: seq[
    ArgumentDefinition], returns: ModuleRef, location: Location): Result[
        FunctionDefinition, core.Error] =
  if args.len == 0:
    return err(err_parser_empty_arg_list(location))
  if args.len > MAX_ARGS_LENGTH:
    return err(err_parser_arg_list_too_long(location, args.len))

  let maybe_args_repo = new_repo(args, @[new_index[ArgumentDefinition]("name",
      name, true)])
  if maybe_args_repo.is_err:
    let error = maybe_args_repo.error
    let arg = error.current
    let predefined_arg_location = error.previous.location
    return err(err_parser_arg_already_defined(arg.location, arg.name.asl,
          predefined_arg_location))

  ok(FunctionDefinition(name: fn_name, args: args, returns: returns,
      location: location))

proc location*(def: FunctionDefinition): Location = def.location
proc name*(def: FunctionDefinition): Identifier = def.name
proc args*(def: FunctionDefinition): seq[ArgumentDefinition] = def.args
proc returns*(def: FunctionDefinition): ModuleRef = def.returns

proc asl*(def: FunctionDefinition): string =
  var args: seq[string]
  for arg in def.args:
    args.add(arg.asl)
  let args_str = args.join(", ")
  fmt"fn {def.name.asl}({args_str}): {def.returns.asl}"

proc hash*(def: FunctionDefinition): Hash =
  var acc = hash(def.name)
  for arg in def.args:
    acc = acc !& hash(arg)
  return acc

proc argument_definition_list_spec*(parser: Parser): Result[seq[
    ArgumentDefinition], core.Error] =
  parser.list_spec(open_paren_bracket_spec,
      argument_definition_spec, close_paren_bracket_spec)

proc function_definition_spec*(parser: Parser, indent: int): Result[
    FunctionDefinition, core.Error] =
  discard ? parser.expect(indent_spec, indent)
  let fn_keyword = ? parser.expect(fn_keyword_spec)

  discard ? parser.expect(strict_space_spec)
  let name = ? parser.expect(identifier_spec)

  discard ? parser.expect(optional_space_spec)
  let args = ? parser.expect(argument_definition_list_spec)

  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(colon_spec)

  discard ? parser.expect(optional_space_spec)
  let returns = ? parser.expect(module_ref_spec)

  new_function_definition(name, args, returns, fn_keyword.location)
