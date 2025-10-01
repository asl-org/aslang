import results, strformat, options

import tokenizer

type Identifier = ref object of RootObj
  name: string
  location: Location

proc new_identifier(name: string, location: Location): Identifier =
  Identifier(name: name, location: location)

type
  ArgumentTypeKind = enum
    ATK_SIMPLE, ATK_NESTED
  ArgumentType = ref object of RootObj
    argtype: Identifier
    case kind: ArgumentTypeKind
    of ATK_SIMPLE: discard
    of ATK_NESTED: children: seq[ArgumentType]

proc new_argument_type(argtype: Identifier): ArgumentType =
  ArgumentType(kind: ATK_SIMPLE, argtype: argtype)

proc new_argument_type(argtype: Identifier, children: seq[
    ArgumentType]): ArgumentType =
  ArgumentType(kind: ATK_NESTED, argtype: argtype, children: children)

type ArgumentDefinition = ref object of RootObj
  name: Identifier
  argtype: ArgumentType

proc new_argument_definition(name: Identifier,
    argtype: ArgumentType): ArgumentDefinition =
  ArgumentDefinition(name: name, argtype: argtype)

type
  StructDefinitionKind = enum
    SK_DEFAULT, SK_NAMED
  StructDefinition = ref object of RootObj
    location: Location
    case kind: StructDefinitionKind
    of SK_DEFAULT: discard
    of SK_NAMED: name: Identifier

proc new_struct_definition(location: Location): StructDefinition =
  StructDefinition(kind: SK_DEFAULT, location: location)

proc new_struct_definition(name: Identifier,
    location: Location): StructDefinition =
  StructDefinition(kind: SK_NAMED, name: name, location: location)

type Struct = ref object of RootObj
  def: StructDefinition
  fields: seq[ArgumentDefinition]

proc new_struct(def: StructDefinition, fields: seq[
    ArgumentDefinition]): Struct =
  Struct(def: def, fields: fields)

type FunctionDefinition = ref object of RootObj
  name: Identifier
  returns: ArgumentType
  args: seq[ArgumentDefinition]
  location: Location

proc new_function_definition(name: Identifier, args: seq[ArgumentDefinition],
    returns: ArgumentType, location: Location): FunctionDefinition =
  FunctionDefinition(name: name, args: args, returns: returns,
      location: location)

type
  LiteralKind = enum
    LK_INTEGER, LK_FLOAT, LK_STRING
  Literal = ref object of RootObj
    kind: LiteralKind
    value: string
    location: Location

proc new_integer_literal(value: string, location: Location): Literal =
  Literal(kind: LK_INTEGER, value: value, location: location)

proc new_float_literal(value: string, location: Location): Literal =
  Literal(kind: LK_FLOAT, value: value, location: location)

proc new_string_literal(value: string, location: Location): Literal =
  Literal(kind: LK_STRING, value: value, location: location)

type
  ArgumentKind = enum
    AK_LITERAL, AK_VARIABLE
  Argument = ref object of RootObj
    case kind: ArgumentKind
    of AK_LITERAL: literal: Literal
    of AK_VARIABLE: variable: Identifier

proc new_argument(literal: Literal): Argument =
  Argument(kind: AK_LITERAL, literal: literal)

proc new_argument(variable: Identifier): Argument =
  Argument(kind: AK_VARIABLE, variable: variable)

type
  FunctionRefKind = enum
    FRK_LOCAL, FRK_MODULE
  FunctionRef = ref object of RootObj
    name: Identifier
    case kind: FunctionRefKind
    of FRK_LOCAL: discard
    of FRK_MODULE: module: ArgumentType

proc new_function_ref(name: Identifier): FunctionRef =
  FunctionRef(kind: FRK_LOCAL, name: name)

proc new_function_ref(name: Identifier, module: ArgumentType): FunctionRef =
  FunctionRef(kind: FRK_MODULE, name: name, module: module)

type FunctionCall = ref object of RootObj
  fnref: FunctionRef
  args: seq[Argument]

proc new_function_call(fnref: FunctionRef, args: seq[Argument]): FunctionCall =
  FunctionCall(fnref: fnref, args: args)

type LiteralInit = ref object of RootObj
  module: ArgumentType
  literal: Literal

proc new_literal_init(module: ArgumentType, literal: Literal): LiteralInit =
  LiteralInit(module: module, literal: literal)

type KeywordArgument = ref object of RootObj
  name: Identifier
  value: Argument

proc new_keyword_argument(name: Identifier, value: Argument): KeywordArgument =
  KeywordArgument(name: name, value: value)

type
  StructRefKind = enum
    SRK_DEFAULT, SRK_NAMED
  StructRef = ref object of RootObj
    module: ArgumentType
    case kind: StructRefKind
    of SRK_DEFAULT: discard
    of SRK_NAMED: struct: Identifier

proc new_struct_ref(module: ArgumentType): StructRef =
  StructRef(kind: SRK_DEFAULT, module: module)

proc new_struct_ref(module: ArgumentType, struct: Identifier): StructRef =
  StructRef(kind: SRK_NAMED, module: module, struct: struct)

type StructInit = ref object of RootObj
  struct_ref: StructRef
  args: seq[KeywordArgument]

proc new_struct_init(struct_ref: StructRef, args: seq[
    KeywordArgument]): StructInit =
  StructInit(struct_ref: struct_ref, args: args)

type
  InitializerKind = enum
    IK_LITERAL, IK_STRUCT
  Initializer = ref object of RootObj
    case kind: InitializerKind
    of IK_LITERAL: literal_init: LiteralInit
    of IK_STRUCT: struct_init: StructInit

proc new_initializer(literal_init: LiteralInit): Initializer =
  Initializer(kind: IK_LITERAL, literal_init: literal_init)

proc new_initializer(struct_init: StructInit): Initializer =
  Initializer(kind: IK_STRUCT, struct_init: struct_init)

type StructGet = ref object of RootObj
  name: Identifier
  field: Identifier

proc new_struct_get(name: Identifier, field: Identifier): StructGet =
  StructGet(name: name, field: field)

type
  ExpressionKind = enum
    EK_FNCALL, EK_INIT, EK_STRUCT_GET
  Expression = ref object of RootObj
    case kind: ExpressionKind
    of EK_FNCALL: fncall: FunctionCall
    of EK_INIT: init: Initializer
    of EK_STRUCT_GET: struct_get: StructGet

proc new_expression(fncall: FunctionCall): Expression =
  Expression(kind: EK_FNCALL, fncall: fncall)

proc new_expression(init: Initializer): Expression =
  Expression(kind: EK_INIT, init: init)

proc new_expression(struct_get: StructGet): Expression =
  Expression(kind: EK_STRUCT_GET, struct_get: struct_get)

type Assignment = ref object of RootObj
  arg: Identifier
  expression: Expression

proc new_assignment(arg: Identifier, expression: Expression): Assignment =
  Assignment(arg: arg, expression: expression)

type
  FunctionStepKind = enum
    FSK_EXPR, FSK_ASSIGN
  FunctionStep = ref object of RootObj
    case kind: FunctionStepKind
    of FSK_EXPR: expression: Expression
    of FSK_ASSIGN: assignment: Assignment

proc new_function_step(expression: Expression): FunctionStep =
  FunctionStep(kind: FSK_EXPR, expression: expression)

proc new_function_step(assignment: Assignment): FunctionStep =
  FunctionStep(kind: FSK_ASSIGN, assignment: assignment)

type Function = ref object of RootObj
  def: FunctionDefinition
  steps: seq[FunctionStep]

proc new_function(def: FunctionDefinition, steps: seq[FunctionStep]): Function =
  Function(def: def, steps: steps)

type Generic = ref object of RootObj
  name: Identifier
  defs: seq[FunctionDefinition]

type ModuleDefinition = ref object of RootObj
  name: Identifier
  location: Location

proc new_module_definition(name: Identifier,
    location: Location): ModuleDefinition =
  ModuleDefinition(name: name, location: location)

type Module = ref object of RootObj
  def: ModuleDefinition
  structs: seq[Struct]
  generics: seq[Generic]
  functions: seq[Function]

proc new_module(def: ModuleDefinition, structs: seq[Struct], generics: seq[
    Generic], functions: seq[Function]): Module =
  Module(def: def, structs: structs, generics: generics, functions: functions)

type File = ref object of RootObj
  modules: seq[Module]
  functions: seq[Function]

proc new_file(modules: seq[Module], functions: seq[Function]): File =
  File(modules: modules, functions: functions)

# NOTE: The parser assumes that the editor used to write code
# must automatically strip off the trailing spaces and also
# add the new line at the end of file if not present. This is
# a conscious choice to ensure the consistent syntax with
# minimal configuration.
type Parser = ref object of RootObj
  tokens: seq[Token]
  index: int = 0
  indent: int = 2 # 2 spaces as indent
  checkpoints: seq[int]

type ParserSpec[T] = proc(parser: Parser): Result[T, string]
type IndentParseSpec[T] = proc(parser: Parser, indent: int): Result[T, string]

proc can_parse(parser: Parser): bool =
  parser.index < parser.tokens.len

proc peek(parser: Parser): Result[Token, string] =
  if parser.can_parse():
    ok(parser.tokens[parser.index])
  else:
    err(fmt"reached end of token stream")

proc expect[T](parser: Parser, spec: ParserSpec[T]): Result[T, string] =
  let start = parser.index
  let maybe_value = spec(parser)
  if maybe_value.is_err:
    parser.index = start
    return err(maybe_value.error)
  return maybe_value

proc expect[T](parser: Parser, spec: IndentParseSpec[T], indent: int): Result[
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
proc space_consumer_spec(parser: Parser): Result[int, string] =
  var count = 0
  var maybe_space = parser.expect(space_spec)
  while maybe_space.is_ok:
    count += 1
    maybe_space = parser.expect(space_spec)
  ok(count)

proc comment_spec(parser: Parser): Result[Token,
    string] = parser.token_spec_util(TK_COMMENT)

# NOTE: This spec is also used to consume trailing line content
proc empty_line_spec(parser: Parser): Result[void, string] =
  # NOTE: Existence of space does not matter at all.
  discard ? parser.expect(space_consumer_spec)
  # NOTE: Existence of comment does not matter at all.
  discard parser.expect(comment_spec)
  # NOTE: Every line must end with a new line.
  discard ? parser.expect(new_line_spec)
  ok()

proc empty_line_consumer_spec(parser: Parser): Result[void, string] =
  var maybe_empty_line = parser.expect(empty_line_spec)
  while maybe_empty_line.is_ok:
    maybe_empty_line = parser.expect(empty_line_spec)
  ok()

# NOTE: Configure indent size here.
proc indent_spec(parser: Parser, indent: int): Result[int, string] =
  # NOTE: this token is the start of line
  let token = ? parser.peek()

  let spaces = ? parser.expect(space_consumer_spec)
  if spaces == indent * parser.indent:
    ok(spaces)
  else:
    err(fmt"{token.location} indentation error: expected `{indent * parser.indent}` space but found `{spaces}`")

# identifier specs
proc identifier_head_spec(parser: Parser): Result[Token, string] =
  let maybe_underscore = parser.token_spec_util(TK_UNDERSCORE)
  if maybe_underscore.is_ok: return maybe_underscore

  let maybe_alphabets = parser.token_spec_util(TK_ALPHABETS)
  if maybe_alphabets.is_ok: return maybe_alphabets

  let token = ? parser.peek()
  err(fmt"{token.location} expected an underscore `_` or alphabet `[a-zA-Z]` but found {token.value}")

proc identifier_tail_spec(parser: Parser): Result[Token, string] =
  let maybe_id_head = parser.expect(identifier_head_spec)
  if maybe_id_head.is_ok: return maybe_id_head

  let maybe_digits = parser.token_spec_util(TK_DIGITS)
  if maybe_digits.is_ok: return maybe_digits

  let token = ? parser.peek()
  err(fmt"{token.location} expected an underscore `_`, alphabet `[a-zA-Z]` or digit `[0-9]` but found {token.value}")

proc identifier_spec(parser: Parser): Result[Identifier, string] =
  let id_head = ? parser.expect(identifier_head_spec)
  var name = id_head.value
  var location = id_head.location

  var maybe_id_tail = parser.expect(identifier_tail_spec)
  while maybe_id_tail.is_ok:
    name.add(maybe_id_tail.get.value)
    maybe_id_tail = parser.expect(identifier_tail_spec)

  ok(new_identifier(name, location))

# module spec
proc module_definition_spec(parser: Parser): Result[ModuleDefinition, string] =
  let module_keyword = ? parser.expect(module_keyword_spec)

  discard ? parser.expect(space_spec)
  discard ? parser.expect(space_consumer_spec)

  let name = ? parser.expect(identifier_spec)

  discard ? parser.expect(space_consumer_spec)
  discard ? parser.expect(colon_spec)

  ok(new_module_definition(name, module_keyword.location))

proc struct_default_definition_spec(parser: Parser, indent: int): Result[
    StructDefinition, string] =
  discard ? parser.expect(indent_spec, indent)

  let struct_keyword = ? parser.expect(struct_keyword_spec)
  discard ? parser.expect(space_consumer_spec)

  discard ? parser.expect(colon_spec)
  ? parser.expect(empty_line_spec)

  ok(new_struct_definition(struct_keyword.location))

proc struct_named_definition_spec(parser: Parser, indent: int): Result[
    StructDefinition, string] =
  discard ? parser.expect(indent_spec, indent)

  let struct_keyword = ? parser.expect(struct_keyword_spec)
  discard ? parser.expect(space_consumer_spec)

  let name = ? parser.expect(identifier_spec)
  discard ? parser.expect(space_consumer_spec)

  discard ? parser.expect(colon_spec)
  ? parser.expect(empty_line_spec)

  ok(new_struct_definition(name, struct_keyword.location))

proc struct_definition_spec(parser: Parser, indent: int): Result[
    StructDefinition, string] =
  let maybe_struct_default_def = parser.expect(struct_default_definition_spec, indent)
  if maybe_struct_default_def.is_ok:
    return maybe_struct_default_def

  let maybe_struct_named_def = parser.expect(struct_named_definition_spec, indent)
  if maybe_struct_named_def.is_ok:
    return maybe_struct_named_def

  let token = ? parser.peek()
  err(fmt"{token.location} expected a struct definition")

proc argument_type_spec(parser: Parser): Result[ArgumentType, string] =
  let argtype = ? parser.expect(identifier_spec)

  var maybe_open_square_bracket = parser.expect(open_square_bracket_spec)
  if maybe_open_square_bracket.is_err:
    return ok(new_argument_type(argtype))

  discard ? parser.expect(space_consumer_spec)

  # at least one child is necessary
  var children: seq[ArgumentType]
  children.add( ? parser.expect(argument_type_spec))
  discard ? parser.expect(space_consumer_spec)

  var maybe_comma = parser.expect(comma_spec)
  while maybe_comma.is_ok:
    discard ? parser.expect(space_consumer_spec)

    var child_argtype = ? parser.expect(argument_type_spec)
    children.add(child_argtype)

    discard ? parser.expect(space_consumer_spec)
    maybe_comma = parser.expect(comma_spec)

  discard ? parser.expect(close_square_bracket_spec)
  ok(new_argument_type(argtype, children))

proc argument_definition_spec(parser: Parser): Result[
    ArgumentDefinition, string] =
  let argtype = ? parser.expect(argument_type_spec)
  discard ? parser.expect(space_consumer_spec)
  let name = ? parser.expect(identifier_spec)
  ok(new_argument_definition(name, argtype))

proc struct_field_definition_spec(parser: Parser, indent: int): Result[
    ArgumentDefinition, string] =
  discard ? parser.expect(indent_spec, indent)
  let field = ? parser.expect(argument_definition_spec)
  ? parser.expect(empty_line_spec)
  ok(field)

proc struct_spec(parser: Parser, indent: int): Result[Struct, string] =
  let def = ? parser.expect(struct_definition_spec, indent)
  ? parser.expect(empty_line_consumer_spec)

  var fields: seq[ArgumentDefinition]
  # NOTE: struct must always at least have 1 field.
  fields.add( ? parser.expect(struct_field_definition_spec, indent + 1))
  ? parser.expect(empty_line_consumer_spec)

  var maybe_field = parser.expect(struct_field_definition_spec, indent + 1)
  while maybe_field.is_ok:
    fields.add(maybe_field.get)
    ? parser.expect(empty_line_consumer_spec)
    maybe_field = parser.expect(struct_field_definition_spec, indent + 1)

  ok(new_struct(def, fields))

proc function_definition_spec(parser: Parser, indent: int): Result[
    FunctionDefinition, string] =
  discard ? parser.expect(indent_spec, indent)
  let fn_keyword = ? parser.expect(fn_keyword_spec)

  discard ? parser.expect(space_spec)
  discard ? parser.expect(space_consumer_spec)

  let name = ? parser.expect(identifier_spec)

  discard ? parser.expect(open_paren_bracket_spec)
  var args: seq[ArgumentDefinition]

  discard ? parser.expect(space_consumer_spec)
  # NOTE: Every function must have an input argument
  args.add( ? parser.expect(argument_definition_spec))
  discard ? parser.expect(space_consumer_spec)

  var maybe_comma = parser.expect(comma_spec)
  while maybe_comma.is_ok:
    discard ? parser.expect(space_consumer_spec)
    args.add( ? parser.expect(argument_definition_spec))
    discard ? parser.expect(space_consumer_spec)

    maybe_comma = parser.expect(comma_spec)

  discard ? parser.expect(close_paren_bracket_spec)
  discard ? parser.expect(space_consumer_spec)

  discard ? parser.expect(colon_spec)
  discard ? parser.expect(space_consumer_spec)

  let returns = ? parser.expect(argument_type_spec)
  ok(new_function_definition(name, args, returns, fn_keyword.location))

proc sign_spec(parser: Parser): Result[Token, string] =
  let maybe_plus = parser.token_spec_util(TK_PLUS)
  if maybe_plus.is_ok: return maybe_plus

  let maybe_minus = parser.token_spec_util(TK_MINUS)
  if maybe_minus.is_ok: return maybe_minus

  let token = ? parser.peek()
  err(fmt"{token.location} expected `+` or `-` but found `{token.value}`")

proc unsigned_integer_spec(parser: Parser): Result[Literal, string] =
  # TODO: Support underscore separated values as integers as well.
  let int_value_token = ? parser.token_spec_util(TK_DIGITS)
  ok(new_integer_literal(int_value_token.value, int_value_token.location))

proc signed_integer_spec(parser: Parser): Result[Literal, string] =
  var sign = ? parser.expect(sign_spec)
  let unsigned_intvalue = ? parser.expect(unsigned_integer_spec)
  var value = sign.value & unsigned_intvalue.value
  ok(new_integer_literal(value, sign.location))

proc integer_spec(parser: Parser): Result[Literal, string] =
  let maybe_unsigned_integer = parser.expect(unsigned_integer_spec)
  if maybe_unsigned_integer.is_ok:
    return maybe_unsigned_integer

  let maybe_signed_integer = parser.expect(signed_integer_spec)
  if maybe_signed_integer.is_ok:
    return maybe_signed_integer

  let token = ? parser.peek()
  err(fmt"{token.location} expected a valid integer literal but found `{token.value}`")

proc float_spec(parser: Parser): Result[Literal, string] =
  # TODO: Improve float parsing to support scientific notation as well.
  let first = ? parser.expect(integer_spec)
  let dot = ? parser.expect(dot_spec)
  let second = ? parser.expect(unsigned_integer_spec)
  ok(new_float_literal(first.value & dot.value & second.value, first.location))

proc string_spec(parser: Parser): Result[Literal, string] =
  let token = ? parser.token_spec_util(TK_STRING)
  ok(new_string_literal(token.value, token.location))

proc literal_spec(parser: Parser): Result[Literal, string] =
  let maybe_integer = parser.expect(integer_spec)
  if maybe_integer.is_ok:
    return maybe_integer

  let maybe_float = parser.expect(float_spec)
  if maybe_float.is_ok:
    return maybe_float

  let maybe_string = parser.expect(string_spec)
  if maybe_string.is_ok:
    return maybe_string

proc argument_spec(parser: Parser): Result[Argument, string] =
  let maybe_identifier = parser.expect(identifier_spec)
  if maybe_identifier.is_ok:
    return ok(new_argument(maybe_identifier.get))

  let maybe_literal = parser.expect(literal_spec)
  if maybe_literal.is_ok:
    return ok(new_argument(maybe_literal.get))

  let token = ? parser.peek()
  err(fmt"{token.location} expected a valid argument to function call but found `{token.value}`")

proc function_ref_local_spec(parser: Parser): Result[FunctionRef, string] =
  let name = ? parser.expect(identifier_spec)
  ok(new_function_ref(name))

proc function_ref_module_spec(parser: Parser): Result[FunctionRef, string] =
  let argtype = ? parser.expect(argument_type_spec)
  discard ? parser.expect(dot_spec)
  let name = ? parser.expect(identifier_spec)
  ok(new_function_ref(name, argtype))

proc function_ref_spec(parser: Parser): Result[FunctionRef, string] =
  let maybe_module_fnref = parser.expect(function_ref_module_spec)
  if maybe_module_fnref.is_ok:
    return maybe_module_fnref

  let maybe_local_fnref = parser.expect(function_ref_local_spec)
  if maybe_local_fnref.is_ok:
    return maybe_local_fnref

  let token = ? parser.peek()
  err(fmt"{token.location} expected a function call but found {token.value}")

proc function_call_spec(parser: Parser): Result[FunctionCall, string] =
  let fnref = ? parser.expect(function_ref_spec)
  discard ? parser.expect(open_paren_bracket_spec)

  var args: seq[Argument]
  discard ? parser.expect(space_consumer_spec)
  # NOTE: every function call must have at least one argument
  args.add( ? parser.expect(argument_spec))
  discard ? parser.expect(space_consumer_spec)

  var maybe_comma = parser.expect(comma_spec)
  while maybe_comma.is_ok:
    discard ? parser.expect(space_consumer_spec)
    args.add( ? parser.expect(argument_spec))
    discard ? parser.expect(space_consumer_spec)
    maybe_comma = parser.expect(comma_spec)

  discard ? parser.expect(close_paren_bracket_spec)
  ok(new_function_call(fnref, args))

proc literal_init_spec(parser: Parser): Result[LiteralInit, string] =
  let argtype = ? parser.expect(argument_type_spec)
  discard ? parser.expect(space_spec)
  discard ? parser.expect(space_consumer_spec)
  let literal = ? parser.expect(literal_spec)
  ok(new_literal_init(argtype, literal))

proc keyword_argument_spec(parser: Parser): Result[KeywordArgument, string] =
  let name = ? parser.expect(identifier_spec)
  discard ? parser.expect(space_consumer_spec)
  discard ? parser.expect(colon_spec)
  discard ? parser.expect(space_consumer_spec)
  let value = ? parser.expect(argument_spec)
  ok(new_keyword_argument(name, value))

proc struct_ref_spec(parser: Parser): Result[StructRef, string] =
  let module = ? parser.expect(argument_type_spec)

  let maybe_dot = parser.expect(dot_spec)
  if maybe_dot.is_err:
    return ok(new_struct_ref(module))

  let struct = ? parser.expect(identifier_spec)
  ok(new_struct_ref(module, struct))

proc struct_init_spec(parser: Parser): Result[StructInit, string] =
  let struct_ref = ? parser.expect(struct_ref_spec)
  discard ? parser.expect(space_consumer_spec)
  discard ? parser.expect(open_curly_bracket_spec)

  discard ? parser.expect(space_consumer_spec)
  var args: seq[KeywordArgument]
  # NOTE: every struct init must have at least one keyword argument
  args.add( ? parser.expect(keyword_argument_spec))
  discard ? parser.expect(space_consumer_spec)
  var maybe_comma = parser.expect(comma_spec)
  while maybe_comma.is_ok:
    discard ? parser.expect(space_consumer_spec)
    args.add( ? parser.expect(keyword_argument_spec))
    discard ? parser.expect(space_consumer_spec)
    maybe_comma = parser.expect(comma_spec)

  discard ? parser.expect(close_curly_bracket_spec)
  ok(new_struct_init(struct_ref, args))

proc initializer_spec(parser: Parser): Result[Initializer, string] =
  let maybe_literal_init = parser.expect(literal_init_spec)
  if maybe_literal_init.is_ok:
    return ok(new_initializer(maybe_literal_init.get))

  let maybe_struct_init = parser.expect(struct_init_spec)
  if maybe_struct_init.is_ok:
    return ok(new_initializer(maybe_struct_init.get))

  let token = ? parser.peek()
  err(fmt"{token.location} expected an initializer but found {token.value}")

proc struct_get_spec(parser: Parser): Result[StructGet, string] =
  let name = ? parser.expect(identifier_spec)
  discard ? parser.expect(dot_spec)
  let field = ? parser.expect(identifier_spec)
  ok(new_struct_get(name, field))

proc expression_spec(parser: Parser): Result[Expression, string] =
  let maybe_fncall = parser.expect(function_call_spec)
  if maybe_fncall.is_ok:
    return ok(new_expression(maybe_fncall.get))

  let maybe_init = parser.expect(initializer_spec)
  if maybe_init.is_ok:
    return ok(new_expression(maybe_init.get))

  let maybe_struct_get = parser.expect(struct_get_spec)
  if maybe_struct_get.is_ok:
    return ok(new_expression(maybe_struct_get.get))

  let token = ? parser.peek()
  err(fmt"{token.location} expected a valid expression but found {token.value}")

proc assignment_spec(parser: Parser): Result[Assignment, string] =
  let arg = ? parser.expect(identifier_spec)
  discard ? parser.expect(space_consumer_spec)
  discard ? parser.expect(equal_spec)
  discard ? parser.expect(space_consumer_spec)
  let expression = ? parser.expect(expression_spec)
  ok(new_assignment(arg, expression))

proc function_step_spec(parser: Parser, indent: int): Result[FunctionStep, string] =
  discard ? parser.expect(indent_spec, indent)

  let maybe_assignment = parser.expect(assignment_spec)
  if maybe_assignment.is_ok:
    return ok(new_function_step(maybe_assignment.get))

  let maybe_expression = parser.expect(expression_spec)
  if maybe_expression.is_ok:
    return ok(new_function_step(maybe_expression.get))

  let token = ? parser.peek()
  err(fmt"{token.location} expected either an expression or assignment but found `{token.value}`")

proc function_spec(parser: Parser, indent: int): Result[Function, string] =
  let def = ? parser.expect(function_definition_spec, indent)
  ? parser.expect(empty_line_consumer_spec)

  var steps: seq[FunctionStep]
  # NOTE: Function must have at least 1 expression.
  steps.add( ? parser.expect(function_step_spec, indent + 1))
  ? parser.expect(empty_line_consumer_spec)

  var maybe_expression = parser.expect(function_step_spec, indent + 1)
  while maybe_expression.is_ok:
    steps.add(maybe_expression.get)
    ? parser.expect(empty_line_consumer_spec)
    maybe_expression = parser.expect(function_step_spec, indent + 1)

  ok(new_function(def, steps))

proc module_spec(parser: Parser, indent: int): Result[Module, string] =
  discard ? parser.expect(indent_spec, indent)
  let def = ? parser.expect(module_definition_spec)
  var structs: seq[Struct]
  var functions: seq[Function]

  while parser.can_parse():
    ? parser.expect(empty_line_consumer_spec)

    let maybe_struct = parser.expect(struct_spec, indent + 1)
    if maybe_struct.is_ok:
      structs.add(maybe_struct.get)

    let maybe_function = parser.expect(function_spec, indent + 1)
    if maybe_function.is_ok:
      functions.add(maybe_function.get)

    break
  ok(new_module(def, structs, @[], functions))

proc parse*(tokens: seq[Token]): Result[File, string] =
  var parser = Parser(tokens: tokens)

  var modules: seq[Module]
  var functions: seq[Function]
  while parser.can_parse():
    ? parser.expect(empty_line_consumer_spec)

    let maybe_module = parser.expect(module_spec, 0)
    if maybe_module.is_ok:
      modules.add(maybe_module.get)
      continue

    let maybe_function = parser.expect(function_spec, 0)
    if maybe_function.is_ok:
      functions.add(maybe_function.get)
      continue

    let token = ? parser.peek()
    return err(fmt"TODO: unexpected token at {token.location}")

  ok(new_file(modules, functions))
