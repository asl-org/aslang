import results, strformat, strutils, sequtils, re, tables, hashes

import parser/tokenizer
export tokenizer

# ast node constants
const MAX_IDENTIFIER_LENGTH = 256
const MAX_TYPE_CHILDREN_COUNT = 8
const MAX_ARGS_LENGTH = 32

# parser constants
const INDENT_SIZE = 2 # spaces

# NOTE: The parser assumes that the editor used to write code
# must automatically strip off the trailing spaces and also
# add the new line at the end of file if not present. This is
# a conscious choice to ensure the consistent syntax with
# minimal configuration.
type Parser = ref object of RootObj
  path: string
  tokens: seq[Token]
  index: int = 0
  indent: int
  checkpoints: seq[int]

type AtomSpec[T] = proc(parser: Parser): Result[T, string]
type BlockSpec[T] = proc(parser: Parser, indent: int): Result[T, string]

proc can_parse(parser: Parser): bool =
  parser.index < parser.tokens.len

proc peek(parser: Parser): Result[Token, string] =
  if parser.can_parse():
    ok(parser.tokens[parser.index])
  else:
    err(fmt"reached end of token stream")

proc expect[T](parser: Parser, spec: AtomSpec[T]): Result[T, string] =
  let start = parser.index
  let maybe_value = spec(parser)
  if maybe_value.is_err:
    parser.index = start
    return err(maybe_value.error)
  return maybe_value

proc expect[T](parser: Parser, spec: BlockSpec[T], indent: int): Result[
    T, string] =
  let start = parser.index
  let maybe_value = spec(parser, indent)
  if maybe_value.is_err:
    parser.index = start
    return err(maybe_value.error)
  return maybe_value

proc token_spec_util(parser: Parser, kind: TokenKind): Result[Token, string] =
  let token = ? parser.peek()
  if token.kind == kind:
    parser.index += 1
    ok(token)
  else:
    err(fmt"{token.location} expected token kind `{kind}` but found `{token.kind}`")

proc keyword_spec_util(parser: Parser, keyword: string): Result[Token, string] =
  let alphabet = ? parser.token_spec_util(TK_ALPHABETS)
  if alphabet.value == keyword:
    ok(alphabet)
  else:
    err(fmt"{alphabet.location} expected keyword `{keyword}` but found `{alphabet.value}`")

# keyword specs
proc module_keyword_spec(parser: Parser): Result[Token,
    string] = parser.keyword_spec_util("module")

proc fn_keyword_spec(parser: Parser): Result[Token,
    string] = parser.keyword_spec_util("fn")

proc match_keyword_spec(parser: Parser): Result[Token,
    string] = parser.keyword_spec_util("match")

proc case_keyword_spec(parser: Parser): Result[Token,
    string] = parser.keyword_spec_util("case")

proc else_keyword_spec(parser: Parser): Result[Token,
    string] = parser.keyword_spec_util("else")

proc struct_keyword_spec(parser: Parser): Result[Token,
    string] = parser.keyword_spec_util("struct")

proc generic_keyword_spec(parser: Parser): Result[Token,
    string] = parser.keyword_spec_util("generic")

proc comment_spec(parser: Parser): Result[Token,
    string] = parser.token_spec_util(TK_COMMENT)

# special character spec
proc colon_spec(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_COLON)

proc comma_spec(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_COMMA)

proc dot_spec(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_DOT)

proc equal_spec(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_EQUAL)

proc open_paren_bracket_spec(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_OPEN_PAREN)

proc close_paren_bracket_spec(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_CLOSE_PAREN)

proc open_curly_bracket_spec(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_OPEN_CURLY)

proc close_curly_bracket_spec(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_CLOSE_CURLY)

proc open_square_bracket_spec(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_OPEN_SQUARE)

proc close_square_bracket_spec(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_CLOSE_SQUARE)

# spaces spec
proc new_line_spec(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_NEW_LINE)

proc space_spec(parser: Parser): Result[Token, string] =
  parser.token_spec_util(TK_SPACE)

# NOTE: It just consumes all the spaces and always succeeds
proc optional_space_spec(parser: Parser): Result[int, string] =
  var count = 0
  while parser.expect(space_spec).is_ok:
    count += 1
  ok(count)

proc strict_space_spec(parser: Parser): Result[int, string] =
  var count = 0
  # NOTE: Must have one strict space
  discard ? parser.expect(space_spec)
  count += 1
  while parser.expect(space_spec).is_ok:
    count += 1
  ok(count)

# NOTE: This spec is also used to consume trailing line content
proc empty_line_spec(parser: Parser): Result[void, string] =
  # NOTE: Existence of space does not matter at all.
  discard ? parser.expect(optional_space_spec)
  # NOTE: Existence of comment does not matter at all.
  discard parser.expect(comment_spec)
  # NOTE: Every line must end with a new line.
  discard ? parser.expect(new_line_spec)
  ok()

proc optional_empty_line_spec(parser: Parser): Result[int, string] =
  var count = 0
  while parser.expect(empty_line_spec).is_ok:
    count += 1
  ok(count)

proc strict_empty_line_spec(parser: Parser): Result[int, string] =
  var count = 0
  # NOTE: Must have one strict space
  ? parser.expect(empty_line_spec)
  count += 1
  while parser.expect(empty_line_spec).is_ok:
    count += 1
  ok(count)

# NOTE: Configure indent size here.
proc indent_spec(parser: Parser, indent: int): Result[int, string] =

  let spaces = ? parser.expect(optional_space_spec)
  if spaces == indent * parser.indent:
    return ok(spaces)

  # NOTE: this token is the start of line
  let token = ? parser.peek()
  err(fmt"{token.location} indentation error: expected `{indent * parser.indent}` space but found `{spaces}`")

type Identifier* = ref object of RootObj
  name: string
  location: Location

proc new_identifier(name: string, location: Location): Result[Identifier, string] =
  if name.len == 0:
    return err(fmt"{location} [PE101] [UNREACHABLE] empty string can not be an identifier.")

  if name.len > MAX_IDENTIFIER_LENGTH:
    return err(fmt"{location} [PE102] identifier length `{name.len}` exceeded maximum identifier length of `{MAX_IDENTIFIER_LENGTH}`")
  ok(Identifier(name: name, location: location))

proc new_identifier*(name: string): Result[Identifier, string] =
  new_identifier(name, Location())

proc new_identifier(location: Location): Identifier =
  let name = fmt"__asl_arg_{location.hash.to_hex}"
  Identifier(name: name, location: location)

proc location*(identifier: Identifier): Location =
  identifier.location

proc asl*(identifier: Identifier): string =
  identifier.name

proc hash*(identifier: Identifier): Hash =
  hash(identifier.name)

proc `==`*(a: Identifier, b: Identifier): bool =
  a.hash == b.hash

# identifier specs
proc identifier_head_spec(parser: Parser): Result[Token, string] =
  let maybe_underscore = parser.token_spec_util(TK_UNDERSCORE)
  if maybe_underscore.is_ok:
    maybe_underscore
  else:
    parser.token_spec_util(TK_ALPHABETS)

proc identifier_tail_spec(parser: Parser): Result[Token, string] =
  let maybe_id_head = parser.expect(identifier_head_spec)
  if maybe_id_head.is_ok:
    maybe_id_head
  else:
    parser.token_spec_util(TK_DIGITS)

proc identifier_spec(parser: Parser): Result[Identifier, string] =
  let id_head = ? parser.expect(identifier_head_spec)
  var name = id_head.value
  var location = id_head.location

  var maybe_id_tail = parser.expect(identifier_tail_spec)
  while maybe_id_tail.is_ok:
    name.add(maybe_id_tail.get.value)
    maybe_id_tail = parser.expect(identifier_tail_spec)

  new_identifier(name, location)

type UserModuleDefinition* = ref object of RootObj
  name: Identifier
  location: Location

proc new_module_definition*(name: Identifier,
    location: Location): UserModuleDefinition =
  UserModuleDefinition(name: name, location: location)

proc location*(def: UserModuleDefinition): Location =
  def.location

proc asl(def: UserModuleDefinition): string =
  fmt"module {def.name.asl}:"

proc hash(def: UserModuleDefinition): Hash =
  def.location.hash

# module spec
proc module_definition_spec(parser: Parser): Result[UserModuleDefinition, string] =
  let module_keyword = ? parser.expect(module_keyword_spec)
  discard ? parser.expect(strict_space_spec)
  let name = ? parser.expect(identifier_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(colon_spec)
  ok(new_module_definition(name, module_keyword.location))

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

proc name(def: StructDefinition): Result[Identifier, string] =
  case def.kind:
  of SDK_DEFAULT: err(fmt"{def.location} expected a named struct but found anonymous struct")
  of SDK_NAMED: ok(def.name)

proc asl(def: StructDefinition): string =
  case def.kind:
  of SDK_DEFAULT: "struct:"
  of SDK_NAMED: fmt"struct {def.name.asl}:"

proc struct_default_definition_spec(parser: Parser): Result[
    StructDefinition, string] =
  let struct_keyword = ? parser.expect(struct_keyword_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(colon_spec)
  ok(new_struct_definition(struct_keyword.location))

proc struct_named_definition_spec(parser: Parser): Result[
    StructDefinition, string] =
  let struct_keyword = ? parser.expect(struct_keyword_spec)
  discard ? parser.expect(strict_space_spec)
  let name = ? parser.expect(identifier_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(colon_spec)
  ok(new_struct_definition(name, struct_keyword.location))

proc struct_definition_spec(parser: Parser): Result[
    StructDefinition, string] =
  let maybe_struct_default_def = parser.expect(struct_default_definition_spec)
  if maybe_struct_default_def.is_ok:
    maybe_struct_default_def
  else:
    parser.expect(struct_named_definition_spec)

type
  ModuleRefKind* = enum
    MRK_SIMPLE, MRK_NESTED
  ModuleRef* = ref object of RootObj
    module: Identifier
    case kind: ModuleRefKind
    of MRK_SIMPLE: discard
    of MRK_NESTED: children: seq[ModuleRef]

proc new_module_ref*(module: Identifier): ModuleRef =
  ModuleRef(kind: MRK_SIMPLE, module: module)

proc new_module_ref*(module: Identifier, children: seq[
    ModuleRef]): Result[ModuleRef, string] =
  if children.len == 0:
    return err(fmt"{module.location} [PE103] nested module refs can not have empty child module ref list")
  if children.len > MAX_TYPE_CHILDREN_COUNT:
    return err(fmt"{module.location} [PE104] a nested module ref only supports upto `{MAX_TYPE_CHILDREN_COUNT}` children types but `{children.len}` were given")
  ok(ModuleRef(kind: MRK_NESTED, module: module, children: children))

proc new_module_ref(module: string): Result[ModuleRef, string] =
  let module_id = ? new_identifier(module)
  ok(new_module_ref(module_id))

proc location*(module_ref: ModuleRef): Location =
  module_ref.module.location

proc module*(module_ref: ModuleRef): Identifier =
  module_ref.module

proc kind*(module_ref: ModuleRef): ModuleRefKind =
  module_ref.kind

proc children*(module_ref: ModuleRef): seq[ModuleRef] =
  case module_ref.kind:
  of MRK_SIMPLE: @[]
  of MRK_NESTED: module_ref.children

proc asl*(module_ref: ModuleRef): string =
  case module_ref.kind:
  of MRK_SIMPLE: module_ref.module.asl
  of MRK_NESTED:
    var children: seq[string]
    for child in module_ref.children:
      children.add(child.asl)
    let module_str = module_ref.module.asl
    let children_str = children.join(", ")
    fmt"{module_str}[{children_str}]"

proc hash(module_ref: ModuleRef): Hash =
  var acc = hash(module_ref.module)
  case module_ref.kind:
  of MRK_SIMPLE: discard
  of MRK_NESTED:
    for child in module_ref.children:
      acc = acc !& hash(child)
  return acc

proc module_ref_spec(parser: Parser): Result[ModuleRef, string] =
  let module_ref = ? parser.expect(identifier_spec)

  var maybe_open_square_bracket = parser.expect(open_square_bracket_spec)
  if maybe_open_square_bracket.is_err:
    return ok(new_module_ref(module_ref))

  var children: seq[ModuleRef]
  discard ? parser.expect(optional_space_spec)
  children.add( ? parser.expect(module_ref_spec))
  discard ? parser.expect(optional_space_spec)

  while parser.expect(comma_spec).is_ok:
    discard ? parser.expect(optional_space_spec)
    children.add( ? parser.expect(module_ref_spec))
    discard ? parser.expect(optional_space_spec)

  discard ? parser.expect(close_square_bracket_spec)
  new_module_ref(module_ref, children)

type ArgumentDefinition* = ref object of RootObj
  name: Identifier
  module_ref: ModuleRef

proc new_argument_definition*(module_ref: ModuleRef,
    name: Identifier): ArgumentDefinition =
  ArgumentDefinition(name: name, module_ref: module_ref)

proc new_argument_definition(module_ref: string, name: string): Result[
    ArgumentDefinition, string] =
  let module_ref_id = ? new_module_ref(module_ref)
  let name_id = ? new_identifier(name)
  ok(new_argument_definition(module_ref_id, name_id))

proc module_ref*(def: ArgumentDefinition): ModuleRef =
  def.module_ref

proc location*(def: ArgumentDefinition): Location =
  def.module_ref.location

proc asl(def: ArgumentDefinition): string =
  let name_str = def.name.asl
  let ref_str = def.module_ref.asl
  fmt"{ref_str} {name_str}"

proc name*(def: ArgumentDefinition): Identifier = def.name
proc hash(def: ArgumentDefinition): Hash = hash(def.module_ref)

proc argument_definition_spec(parser: Parser): Result[
    ArgumentDefinition, string] =
  let module_ref = ? parser.expect(module_ref_spec)
  discard ? parser.expect(strict_space_spec)
  let name = ? parser.expect(identifier_spec)
  ok(new_argument_definition(module_ref, name))

# TODO: Fix this later.
proc struct_field_definition_spec(parser: Parser, indent: int): Result[
    ArgumentDefinition, string] =
  discard ? parser.expect(indent_spec, indent)
  let field = ? parser.expect(argument_definition_spec)
  ok(field)

type Struct* = ref object of RootObj
  def: StructDefinition
  fields: seq[ArgumentDefinition]
  fields_map: Table[Identifier, int]

proc new_struct*(def: StructDefinition, fields: seq[
    ArgumentDefinition]): Result[Struct, string] =
  if fields.len == 0:
    return err(fmt"{def.location} [PE106] struct block can not be empty")
  if fields.len > MAX_ARGS_LENGTH:
    return err(fmt"{def.location} [PE107] struct field length `{fields.len}` exceeded maximum field length `{MAX_ARGS_LENGTH}`")

  var fields_map: Table[Identifier, int]
  for index, field in fields.pairs:
    if field.name in fields_map:
      let predefined_field_location = fields[fields_map[field.name]].location
      return err(fmt"{field.location} [PE108] field `{field.name.asl}` is already defined at {predefined_field_location}")
    fields_map[field.name] = index

  ok(Struct(def: def, fields: fields, fields_map: fields_map))

proc find_field*(struct: Struct, field: Identifier): Result[ModuleRef, string] =
  if field notin struct.fields_map:
    err(fmt"{field.location} [PE109] field `{field.asl}` does not exist")
  else:
    ok(struct.fields[struct.fields_map[field]].module_ref)

proc fields*(struct: Struct): seq[ArgumentDefinition] = struct.fields

proc location*(struct: Struct): Location =
  struct.def.location

proc name*(struct: Struct): Result[Identifier, string] = name(struct.def)
proc def*(struct: Struct): StructDefinition = struct.def

proc asl(struct: Struct, indent: string): seq[string] =
  let header = struct.def.asl
  var fields: seq[string]
  for field in struct.fields:
    fields.add(indent & field.asl)

  return (@[header] & fields)

proc struct_spec(parser: Parser, indent: int): Result[Struct, string] =
  discard ? parser.expect(indent_spec, indent)
  let def = ? parser.expect(struct_definition_spec)
  discard ? parser.expect(strict_empty_line_spec)

  var fields: seq[ArgumentDefinition]
  # NOTE: struct must always at least have 1 field.
  fields.add( ? parser.expect(struct_field_definition_spec, indent + 1))
  discard ? parser.expect(strict_empty_line_spec)

  var maybe_field = parser.expect(struct_field_definition_spec, indent + 1)
  while maybe_field.is_ok:
    fields.add(maybe_field.get)
    discard ? parser.expect(strict_empty_line_spec)
    maybe_field = parser.expect(struct_field_definition_spec, indent + 1)

  new_struct(def, fields)

type FunctionDefinition* = ref object of RootObj
  name: Identifier
  returns: ModuleRef
  args: seq[ArgumentDefinition]
  location: Location

proc new_function_definition*(name: Identifier, args: seq[ArgumentDefinition],
    returns: ModuleRef, location: Location): Result[FunctionDefinition, string] =
  if args.len == 0:
    return err(fmt"{location} [PE110] function argument list can not be empty")
  if args.len > MAX_ARGS_LENGTH:
    return err(fmt"{location} [PE111] function argument length `{args.len}` exceeded maximum argument length `{MAX_ARGS_LENGTH}`")

  var args_map: Table[Identifier, int]
  for index, arg in args.pairs:
    if arg.name in args_map:
      let predefined_arg_location = args[args_map[arg.name]].location
      return err(fmt"{arg.location} [PE112] argument `{arg.name.asl}` is already defined at {predefined_arg_location}")
    args_map[arg.name] = index

  ok(FunctionDefinition(name: name, args: args, returns: returns,
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

proc hash(def: FunctionDefinition): Hash =
  var acc = hash(def.name)
  for arg in def.args:
    acc = acc !& hash(arg)
  return acc

proc argument_definition_list_spec(parser: Parser): Result[seq[
    ArgumentDefinition], string] =
  var argdefs: seq[ArgumentDefinition]
  discard ? parser.expect(open_paren_bracket_spec)
  discard ? parser.expect(optional_space_spec)
  # NOTE: Every function must have an input argument
  argdefs.add( ? parser.expect(argument_definition_spec))
  discard ? parser.expect(optional_space_spec)

  while parser.expect(comma_spec).is_ok:
    discard ? parser.expect(optional_space_spec)
    argdefs.add( ? parser.expect(argument_definition_spec))
    discard ? parser.expect(optional_space_spec)

  discard ? parser.expect(close_paren_bracket_spec)
  ok(argdefs)

proc function_definition_spec(parser: Parser, indent: int): Result[
    FunctionDefinition, string] =
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

type UnsignedIntegerLiteral* = ref object of RootObj
  value: string
  location: Location

proc new_unsigned_integer*(digits: Token): UnsignedIntegerLiteral =
  UnsignedIntegerLiteral(value: digits.value, location: digits.location)

proc asl(unsigned_integer: UnsignedIntegerLiteral): string =
  unsigned_integer.value

proc unsigned_integer_spec(parser: Parser): Result[UnsignedIntegerLiteral, string] =
  # TODO: Support underscore separated values as integers as well.
  let int_value_token = ? parser.token_spec_util(TK_DIGITS)
  ok(new_unsigned_integer(int_value_token))

type
  SignedIntegerLiteralKind* = enum
    SIK_POSITIVE, SIK_NEGATIVE
  SignedIntegerLiteral* = ref object of RootObj
    kind: SignedIntegerLiteralKind
    value: string
    location: Location

proc new_signed_integer*(sign: Token, unsigned_integer: UnsignedIntegerLiteral): Result[
    SignedIntegerLiteral, string] =
  case sign.kind:
  of TK_PLUS:
    ok(SignedIntegerLiteral(kind: SIK_POSITIVE, value: unsigned_integer.value,
        location: sign.location))
  of TK_MINUS:
    ok(SignedIntegerLiteral(kind: SIK_NEGATIVE, value: unsigned_integer.value,
        location: sign.location))
  else:
    return err(fmt"{sign.location} [PE113] expected a sign `+` or `-` but found {sign.value}")

proc asl(signed_integer: SignedIntegerLiteral): string =
  let sign =
    case signed_integer.kind:
    of SIK_POSITIVE: ""
    of SIK_NEGATIVE: "-"
  return sign & signed_integer.value

proc sign_spec(parser: Parser): Result[Token, string] =
  let maybe_plus = parser.token_spec_util(TK_PLUS)
  if maybe_plus.is_ok:
    maybe_plus
  else:
    parser.token_spec_util(TK_MINUS)

proc signed_integer_spec(parser: Parser): Result[SignedIntegerLiteral, string] =
  var sign = ? parser.expect(sign_spec)
  let unsigned_intvalue = ? parser.expect(unsigned_integer_spec)
  new_signed_integer(sign, unsigned_intvalue)

type
  IntegerLiteralKind* = enum
    ILK_SIGNED, ILK_UNSIGNED
  IntegerLiteral* = ref object of RootObj
    case kind: IntegerLiteralKind
    of ILK_SIGNED: signed: SignedIntegerLiteral
    of ILK_UNSIGNED: unsigned: UnsignedIntegerLiteral

proc new_integer_literal*(signed: SignedIntegerLiteral): IntegerLiteral =
  IntegerLiteral(kind: ILK_SIGNED, signed: signed)

proc new_integer_literal*(unsigned: UnsignedIntegerLiteral): IntegerLiteral =
  IntegerLiteral(kind: ILK_UNSIGNED, unsigned: unsigned)

proc location(integer: IntegerLiteral): Location =
  case integer.kind:
  of ILK_SIGNED: integer.signed.location
  of ILK_UNSIGNED: integer.unsigned.location

proc asl*(integer: IntegerLiteral): string =
  case integer.kind:
  of ILK_SIGNED: integer.signed.asl
  of ILK_UNSIGNED: integer.unsigned.asl

proc integer_spec(parser: Parser): Result[IntegerLiteral, string] =
  let maybe_unsigned_integer = parser.expect(unsigned_integer_spec)
  if maybe_unsigned_integer.is_ok:
    ok(new_integer_literal(maybe_unsigned_integer.get))
  else:
    let signed_integer = ? parser.expect(signed_integer_spec)
    ok(new_integer_literal(signed_integer))

type FloatLiteral* = ref object of RootObj
  value: string
  location: Location

proc new_float_literal*(first: IntegerLiteral,
    second: UnsignedIntegerLiteral): FloatLiteral =
  let value = first.asl & "." & second.asl
  FloatLiteral(value: value, location: first.location)

proc asl*(float_literal: FloatLiteral): string =
  float_literal.value

proc float_spec(parser: Parser): Result[FloatLiteral, string] =
  # TODO: Improve float parsing to support scientific notation as well.
  let first = ? parser.expect(integer_spec)
  discard ? parser.expect(dot_spec)
  let second = ? parser.expect(unsigned_integer_spec)
  ok(new_float_literal(first, second))

type StringLiteral* = ref object of RootObj
  value: string
  location: Location

proc new_string_literal*(token: Token): Result[StringLiteral, string] =
  case token.kind:
  of TK_STRING:
    ok(StringLiteral(value: token.value, location: token.location))
  else:
    err(fmt"{token.location} [PE114] expected a string found token of type `{token.kind}` with value: `{token.value}`")

proc asl*(string_literal: StringLiteral): string =
  string_literal.value

proc string_spec(parser: Parser): Result[StringLiteral, string] =
  let token = ? parser.token_spec_util(TK_STRING)
  new_string_literal(token)

type
  LiteralKind* = enum
    LK_INTEGER, LK_FLOAT, LK_STRING
  Literal* = ref object of RootObj
    case kind: LiteralKind
    of LK_INTEGER: integer_literal: IntegerLiteral
    of LK_FLOAT: float_literal: FloatLiteral
    of LK_STRING: string_literal: StringLiteral

proc new_literal*(integer_literal: IntegerLiteral): Literal =
  Literal(kind: LK_INTEGER, integer_literal: integer_literal)

proc new_literal*(float_literal: FloatLiteral): Literal =
  Literal(kind: LK_FLOAT, float_literal: float_literal)

proc new_literal*(string_literal: StringLiteral): Literal =
  Literal(kind: LK_STRING, string_literal: string_literal)

proc location*(literal: Literal): Location =
  case literal.kind:
  of LK_INTEGER: literal.integer_literal.location
  of LK_FLOAT: literal.float_literal.location
  of LK_STRING: literal.string_literal.location

proc kind*(literal: Literal): LiteralKind = literal.kind
proc integer_literal*(literal: Literal): Result[IntegerLiteral, string] =
  case literal.kind:
  of LK_INTEGER: ok(literal.integer_literal)
  else: err("{literal.location} [PE115] is not an integer")
proc float_literal*(literal: Literal): Result[FloatLiteral, string] =
  case literal.kind:
  of LK_FLOAT: ok(literal.float_literal)
  else: err("{literal.location} [PE116] is not a float")
proc string_literal*(literal: Literal): Result[StringLiteral, string] =
  case literal.kind:
  of LK_STRING: ok(literal.string_literal)
  else: err("{literal.location} [PE117] is not a string")

proc asl*(literal: Literal): string =
  case literal.kind:
  of LK_INTEGER: literal.integer_literal.asl
  of LK_FLOAT: literal.float_literal.asl
  of LK_STRING: literal.string_literal.asl

proc literal_spec(parser: Parser): Result[Literal, string] =
  let maybe_integer = parser.expect(integer_spec)
  if maybe_integer.is_ok:
    return ok(new_literal(maybe_integer.get))

  let maybe_float = parser.expect(float_spec)
  if maybe_float.is_ok:
    return ok(new_literal(maybe_float.get))

  let maybe_string = parser.expect(string_spec)
  if maybe_string.is_ok:
    return ok(new_literal(maybe_string.get))

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
  of AK_LITERAL: err("{arg.location} [PE118] expected argument to be a variable but found literal `{arg.literal.asl}`")
  of AK_VARIABLE: ok(arg.variable)

proc literal*(arg: Argument): Result[Literal, string] =
  case arg.kind:
  of AK_LITERAL: ok(arg.literal)
  of AK_VARIABLE: err("{arg.location} [PE119] expected argument to be a literal but found variable `{arg.variable.asl}`")

proc asl*(arg: Argument): string =
  case arg.kind:
  of AK_LITERAL: arg.literal.asl
  of AK_VARIABLE: arg.variable.asl

proc argument_spec(parser: Parser): Result[Argument, string] =
  let maybe_identifier = parser.expect(identifier_spec)
  if maybe_identifier.is_ok:
    ok(new_argument(maybe_identifier.get))
  else:
    let literal = ? parser.expect(literal_spec)
    ok(new_argument(literal))

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

proc asl(fnref: FunctionRef): string =
  case fnref.kind:
  of FRK_LOCAL: fnref.name.asl
  of FRK_MODULE: fmt"{fnref.module.asl}.{fnref.name.asl}"

proc kind*(fnref: FunctionRef): FunctionRefKind = fnref.kind
proc name*(fnref: FunctionRef): Identifier = fnref.name
proc module*(fnref: FunctionRef): Result[ModuleRef, string] =
  case fnref.kind:
  of FRK_LOCAL: err("{fnref.location} expected a module function call but found local function call")
  of FRK_MODULE: ok(fnref.module)

proc function_ref_local_spec(parser: Parser): Result[FunctionRef, string] =
  let name = ? parser.expect(identifier_spec)
  ok(new_function_ref(name))

proc function_ref_module_spec(parser: Parser): Result[FunctionRef, string] =
  let module_ref = ? parser.expect(module_ref_spec)
  discard ? parser.expect(dot_spec)
  let name = ? parser.expect(identifier_spec)
  ok(new_function_ref(name, module_ref))

proc function_ref_spec(parser: Parser): Result[FunctionRef, string] =
  let maybe_module_fnref = parser.expect(function_ref_module_spec)
  if maybe_module_fnref.is_ok:
    maybe_module_fnref
  else:
    parser.expect(function_ref_local_spec)

proc argument_list_spec(parser: Parser): Result[seq[Argument], string] =
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

type FunctionCall* = ref object of RootObj
  fnref: FunctionRef
  args: seq[Argument]

proc new_function_call*(fnref: FunctionRef, args: seq[Argument]): Result[
    FunctionCall, string] =
  if args.len == 0:
    return err(fmt"{fnref.location} [PE120] function call argument list can not be empty")
  if args.len > MAX_ARGS_LENGTH:
    return err(fmt"{fnref.location} [PE121] function call argument length `{args.len}` exceeded maximum args length `{MAX_ARGS_LENGTH}`")
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

proc function_call_spec(parser: Parser): Result[FunctionCall, string] =
  let fnref = ? parser.expect(function_ref_spec)
  let args = ? parser.expect(argument_list_spec)
  new_function_call(fnref, args)

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

proc literal_init_spec(parser: Parser): Result[LiteralInit, string] =
  let module_ref = ? parser.expect(module_ref_spec)
  discard ? parser.expect(strict_space_spec)
  let literal = ? parser.expect(literal_spec)
  ok(new_literal_init(module_ref, literal))

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

proc asl(struct_ref: StructRef): string =
  case struct_ref.kind:
  of SRK_DEFAULT: struct_ref.module.asl
  of SRK_NAMED: fmt"{struct_ref.module.asl}.{struct_ref.struct.asl}"

proc struct_ref_spec(parser: Parser): Result[StructRef, string] =
  let module = ? parser.expect(module_ref_spec)

  let maybe_dot = parser.expect(dot_spec)
  if maybe_dot.is_err:
    return ok(new_struct_ref(module))

  let struct = ? parser.expect(identifier_spec)
  ok(new_struct_ref(module, struct))

type KeywordArgument* = ref object of RootObj
  name: Identifier
  value: Argument

proc new_keyword_argument*(name: Identifier, value: Argument): KeywordArgument =
  KeywordArgument(name: name, value: value)

proc location(kwarg: KeywordArgument): Location =
  kwarg.name.location

proc name*(kwarg: KeywordArgument): Identifier = kwarg.name
proc value*(kwarg: KeywordArgument): Argument = kwarg.value

proc asl*(kwarg: KeywordArgument): string =
  fmt"{kwarg.name.asl}: {kwarg.value.asl}"

proc keyword_argument_spec(parser: Parser): Result[KeywordArgument, string] =
  let name = ? parser.expect(identifier_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(colon_spec)
  discard ? parser.expect(optional_space_spec)
  let value = ? parser.expect(argument_spec)
  ok(new_keyword_argument(name, value))

proc keyword_argument_list_spec(parser: Parser): Result[seq[KeywordArgument], string] =
  var args: seq[KeywordArgument]
  discard ? parser.expect(open_curly_bracket_spec)

  discard ? parser.expect(optional_space_spec)
  # NOTE: every struct init must have at least one keyword argument
  args.add( ? parser.expect(keyword_argument_spec))
  discard ? parser.expect(optional_space_spec)
  var maybe_comma = parser.expect(comma_spec)
  while maybe_comma.is_ok:
    discard ? parser.expect(optional_space_spec)
    args.add( ? parser.expect(keyword_argument_spec))
    discard ? parser.expect(optional_space_spec)
    maybe_comma = parser.expect(comma_spec)

  discard ? parser.expect(close_curly_bracket_spec)
  ok(args)

type StructInit* = ref object of RootObj
  struct_ref: StructRef
  args: seq[KeywordArgument]

proc new_struct_init*(struct_ref: StructRef, args: seq[
    KeywordArgument]): Result[StructInit, string] =
  if args.len == 0:
    return err(fmt"{struct_ref.location} [PE122] initializer field list can not be empty")

  if args.len > MAX_ARGS_LENGTH:
    return err(fmt"{struct_ref.location} [PE123] initializer field length `{args.len}` exceeded maximum field length `{MAX_ARGS_LENGTH}`")

  var args_map: Table[Identifier, int]
  for index, arg in args.pairs:
    if arg.name in args_map:
      let predefined_arg_location = args[args_map[arg.name]].location
      return err(fmt"{arg.location} [PE124] field `{arg.name.asl}` is already defined at {predefined_arg_location}")
    args_map[arg.name] = index

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

proc struct_init_spec(parser: Parser): Result[StructInit, string] =
  let struct_ref = ? parser.expect(struct_ref_spec)
  discard ? parser.expect(optional_space_spec)
  let kwargs = ? parser.expect(keyword_argument_list_spec)
  new_struct_init(struct_ref, kwargs)

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

proc asl(init: Initializer): string =
  case init.kind:
  of IK_LITERAL: init.literal.asl
  of IK_STRUCT: init.struct.asl

proc initializer_spec(parser: Parser): Result[Initializer, string] =
  let maybe_literal_init = parser.expect(literal_init_spec)
  if maybe_literal_init.is_ok:
    ok(new_initializer(maybe_literal_init.get))
  else:
    let struct_init = ? parser.expect(struct_init_spec)
    ok(new_initializer(struct_init))

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

proc struct_get_spec(parser: Parser): Result[StructGet, string] =
  let name = ? parser.expect(identifier_spec)
  discard ? parser.expect(dot_spec)
  let field = ? parser.expect(identifier_spec)
  ok(new_struct_get(name, field))

type
  MatchDefinitionKind* = enum
    MDK_DEFAULT, MDK_ASSIGNED
  MatchDefinition* = ref object of RootObj
    kind: MatchDefinitionKind
    operand: Identifier
    arg: Identifier

proc new_match_definition*(operand: Identifier,
    location: Location): Result[MatchDefinition, string] =
  let arg = new_identifier(location)
  ok(MatchDefinition(kind: MDK_DEFAULT, arg: arg, operand: operand))

proc new_match_definition*(def: MatchDefinition,
    arg: Identifier): MatchDefinition =
  MatchDefinition(kind: MDK_ASSIGNED, arg: arg, operand: def.operand)

proc location*(def: MatchDefinition): Location = def.arg.location
proc operand*(def: MatchDefinition): Identifier = def.operand
proc arg*(def: MatchDefinition): Identifier = def.arg

proc asl(def: MatchDefinition): string =
  case def.kind:
  of MDK_DEFAULT: fmt"match {def.operand.asl}:"
  of MDK_ASSIGNED: fmt"{def.arg.asl} = match {def.operand.asl}:"

proc match_definition_default_spec(parser: Parser): Result[
    MatchDefinition, string] =
  let match_keyword = ? parser.expect(match_keyword_spec)
  discard ? parser.expect(strict_space_spec)
  let operand = ? parser.expect(identifier_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(colon_spec)
  new_match_definition(operand, match_keyword.location)

proc match_definition_spec(parser: Parser): Result[MatchDefinition, string] =
  let maybe_match_def_default = parser.expect(match_definition_default_spec)
  if maybe_match_def_default.is_ok:
    return maybe_match_def_default

  let arg = ? parser.expect(identifier_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(equal_spec)
  discard ? parser.expect(optional_space_spec)
  let match_def_default = ? parser.expect(match_definition_default_spec)
  ok(new_match_definition(match_def_default, arg))

proc keyword_value_identifier_spec(parser: Parser): Result[(Identifier,
    Identifier), string] =
  let name = ? parser.expect(identifier_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(colon_spec)
  discard ? parser.expect(optional_space_spec)
  let value = ? parser.expect(identifier_spec)
  ok((name, value))

type
  StructPatternKind* = enum
    SPK_DEFAULT, SPK_NAMED
  StructPattern* = ref object of RootObj
    location: Location
    args: seq[(Identifier, Identifier)]
    case kind: StructPatternKind
    of SPK_DEFAULT: discard
    of SPK_NAMED: struct: Identifier

proc new_struct_pattern*(args: seq[(Identifier, Identifier)],
    location: Location): Result[StructPattern, string] =
  if args.len == 0:
    return err(fmt"{location} [PE125] pattern field list can not be empty")
  if args.len > MAX_ARGS_LENGTH:
    return err(fmt"{location} [PE126] pattern field length `{args.len}` exceeded maximum field length `{MAX_ARGS_LENGTH}`")

  var keys_map: Table[Identifier, int]
  var values_map: Table[Identifier, int]
  for index, (key, value) in args.pairs:
    if key in keys_map:
      let predefined_field_location = args[keys_map[key]][0].location
      return err(fmt"{key.location} [PE127] field `{key.asl}` is already defined at {predefined_field_location}")
    keys_map[key] = index

    if value in values_map:
      let predefined_field_location = args[values_map[value]][1].location
      return err(fmt"{value.location} [PE128] field `{value.asl}` is already defined at {predefined_field_location}")
    values_map[value] = index

  ok(StructPattern(kind: SPK_DEFAULT, args: args, location: location))

proc new_struct_pattern*(struct: Identifier, pattern: StructPattern): Result[
    StructPattern, string] =
  case pattern.kind:
  of SPK_DEFAULT:
    ok(StructPattern(kind: SPK_NAMED, location: struct.location, struct: struct,
        args: pattern.args))
  of SPK_NAMED:
    err(fmt"{struct.location} [PE129] [UNREACHABLE] named struct pattern can not be converted to another named struct pattern")

proc location*(pattern: StructPattern): Location = pattern.location
proc kind*(pattern: StructPattern): StructPatternKind = pattern.kind
proc args*(pattern: StructPattern): seq[(Identifier, Identifier)] = pattern.args
proc struct*(pattern: StructPattern): Result[Identifier, string] =
  case pattern.kind:
  of SPK_DEFAULT: err(fmt"{pattern.location} expected a named struct but found a default struct")
  of SPK_NAMED: ok(pattern.struct)

proc asl*(pattern: StructPattern): string =
  var args: seq[string]
  for (key, val) in pattern.args:
    args.add(fmt"{key.asl}: {val.asl}")

  case pattern.kind:
  of SPK_DEFAULT: "{ " & args.join(", ") & " }"
  of SPK_NAMED: pattern.struct.asl & " { " & args.join(", ") & " }"

proc struct_pattern_default_spec(parser: Parser): Result[StructPattern, string] =
  let open_curly = ? parser.expect(open_curly_bracket_spec)
  discard ? parser.expect(optional_space_spec)

  var keywords: seq[(Identifier, Identifier)]
  keywords.add( ? parser.expect(keyword_value_identifier_spec))
  discard ? parser.expect(optional_space_spec)
  var maybe_comma = parser.expect(comma_spec)
  while maybe_comma.is_ok:
    discard ? parser.expect(optional_space_spec)
    keywords.add( ? parser.expect(keyword_value_identifier_spec))
    discard ? parser.expect(optional_space_spec)
    maybe_comma = parser.expect(comma_spec)

  discard ? parser.expect(close_curly_bracket_spec)
  new_struct_pattern(keywords, open_curly.location)

proc struct_pattern_named_spec(parser: Parser): Result[StructPattern, string] =
  let struct = ? parser.expect(identifier_spec)
  discard ? parser.expect(optional_space_spec)
  let struct_pattern_default = ? parser.expect(struct_pattern_default_spec)
  new_struct_pattern(struct, struct_pattern_default)

proc struct_pattern_spec(parser: Parser): Result[StructPattern, string] =
  let maybe_struct_pattern_named = parser.expect(struct_pattern_named_spec)
  if maybe_struct_pattern_named.is_ok:
    maybe_struct_pattern_named
  else:
    parser.expect(struct_pattern_default_spec)

type
  CasePatternKind* = enum
    CPK_LITERAL, CPK_STRUCT
  CasePattern* = ref object of RootObj
    case kind: CasePatternKind
    of CPK_LITERAL: literal: Literal
    of CPK_STRUCT: struct: StructPattern

proc new_case_pattern*(literal: Literal): CasePattern =
  CasePattern(kind: CPK_LITERAL, literal: literal)

proc new_case_pattern*(struct: StructPattern): CasePattern =
  CasePattern(kind: CPK_STRUCT, struct: struct)

proc location*(pattern: CasePattern): Location =
  case pattern.kind:
  of CPK_LITERAL: pattern.literal.location
  of CPK_STRUCT: pattern.struct.location

proc kind*(pattern: CasePattern): CasePatternKind = pattern.kind
proc literal*(pattern: CasePattern): Result[Literal, string] =
  case pattern.kind:
  of CPK_LITERAL: ok(pattern.literal)
  of CPK_STRUCT: err(fmt"{pattern.location} expected case pattern to be literal but struct was found")
proc struct*(pattern: CasePattern): Result[StructPattern, string] =
  case pattern.kind:
  of CPK_LITERAL: err(fmt"{pattern.location} expected case pattern to be struct but literal was found")
  of CPK_STRUCT: ok(pattern.struct)

proc asl(pattern: CasePattern): string =
  case pattern.kind:
  of CPK_LITERAL: pattern.literal.asl
  of CPK_STRUCT: pattern.struct.asl

proc case_pattern_spec(parser: Parser): Result[CasePattern, string] =
  let maybe_struct_pattern = parser.expect(struct_pattern_spec)
  if maybe_struct_pattern.is_ok:
    ok(new_case_pattern(maybe_struct_pattern.get))
  else:
    let literal = ? parser.expect(literal_spec)
    ok(new_case_pattern(literal))

type CaseDefinition* = ref object of RootObj
  pattern: CasePattern
  location: Location

proc new_case_definition*(pattern: CasePattern,
    location: Location): CaseDefinition =
  CaseDefinition(pattern: pattern, location: location)

proc location*(def: CaseDefinition): Location = def.location
proc pattern*(def: CaseDefinition): CasePattern = def.pattern

proc asl(def: CaseDefinition): string =
  fmt"case {def.pattern.asl}:"

proc case_definition_spec(parser: Parser): Result[CaseDefinition, string] =
  let case_keyword = ? parser.expect(case_keyword_spec)
  discard ? parser.expect(space_spec)
  discard ? parser.expect(optional_space_spec)
  let pattern = ? parser.expect(case_pattern_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(colon_spec)
  ok(new_case_definition(pattern, case_keyword.location))

# This block is together due to match <-> expression cyclic dependency by design
type
  ExpressionKind* = enum
    EK_MATCH, EK_FNCALL, EK_INIT, EK_STRUCT_GET, EK_VARIABLE
  Expression* = ref object of RootObj
    case kind: ExpressionKind
    of EK_MATCH: match: Match
    of EK_FNCALL: fncall: FunctionCall
    of EK_INIT: init: Initializer
    of EK_STRUCT_GET: struct_get: StructGet
    of EK_VARIABLE: variable: Identifier
  StatementKind = enum
    SK_USER, SK_AUTO
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
  MatchKind* = enum
    MK_CASE_ONLY, MK_COMPLETE
  Match* = ref object of RootObj
    def: MatchDefinition
    case_blocks: seq[Case]
    case kind: MatchKind
    of MK_CASE_ONLY: discard
    of MK_COMPLETE: else_block: Else

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

# Forward declaration needed due to match <-> expression cyclic dependency by design
proc location*(match: Match): Location

proc location*(expression: Expression): Location =
  case expression.kind:
  of EK_MATCH: expression.match.location
  of EK_FNCALL: expression.fncall.location
  of EK_INIT: expression.init.location
  of EK_STRUCT_GET: expression.struct_get.location
  of EK_VARIABLE: expression.variable.location

# Forward declaration needed due to match <-> expression cyclic dependency by design
proc asl(match: Match, indent: string): seq[string]

proc asl(expression: Expression, indent: string): seq[string] =
  case expression.kind:
  of EK_MATCH: expression.match.asl(indent)
  of EK_FNCALL: @[expression.fncall.asl]
  of EK_INIT: @[expression.init.asl]
  of EK_STRUCT_GET: @[expression.struct_get.asl]
  of EK_VARIABLE: @[expression.variable.asl]

proc kind*(expression: Expression): ExpressionKind = expression.kind

proc match*(expression: Expression): Result[Match, string] =
  case expression.kind:
  of EK_MATCH: ok(expression.match)
  else: err(fmt"{expression.location} expression is not a function call")

proc fncall*(expression: Expression): Result[FunctionCall, string] =
  case expression.kind:
  of EK_FNCALL: ok(expression.fncall)
  else: err(fmt"{expression.location} expression is not a function call")

proc init*(expression: Expression): Result[Initializer, string] =
  case expression.kind:
  of EK_INIT: ok(expression.init)
  else: err(fmt"{expression.location} expression is not an initializer")

proc struct_get*(expression: Expression): Result[StructGet, string] =
  case expression.kind:
  of EK_STRUCT_GET: ok(expression.struct_get)
  else: err(fmt"{expression.location} expression is not a struct get")

proc variable*(expression: Expression): Result[Identifier, string] =
  case expression.kind:
  of EK_VARIABLE: ok(expression.variable)
  else: err(fmt"{expression.location} expression is not a variable")

# Forward declaration needed due to match <-> expression cyclic dependency
proc match_spec(parser: Parser, indent: int): Result[Match, string]

proc expression_spec(parser: Parser, indent: int): Result[Expression, string] =
  let maybe_match = parser.expect(match_spec, indent)
  if maybe_match.is_ok:
    return ok(new_expression(maybe_match.get))

  let maybe_fncall = parser.expect(function_call_spec)
  if maybe_fncall.is_ok:
    return ok(new_expression(maybe_fncall.get))

  let maybe_init = parser.expect(initializer_spec)
  if maybe_init.is_ok:
    return ok(new_expression(maybe_init.get))

  let maybe_struct_get = parser.expect(struct_get_spec)
  if maybe_struct_get.is_ok:
    return ok(new_expression(maybe_struct_get.get))

  let variable = ? parser.expect(identifier_spec)
  ok(new_expression(variable))

# Statement
proc new_statement*(expression: Expression): Statement =
  let arg = new_identifier(expression.location)
  Statement(kind: SK_AUTO, arg: arg, expression: expression)

proc new_statement*(arg: Identifier, expression: Expression): Statement =
  Statement(kind: SK_USER, arg: arg, expression: expression)

proc location*(statement: Statement): Location = statement.arg.location
proc expression*(statement: Statement): Expression = statement.expression
proc arg*(statement: Statement): Identifier = statement.arg

proc asl*(statement: Statement, indent: string): seq[string] =
  var lines = statement.expression.asl(indent)
  case statement.kind:
  of SK_AUTO: discard
  of SK_USER: lines[0] = fmt"{statement.arg.asl} = {lines[0]}"
  return lines

proc assignment_spec(parser: Parser): Result[Identifier, string] =
  let arg = ? parser.expect(identifier_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(equal_spec)
  discard ? parser.expect(optional_space_spec)
  ok(arg)

proc statement_spec(parser: Parser, indent: int): Result[Statement, string] =
  discard ? parser.expect(indent_spec, indent)

  let maybe_assignment = parser.expect(assignment_spec)
  let expression = ? parser.expect(expression_spec, indent)
  if maybe_assignment.is_ok:
    ok(new_statement(maybe_assignment.get, expression))
  else:
    ok(new_statement(expression))

# Case
proc new_case*(def: CaseDefinition, statements: seq[Statement]): Result[Case, string] =
  if statements.len == 0:
    return err(fmt"{def.location} [PE130] case block must have at least one statement")
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

proc case_spec(parser: Parser, indent: int): Result[Case, string] =
  discard ? parser.expect(indent_spec, indent)
  let case_def = ? parser.expect(case_definition_spec)
  discard ? parser.expect(optional_empty_line_spec)
  var statements: seq[Statement]
  var maybe_statement = parser.expect(statement_spec, indent + 1)
  while maybe_statement.is_ok:
    statements.add(maybe_statement.get)
    discard ? parser.expect(optional_empty_line_spec)
    maybe_statement = parser.expect(statement_spec, indent + 1)
  new_case(case_def, statements)

# Else
proc new_else*(statements: seq[Statement], location: Location): Result[Else, string] =
  if statements.len == 0:
    return err(fmt"{location} [PE131] else block must have at least one statement")

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

proc else_spec(parser: Parser, indent: int): Result[Else, string] =
  discard ? parser.expect(indent_spec, indent)

  let else_def = ? parser.expect(else_keyword_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(colon_spec)
  discard ? parser.expect(optional_empty_line_spec)

  var statements: seq[Statement]
  var maybe_statement = parser.expect(statement_spec, indent + 1)
  while maybe_statement.is_ok:
    statements.add(maybe_statement.get)
    discard ? parser.expect(optional_empty_line_spec)
    maybe_statement = parser.expect(statement_spec, indent + 1)

  new_else(statements, else_def.location)

# Match
proc new_match*(def: MatchDefinition, case_blocks: seq[Case]): Result[Match, string] =
  if case_blocks.len < 2:
    return err(fmt"{location(def)} [PE132] match block must have at least 2 case blocks")
  ok(Match(kind: MK_CASE_ONLY, def: def, case_blocks: case_blocks))

proc new_match*(def: MatchDefinition, case_blocks: seq[Case],
    else_block: Else): Result[Match, string] =
  if case_blocks.len < 1:
    return err(fmt"{location(def)} [PE133] match block must have at least 1 case block")

  ok(Match(kind: MK_COMPLETE, def: def, case_blocks: case_blocks,
      else_block: else_block))

proc location*(match: Match): Location =
  match.def.location

proc def*(match: Match): MatchDefinition = match.def

proc kind*(match: Match): MatchKind = match.kind
proc case_blocks*(match: Match): seq[Case] = match.case_blocks
proc else_block*(match: Match): Result[Else, string] =
  case match.kind:
  of MK_CASE_ONLY: err("{match.location} match block does not have any else block")
  of MK_COMPLETE: ok(match.else_block)

proc asl(match: Match, indent: string): seq[string] =
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

proc match_spec(parser: Parser, indent: int): Result[Match, string] =
  let match_def = ? parser.expect(match_definition_spec)
  var cases: seq[Case]

  discard ? parser.expect(optional_empty_line_spec)
  var maybe_case = parser.expect(case_spec, indent + 1)
  while maybe_case.is_ok:
    cases.add(maybe_case.get)
    discard ? parser.expect(optional_empty_line_spec)
    maybe_case = parser.expect(case_spec, indent + 1)

  var maybe_else = parser.expect(else_spec, indent + 1)
  if maybe_else.is_ok:
    return new_match(match_def, cases, maybe_else.get)

  return new_match(match_def, cases)

type Function* = ref object of RootObj
  def: FunctionDefinition
  steps: seq[Statement]

proc new_function*(def: FunctionDefinition, steps: seq[Statement]): Result[
    Function, string] =
  if steps.len == 0:
    return err(fmt"{def.location} [PE134] function `{def.name.asl}` must have at least one statement")

  ok(Function(def: def, steps: steps))

proc location*(function: Function): Location = function.def.location
proc name*(function: Function): Identifier = function.def.name
proc def*(function: Function): FunctionDefinition = function.def
proc steps*(function: Function): seq[Statement] = function.steps

proc asl*(function: Function, indent: string): seq[string] =
  let header = function.def.asl

  var lines: seq[string]
  for step in function.steps:
    for line in step.asl(indent):
      lines.add(indent & line)

  return (@[header] & lines)

proc function_spec(parser: Parser, indent: int): Result[Function, string] =
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

type
  GenericKind* = enum
    GK_DEFAULT, GK_CONSTRAINED
  Generic* = ref object of RootObj
    name: Identifier
    location: Location
    defs_hash_map: Table[Hash, int]
    defs_map: Table[Identifier, Table[int, seq[int]]] # Name => Arity => Indexes
    case kind: GenericKind
    of GK_DEFAULT: discard
    of GK_CONSTRAINED: defs: seq[FunctionDefinition]

proc new_generic*(name: Identifier, location: Location): Generic =
  Generic(kind: GK_DEFAULT, name: name, location: location)

proc new_generic*(name: Identifier, defs: seq[FunctionDefinition],
    location: Location): Result[Generic, string] =
  if defs.len == 0:
    return err(fmt"{location} [PE135] generic `{name.asl}` must have at least one constraint")

  var defs_map: Table[Identifier, Table[int, seq[int]]]
  var defs_hash_map: Table[Hash, int]
  for index, def in defs.pairs:
    let def_hash = def.hash
    if def_hash in defs_hash_map:
      let predefined_def_location = defs[defs_hash_map[def_hash]].location
      return err(fmt"{def.location} [PE136] generic constraint `{def.name.asl}` is already defined at {predefined_def_location}")
    defs_hash_map[def_hash] = index

    if def.name notin defs_map:
      defs_map[def.name] = init_table[int, seq[int]]()
    if def.args.len notin defs_map[def.name]:
      defs_map[def.name][def.args.len] = new_seq[int]()
    defs_map[def.name][def.args.len].add(index)

  ok(Generic(kind: GK_CONSTRAINED, name: name, defs: defs, defs_map: defs_map,
      defs_hash_map: defs_hash_map, location: location))

proc module_ref*(generic: Generic): ModuleRef =
  new_module_ref(generic.name)

proc location*(generic: Generic): Location =
  generic.location

proc defs*(generic: Generic): seq[FunctionDefinition] =
  case generic.kind:
  of GK_DEFAULT: @[]
  of GK_CONSTRAINED: generic.defs

proc name*(generic: Generic): Identifier =
  generic.name

proc asl*(generic: Generic, indent: string): seq[string] =
  case generic.kind:
  of GK_DEFAULT:
    @[fmt"generic {generic.name.asl}"]
  of GK_CONSTRAINED:
    let header = fmt"generic {generic.name.asl}:"

    var defs: seq[string]
    for def in generic.defs:
      defs.add(indent & def.asl)

    @[header] & defs

proc hash*(generic: Generic): Hash =
  generic.location.hash

proc `==`*(self: Generic, other: Generic): bool =
  self.hash == other.hash

proc generic_default_spec(parser: Parser, indent: int): Result[Generic, string] =
  discard ? parser.expect(indent_spec, indent)
  let generic_keyword = ? parser.expect(generic_keyword_spec)
  discard ? parser.expect(space_spec)
  discard ? parser.expect(optional_space_spec)
  let name = ? parser.expect(identifier_spec)
  ok(new_generic(name, generic_keyword.location))

proc generic_constrained_spec(parser: Parser, indent: int): Result[Generic, string] =
  discard ? parser.expect(indent_spec, indent)
  let generic_keyword = ? parser.expect(generic_keyword_spec)
  discard ? parser.expect(space_spec)
  discard ? parser.expect(optional_space_spec)
  let name = ? parser.expect(identifier_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(colon_spec)

  var defs: seq[FunctionDefinition]
  discard ? parser.expect(optional_empty_line_spec)

  var maybe_func_def = parser.expect(function_definition_spec, indent + 1)
  while maybe_func_def.is_ok:
    defs.add(maybe_func_def.get)
    discard ? parser.expect(strict_empty_line_spec)
    maybe_func_def = parser.expect(function_definition_spec, indent + 1)

  new_generic(name, defs, generic_keyword.location)

proc generic_spec(parser: Parser, indent: int): Result[Generic, string] =
  let maybe_generic_constrained = parser.expect(generic_constrained_spec, indent)
  if maybe_generic_constrained.is_ok:
    maybe_generic_constrained
  else:
    # NOTE: generic default parser must be second since it is a subset of
    # generic_named spec and therefore may result in malformed parsing.
    parser.expect(generic_default_spec, indent)

type UserModule* = ref object of RootObj
  def: UserModuleDefinition
  generics: seq[Generic]
  generics_map: Table[Identifier, int]
  structs: seq[Struct]
  default_struct_index: int
  structs_map: Table[Identifier, int]
  functions: seq[Function]
  functions_map: Table[Identifier, seq[int]]
  function_defs_hash_map: Table[Hash, int]

proc new_user_module*(def: UserModuleDefinition, generics: seq[Generic],
    structs: seq[Struct], functions: seq[Function]): Result[UserModule, string] =
  if generics.len + structs.len + functions.len == 0:
    return err(fmt"{def.location} [PE142] module can not be empty")

  if generics.len > 0 and structs.len + functions.len == 0:
    return err(fmt"{def.location} [PE143] module can not only contain generics")

  var generics_map: Table[Identifier, int]
  for index, generic in generics:
    if generic.name in generics_map:
      let predefined_generic_location = generics[generics_map[
          generic.name]].location
      return err(fmt"{generic.location} [PE144] generic `{generic.name.asl}` is already defined at {predefined_generic_location}")
    generics_map[generic.name] = index

  var structs_map: Table[Identifier, int]
  var default_struct_index = -1
  for index, struct in structs:
    case struct.def.kind:
    of SDK_DEFAULT:
      if default_struct_index == -1:
        default_struct_index = index
      else:
        let predefined_default_struct_location = structs[
            default_struct_index].location
        return err(fmt"{struct.location} [PE145] default struct is already defined at {predefined_default_struct_location}")
    of SDK_NAMED:
      let struct_name = ? struct.name
      if struct_name in generics_map:
        let generic = generics[generics_map[struct_name]]
        return err(fmt"{struct.location} [PE146] struct `{struct_name.asl}` name conflicts with generic `{generic.name.asl}` at {generic.location}")

      if struct_name in structs_map:
        let predefined_struct_location = structs[structs_map[
            struct_name]].location
        return err(fmt"{struct.location} [PE147] struct `{struct_name.asl}` is already defined at {predefined_struct_location}")

      structs_map[struct_name] = index

  var function_defs_hash_map: Table[Hash, int]
  var functions_map: Table[Identifier, seq[int]]
  for index, function in functions:
    if function.name in generics_map:
      let generic = generics[generics_map[function.name]]
      return err(fmt"{function.location} [PE148] function `{function.name.asl}` name conflicts with generic `{generic.name.asl}` at {generic.location}")

    if function.name in structs_map:
      let struct = structs[structs_map[function.name]]
      let struct_name = ? struct.name
      return err(fmt"{function.location} [PE149] function `{function.name.asl}` name conflicts with generic `{struct_name.asl}` at {struct.location}")

    let def_hash = function.def.hash
    if def_hash in function_defs_hash_map:
      let predefined_function_location = functions[function_defs_hash_map[
          def_hash]].location
      return err(fmt"{function.location} [PE150] function `{function.name.asl}` is already defined at {predefined_function_location}")
    function_defs_hash_map[def_hash] = index

    if function.name notin functions_map:
      functions_map[function.name] = new_seq[int]()
    functions_map[function.name].add(index)

  ok(UserModule(def: def, structs: structs, structs_map: structs_map,
      default_struct_index: default_struct_index, generics: generics,
      generics_map: generics_map, functions: functions,
      functions_map: functions_map,
      function_defs_hash_map: function_defs_hash_map))

proc hash*(module: UserModule): Hash = module.def.hash
proc `==`*(self: UserModule, other: UserModule): bool = self.hash == other.hash
proc def*(module: UserModule): UserModuleDefinition = module.def
proc name*(module: UserModule): Identifier = module.def.name
proc location*(module: UserModule): Location = module.def.location
proc generics*(module: UserModule): seq[Generic] = module.generics
proc structs*(module: UserModule): seq[Struct] = module.structs
proc functions*(module: UserModule): seq[Function] = module.functions
proc is_struct*(module: UserModule): bool = module.structs.len > 0

proc module_ref*(module: UserModule): Result[ModuleRef, string] =
  if module.generics.len > 0:
    let children = module.generics.map_it(new_module_ref(it.name))
    new_module_ref(module.name, children)
  else:
    ok(new_module_ref(module.name))

proc find_generic*(module: UserModule, name: Identifier): Result[Generic, string] =
  if name notin module.generics_map:
    err(fmt"{name.location} [PE154] module `{module.name.asl}` does not have any generic named `{name.asl}`")
  else:
    ok(module.generics[module.generics_map[name]])

proc asl(module: UserModule, indent: string): seq[string] =
  var lines = @[module.def.asl]
  for generic in module.generics:
    for line in generic.asl(indent):
      lines.add(indent & line)
  lines.add("\n")
  for struct in module.structs:
    for line in struct.asl(indent):
      lines.add(indent & line)
  lines.add("\n")
  for function in module.functions:
    for line in function.asl(indent):
      lines.add(indent & line)
    lines.add("\n")

  return lines

type NativeFunction* = ref object of RootObj
  def: FunctionDefinition
  native: string

proc new_native_function(native: string, returns: string, name: string,
    args: seq[string]): Result[NativeFunction, string] =
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

  ok(NativeFunction(def: def, native: native))

proc name(function: NativeFunction): Identifier = function.def.name
proc def*(function: NativeFunction): FunctionDefinition = function.def
proc native*(function: NativeFunction): string = function.native

type NativeModule* = ref object of RootObj
  name: Identifier
  generics: seq[Generic]
  generics_map: Table[Identifier, int]
  structs: seq[Struct]
  functions: seq[NativeFunction]
  functions_map: Table[Identifier, seq[int]]
  function_defs_hash_map: Table[Hash, int]

proc new_native_module(name: string, functions: seq[
    NativeFunction]): Result[NativeModule, string] =
  let name = ? new_identifier(name)
  var function_defs_hash_map: Table[Hash, int]
  for index, function in functions.pairs:
    let def_hash = function.def.hash
    if def_hash in function_defs_hash_map:
      return err(fmt"[INTERNAL] - Native function `{function.name.asl}` is defined twice")
    function_defs_hash_map[def_hash] = index

  ok(NativeModule(name: name, functions: functions,
      function_defs_hash_map: function_defs_hash_map))

proc new_native_module(name: string, generics: seq[Generic], structs: seq[
    Struct], functions: seq[NativeFunction]): Result[NativeModule, string] =
  if generics.len + structs.len + functions.len == 0:
    return err(fmt"[INTERNAL ERROR] module can not be empty")

  if generics.len > 0 and structs.len + functions.len == 0:
    return err(fmt"[INTERNAL ERROR] module can not only contain generics")

  var generics_map: Table[Identifier, int]
  for index, generic in generics:
    if generic.name in generics_map:
      let predefined_generic_location = generics[generics_map[
          generic.name]].location
      return err(fmt"{generic.location} [PE144] generic `{generic.name.asl}` is already defined at {predefined_generic_location}")
    generics_map[generic.name] = index

  let name = ? new_identifier(name)
  var function_defs_hash_map: Table[Hash, int]
  for index, function in functions.pairs:
    let def_hash = function.def.hash
    if def_hash in function_defs_hash_map:
      return err(fmt"[INTERNAL] - Native function `{function.name.asl}` is defined twice")
    function_defs_hash_map[def_hash] = index

  ok(NativeModule(name: name, structs: structs, generics: generics,
      generics_map: generics_map, functions: functions,
      function_defs_hash_map: function_defs_hash_map))

proc hash*(module: NativeModule): Hash =
  module.name.hash

proc name*(module: NativeModule): Identifier =
  module.name

proc generics*(module: NativeModule): seq[Generic] =
  module.generics

proc structs*(module: NativeModule): seq[Struct] =
  module.structs

proc functions*(module: NativeModule): seq[NativeFunction] =
  module.functions

proc module_ref*(module: NativeModule): Result[ModuleRef, string] =
  ok(new_module_ref(module.name))

proc find_generic*(module: NativeModule, name: Identifier): Result[Generic, string] =
  if name notin module.generics_map:
    err(fmt"{name.location} [PE154] module `{module.name.asl}` does not have any generic named `{name.asl}`")
  else:
    ok(module.generics[module.generics_map[name]])

proc new_native_error_module(): Result[NativeModule, string] =
  let code_arg = ? new_argument_definition("S32", "code")
  let message_arg = ? new_argument_definition("String", "message")
  let struct = ? new_struct(new_struct_definition(Location()), @[code_arg, message_arg])

  var generics: seq[Generic]
  var functions: seq[NativeFunction]
  new_native_module("Error", generics, @[struct], functions)

proc new_native_status_module(): Result[NativeModule, string] =
  let generic = new_generic( ? new_identifier("Value"), Location())

  let value_arg = ? new_argument_definition("Value", "value")
  let ok_branch = new_struct_definition( ? new_identifier("Ok"), Location())
  let ok_struct = ? new_struct(ok_branch, @[value_arg])

  let err_arg = ? new_argument_definition("Error", "error")
  let err_branch = new_struct_definition( ? new_identifier("Err"), Location())
  let err_struct = ? new_struct(err_branch, @[err_arg])

  var functions: seq[NativeFunction]
  new_native_module("Status", @[generic], @[ok_struct, err_struct], functions)

proc new_native_array_module(): Result[NativeModule, string] =
  let generic = new_generic( ? new_identifier("Item"), Location())

  let size_arg = ? new_argument_definition("U64", "size")
  let struct = ? new_struct(new_struct_definition(Location()), @[size_arg])

  let size_module_ref = new_module_ref( ? new_identifier("U64"))
  let size_arg_name = ? new_identifier("__asl__arg__size__")
  let size_arg_def = new_argument_definition(size_module_ref, size_arg_name)

  let index_module_ref = new_module_ref( ? new_identifier("U64"))
  let index_arg_name = ? new_identifier("__asl__arg__index__")
  let index_arg_def = new_argument_definition(index_module_ref, index_arg_name)

  let item_generic_name = ? new_identifier("Item")
  let item_module_ref = new_module_ref(item_generic_name) # Item
  let item_arg_name = ? new_identifier(fmt"__asl__arg__item__")
  let item_arg_def = new_argument_definition(item_module_ref, item_arg_name)

  let array_module_name = ? new_identifier("Array")
  let array_item_module_ref = ? new_module_ref(array_module_name, @[
      item_module_ref]) # Array[Item]
  let array_item_arg_name = ? new_identifier(fmt"__asl__arg__array__")
  let array_item_arg_def = new_argument_definition(array_item_module_ref, array_item_arg_name)

  let status_module_name = ? new_identifier("Status")
  let status_item_module_ref = ? new_module_ref(status_module_name, @[
      item_module_ref]) # Status[Item]
  let status_array_module_ref = ? new_module_ref(status_module_name, @[
      array_item_module_ref]) # Status[Array[Item]]

  let array_init_fn_name = ? new_identifier("init")
  let array_init_fn_def = ? new_function_definition(array_init_fn_name, @[
      size_arg_def], array_item_module_ref, Location())
  let array_init_native_fn = NativeFunction(def: array_init_fn_def,
      native: "Array_init")

  let array_get_fn_name = ? new_identifier("get")
  let array_get_fn_def = ? new_function_definition(array_get_fn_name, @[
      array_item_arg_def, index_arg_def], status_item_module_ref, Location())
  let array_get_native_fn = NativeFunction(def: array_get_fn_def,
      native: "Array_get")

  let array_set_fn_name = ? new_identifier("set")
  let array_set_fn_def = ? new_function_definition(array_set_fn_name, @[
      array_item_arg_def, index_arg_def, item_arg_def], status_array_module_ref,
      Location())
  let array_set_native_fn = NativeFunction(def: array_set_fn_def,
      native: "Array_set")

  new_native_module("Array", @[generic], @[struct], @[
    array_init_native_fn, array_get_native_fn, array_set_native_fn
  ])

proc native_modules(): Result[seq[NativeModule], string] =
  ok(@[
    ? new_native_module("S8", @[
      ? new_native_function("S8_byte_size", "U64", "byte_size", @["U64"]),
      ? new_native_function("S8_read", "S8", "read", @["Pointer",
          "U64"]),
      ? new_native_function("S8_write", "Pointer", "write", @["S8",
          "Pointer", "U64"]),
    ]),
    ? new_native_module("S16", @[
      ? new_native_function("S16_byte_size", "U64", "byte_size", @["U64"]),
      ? new_native_function("S16_read", "S16", "read", @["Pointer",
          "U64"]),
      ? new_native_function("S16_write", "Pointer", "write", @["S16",
          "Pointer", "U64"]),
    ]),
    ? new_native_module("S32", @[
      ? new_native_function("S32_byte_size", "U64", "byte_size", @["U64"]),
      ? new_native_function("S32_read", "S32", "read", @["Pointer",
          "U64"]),
      ? new_native_function("S32_write", "Pointer", "write", @["S32",
          "Pointer", "U64"]),
    ]),
    ? new_native_module("S64", @[
      ? new_native_function("S64_byte_size", "U64", "byte_size", @["U64"]),
      ? new_native_function("S64_read", "S64", "read", @["Pointer",
          "U64"]),
      ? new_native_function("S64_write", "Pointer", "write", @["S64",
          "Pointer", "U64"]),
      ? new_native_function("S64_add_S64", "S64", "add", @["S64", "S64"]),
      ? new_native_function("S64_subtract_S64", "S64", "subtract", @["S64",
          "S64"]),
      ? new_native_function("S64_multiply_S64", "S64", "multiply", @["S64",
          "S64"]),
      ? new_native_function("S64_remainder_S64", "S64", "remainder", @["S64",
          "S64"]),
      ? new_native_function("S64_quotient_S64", "S64", "quotient", @["S64",
          "S64"]),
      ? new_native_function("S64_compare_S64", "S8", "compare", @["S64",
          "S64"]),
      ? new_native_function("S64_from_U8", "S64", "from", @["U8"]),
      ? new_native_function("S64_from_U64", "S64", "from", @["U64"]),
    ]),
    ? new_native_module("U8", @[
      ? new_native_function("U8_byte_size", "U64", "byte_size", @["U64"]),
      ? new_native_function("U8_read", "U8", "read", @["Pointer",
          "U64"]),
      ? new_native_function("U8_write", "Pointer", "write", @["U8",
          "Pointer", "U64"]),
      ? new_native_function("U8_lshift_U8", "U8", "lshift", @["U8",
          "U64"]),
      ? new_native_function("U8_rshift_U8", "U8", "rshift", @["U8",
          "U64"]),
      ? new_native_function("U8_and_U8", "U8", "and", @["U8",
          "U8"]),
      ? new_native_function("U8_or_U8", "U8", "or", @["U8",
          "U8"]),
      ? new_native_function("U8_not", "U8", "not", @["U8"]),
      ? new_native_function("U8_from_U64", "U8", "from", @["U64"]),
    ]),
    ? new_native_module("U16", @[
      ? new_native_function("U16_byte_size", "U64", "byte_size", @["U64"]),
      ? new_native_function("U16_read", "U16", "read", @["Pointer",
          "U64"]),
      ? new_native_function("U16_write", "Pointer", "write", @["U16",
          "Pointer", "U64"]),
    ]),
    ? new_native_module("U32", @[
      ? new_native_function("U32_byte_size", "U64", "byte_size", @["U64"]),
      ? new_native_function("U32_read", "U32", "read", @["Pointer",
          "U64"]),
      ? new_native_function("U32_write", "Pointer", "write", @["U32",
          "Pointer", "U64"]),
    ]),
    ? new_native_module("U64", @[
      ? new_native_function("U64_byte_size", "U64", "byte_size", @["U64"]),
      ? new_native_function("U64_read", "U64", "read", @["Pointer",
          "U64"]),
      ? new_native_function("U64_write", "Pointer", "write", @["U64",
          "Pointer", "U64"]),
      ? new_native_function("U64_add_U64", "U64", "add", @["U64", "U64"]),
      ? new_native_function("U64_subtract_U64", "U64", "subtract", @["U64",
          "U64"]),
      ? new_native_function("U64_multiply_U64", "U64", "multiply", @["U64",
          "U64"]),
      ? new_native_function("U64_remainder_U64", "U64", "remainder", @["U64",
          "U64"]),
      ? new_native_function("U64_quotient_U64", "U64", "quotient", @["U64",
          "U64"]),
      ? new_native_function("U64_compare_U64", "S8", "compare", @["U64",
          "U64"]),
      ? new_native_function("U64_lshift_U64", "U64", "lshift", @["U64",
          "U64"]),
      ? new_native_function("U64_rshift_U64", "U64", "rshift", @["U64",
          "U64"]),
      ? new_native_function("U64_and_U64", "U64", "and", @["U64",
          "U64"]),
      ? new_native_function("U64_or_U64", "U64", "or", @["U64",
          "U64"]),
      ? new_native_function("U64_not", "U64", "not", @["U64"]),
    ]),
    ? new_native_module("F32", @[
      ? new_native_function("F32_byte_size", "U64", "byte_size", @["U64"]),
      ? new_native_function("F32_read", "F32", "read", @["Pointer",
          "U64"]),
      ? new_native_function("F32_write", "Pointer", "write", @["F32",
          "Pointer", "U64"]),
    ]),
    ? new_native_module("F64", @[
      ? new_native_function("F64_byte_size", "U64", "byte_size", @["U64"]),
      ? new_native_function("F64_read", "F64", "read", @["Pointer",
          "U64"]),
      ? new_native_function("F64_write", "Pointer", "write", @["F64",
          "Pointer", "U64"]),
    ]),
    ? new_native_module("String", @[
      ? new_native_function("String_byte_size", "U64", "byte_size", @["U64"]),
      ? new_native_function("String_read", "String", "read", @[
          "Pointer", "U64"]),
      ? new_native_function("F64_write", "Pointer", "write", @["String",
          "Pointer", "U64"]),
    ]),
    ? new_native_module("Pointer", @[
      ? new_native_function("Pointer_byte_size", "U64", "byte_size", @[
          "U64"]),
      ? new_native_function("Pointer_read", "Pointer", "read", @[
          "Pointer", "U64"]),
      ? new_native_function("Pointer_write", "Pointer", "write", @[
          "Pointer", "Pointer", "U64"]),
    ]),
    ? new_native_error_module(),
    ? new_native_status_module(),
    ? new_native_array_module(),
    ? new_native_module("System", @[
      ? new_native_function("System_allocate", "Pointer", "allocate", @["U64"]),
      ? new_native_function("System_free", "U64", "free", @["Pointer"]),
      ? new_native_function("System_box_U8", "Pointer", "box", @["U8"]),
      ? new_native_function("System_box_U64", "Pointer", "box", @["U64"]),
      ? new_native_function("System_box_S32", "Pointer", "box", @["S32"]),
      ? new_native_function("System_box_S64", "Pointer", "box", @["S64"]),
      ? new_native_function("System_print_U8", "U64", "print", @["U8"]),
      ? new_native_function("System_print_U16", "U64", "print", @["U16"]),
      ? new_native_function("System_print_U32", "U64", "print", @["U32"]),
      ? new_native_function("System_print_U64", "U64", "print", @["U64"]),
      ? new_native_function("System_print_S8", "U64", "print", @["S8"]),
      ? new_native_function("System_print_S16", "U64", "print", @["S16"]),
      ? new_native_function("System_print_S32", "U64", "print", @["S32"]),
      ? new_native_function("System_print_S64", "U64", "print", @["S64"]),
      ? new_native_function("System_print_F32", "U64", "print", @["F32"]),
      ? new_native_function("System_print_F64", "U64", "print", @["F64"]),
      ? new_native_function("System_print_String", "U64", "print", @["String"]),
    ])
  ])

type
  ModuleKind* = enum
    MK_NATIVE, MK_USER
  Module* = ref object of RootObj
    case kind: ModuleKind
    of MK_NATIVE: native: NativeModule
    of MK_USER: user: UserModule

proc new_module*(native: NativeModule): Module =
  Module(kind: MK_NATIVE, native: native)

proc new_module(user: UserModule): Module =
  Module(kind: MK_USER, user: user)

proc kind*(module: Module): ModuleKind = module.kind

proc hash*(module: Module): Hash =
  case module.kind:
  of MK_USER: module.user.hash
  of MK_NATIVE: module.native.hash

proc `==`*(self: Module, other: Module): bool =
  self.hash == other.hash

proc module_ref*(module: Module): Result[ModuleRef, string] =
  case module.kind:
  of MK_NATIVE: module.native.module_ref
  of MK_USER: module.user.module_ref

proc generics*(module: Module): seq[Generic] =
  case module.kind:
  of MK_USER: module.user.generics
  of MK_NATIVE: @[]

proc name*(module: Module): Identifier =
  case module.kind:
  of MK_NATIVE: module.native.name
  of MK_USER: module.user.name

proc native_module*(module: Module): Result[NativeModule, string] =
  case module.kind:
  of MK_NATIVE: ok(module.native)
  of MK_USER: err(fmt"[PE160] [INTERNAL ERROR] module `{module.name.asl}` is not a native module")

proc user_module*(module: Module): Result[UserModule, string] =
  case module.kind:
  of MK_NATIVE: err(fmt"[PE161] [INTERNAL ERROR] module `{module.name.asl}` is not a user module")
  of MK_USER: ok(module.user)

proc location(module: Module): Location =
  case module.kind:
  of MK_NATIVE: Location()
  of MK_USER: module.user.location

proc module_spec(parser: Parser, indent: int): Result[UserModule, string] =
  discard ? parser.expect(indent_spec, indent)
  let def = ? parser.expect(module_definition_spec)

  var generics: seq[Generic]
  discard ? parser.expect(optional_empty_line_spec)
  var maybe_generic = parser.expect(generic_spec, indent + 1)
  while maybe_generic.is_ok:
    generics.add(maybe_generic.get)
    discard ? parser.expect(optional_empty_line_spec)
    maybe_generic = parser.expect(generic_spec, indent + 1)

  var structs: seq[Struct]
  discard ? parser.expect(optional_empty_line_spec)
  var maybe_struct = parser.expect(struct_spec, indent + 1)
  while maybe_struct.is_ok:
    structs.add(maybe_struct.get)
    discard ? parser.expect(optional_empty_line_spec)
    maybe_struct = parser.expect(struct_spec, indent + 1)

  var functions: seq[Function]
  discard ? parser.expect(optional_empty_line_spec)
  var maybe_function = parser.expect(function_spec, indent + 1)
  while maybe_function.is_ok:
    functions.add(maybe_function.get)
    discard ? parser.expect(optional_empty_line_spec)
    maybe_function = parser.expect(function_spec, indent + 1)

  new_user_module(def, generics, structs, functions)

type File* = ref object of RootObj
  path: string
  indent: int
  modules: seq[Module]
  modules_map: Table[Identifier, int]
  native_modules: seq[NativeModule]
  user_modules: seq[UserModule]
  functions: seq[Function]

proc new_file*(path: string, indent: int, user_modules: seq[UserModule],
    functions: seq[Function]): Result[File, string] =
  if functions.len + user_modules.len == 0:
    return err(fmt"{path} [PE163] expected file to have at least a function or module")

  # NOTE: Build index to enable module look by name
  var modules: seq[Module]
  var modules_map: Table[Identifier, int]
  var native_modules: seq[NativeModule]

  for native_module in ( ? native_modules()):
    if native_module.name in modules_map:
      return err(fmt"[INTERNAL] - Native module `{native_module.name.asl} is defined twice")
    native_modules.add(native_module)
    let module = new_module(native_module)
    modules_map[module.name] = modules.len
    modules.add(module)

  for user_module in user_modules:
    if user_module.name in modules_map:
      let predefined_module_location = modules[modules_map[
          user_module.name]].location
      return err(fmt"{user_module.location} [PE165] module `{user_module.name.asl}` is already defined at {predefined_module_location}")

    let module = new_module(user_module)
    modules_map[module.name] = modules.len
    modules.add(module)

  # NOTE: Build index to enable function look up by definition
  var function_defs_hash_map: Table[Hash, int]
  for index, function in functions:
    # NOTE: Validate module and function name collisions
    if function.name in modules_map:
      let module = modules[modules_map[function.name]]
      return err(fmt"{function.location} [PE166] function `{function.name.asl}` conflicts with module `{module.name.asl}` at {module.location}")

    # NOTE: Validate function definition collisions
    let def_hash = function.def.hash
    if def_hash in function_defs_hash_map:
      let predefined_function_location = functions[function_defs_hash_map[
          def_hash]].location
      return err(fmt"{function.location} [PE167] function `{function.name.asl}` is already defined at {predefined_function_location}")
    function_defs_hash_map[def_hash] = index

  ok(File(path: path, indent: indent, native_modules: native_modules,
      user_modules: user_modules, modules: modules, modules_map: modules_map,
      functions: functions))

proc path*(file: File): string = file.path
proc indent*(file: File): int = file.indent
proc native_modules*(file: File): seq[NativeModule] = file.native_modules
proc user_modules*(file: File): seq[UserModule] = file.user_modules
proc functions*(file: File): seq[Function] = file.functions

proc asl*(file: File): string =
  var lines: seq[string]
  let indent = " ".repeat(file.indent)

  for module in file.user_modules:
    for line in module.asl(indent):
      lines.add(line)
    lines.add("\n")

  for function in file.functions:
    for line in function.asl(indent):
      lines.add(line)
    lines.add("\n")

  lines.map_it(it.strip(leading = false)).join("\n").replace(re"\n{3,}", "\n\n")

proc find_module*(file: File, module_name: Identifier): Result[Module, string] =
  # NOTE: Somehow `modules_map` table is not behaving as expected when using `in` operator.
  if module_name in file.modules_map:
    ok(file.modules[file.modules_map[module_name]])
  else:
    err(fmt"{module_name.location} [PE168] module `{module_name.asl}` is not defined in the file {file.path}")

proc file_spec(parser: Parser): Result[File, string] =
  var modules: seq[UserModule]
  var functions: seq[Function]
  while parser.can_parse():
    discard ? parser.expect(optional_empty_line_spec)

    let maybe_module = parser.expect(module_spec, 0)
    if maybe_module.is_ok:
      modules.add(maybe_module.get)
      continue

    let maybe_function = parser.expect(function_spec, 0)
    if maybe_function.is_ok:
      functions.add(maybe_function.get)
      continue

    let token = ? parser.peek()
    return err(fmt"{token.location} expected a module or function but found {token.value}")

  new_file(parser.path, parser.indent, modules, functions)

proc parse*(path: string, tokens: seq[Token]): Result[File, string] =
  let parser = Parser(path: path, tokens: tokens, indent: INDENT_SIZE)
  let file = ? parser.expect(file_spec)
  ok(file)
